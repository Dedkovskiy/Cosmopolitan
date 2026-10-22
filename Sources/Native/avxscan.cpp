// AVX detection for Windows executables, in-process. Walks every executable section of a PE32+ file with an x86-64 instruction-length
// decoder (prefixes, REX, VEX2/VEX3, EVEX, 1/2/3-byte opcode maps, ModRM/SIB/displacement, immediates) and counts VEX and EVEX
// encodings. Counting raw C4/C5 bytes would be wrong (they also occur inside immediates and displacements); decoding instruction
// boundaries is what makes the count trustworthy. In 64-bit mode C4/C5/62 at an instruction start are always VEX/EVEX.
// Rare opcodes with unusual immediates may be mis-sized by a byte; the decoder re-synchronises within a few instructions, which is
// why the result is a count, not a listing.
#include "cosmo_native.h"
#include "native_file.h"
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <new>
#include <vector>

namespace {

struct Reader { const uint8_t *p; size_t n; };

// Does a one-byte opcode take a ModRM byte?
inline bool modrm1(uint8_t op) {
    if (op < 0x40) return (op & 7) < 4;              // ALU r/m forms
    if (op >= 0x40 && op < 0x60) return false;        // REX / push / pop (REX handled before)
    switch (op) {
        case 0x62: case 0x63: case 0x69: case 0x6B: return true;
        case 0x80: case 0x81: case 0x83: case 0x84: case 0x85: case 0x86: case 0x87:
        case 0x88: case 0x89: case 0x8A: case 0x8B: case 0x8C: case 0x8D: case 0x8E: case 0x8F: return true;
        case 0xC0: case 0xC1: case 0xC4: case 0xC5: case 0xC6: case 0xC7: return true;
        case 0xD0: case 0xD1: case 0xD2: case 0xD3: return true;
        case 0xF6: case 0xF7: case 0xFE: case 0xFF: return true;
        default: return op >= 0xD8 && op <= 0xDF;    // x87
    }
}
// Immediate size for a one-byte opcode (ModRM reg field needed for F6/F7 groups). opsize: 2 if 0x66 prefix active, else 4; rexw: REX.W.
inline int imm1(uint8_t op, int opsize, bool rexw, int modrm_reg) {
    switch (op) {
        case 0x04: case 0x0C: case 0x14: case 0x1C: case 0x24: case 0x2C: case 0x34: case 0x3C:
        case 0x6A: case 0x6B: case 0x80: case 0x82: case 0x83: case 0xA8: case 0xC0: case 0xC1: case 0xC6: case 0xCD: case 0xD4: case 0xD5: case 0xEB: return 1;
        case 0x70: case 0x71: case 0x72: case 0x73: case 0x74: case 0x75: case 0x76: case 0x77:
        case 0x78: case 0x79: case 0x7A: case 0x7B: case 0x7C: case 0x7D: case 0x7E: case 0x7F: return 1;
        case 0xB0: case 0xB1: case 0xB2: case 0xB3: case 0xB4: case 0xB5: case 0xB6: case 0xB7: return 1;
        case 0x05: case 0x0D: case 0x15: case 0x1D: case 0x25: case 0x2D: case 0x35: case 0x3D: case 0x68: case 0x69: case 0x81: case 0xA9: case 0xC7: return opsize;
        case 0xE8: case 0xE9: return 4;
        case 0xC2: case 0xCA: return 2;
        case 0xC8: return 3;
        case 0xA0: case 0xA1: case 0xA2: case 0xA3: return 8;   // moffs64
        case 0xF6: return modrm_reg < 2 ? 1 : 0;
        case 0xF7: return modrm_reg < 2 ? opsize : 0;
        default:
            if (op >= 0xB8 && op <= 0xBF) return rexw ? 8 : opsize;
            return 0;
    }
}
// 0F-map: ModRM present except for these.
inline bool modrm2(uint8_t op) {
    switch (op) {
        case 0x05: case 0x06: case 0x07: case 0x08: case 0x09: case 0x0B: case 0x0E: case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x37:
        case 0x77: case 0xA0: case 0xA1: case 0xA2: case 0xA8: case 0xA9: case 0xAA: case 0xC8: case 0xC9: case 0xCA: case 0xCB: case 0xCC: case 0xCD: case 0xCE: case 0xCF: return false;
        default: return !(op >= 0x80 && op <= 0x8F);
    }
}
inline int imm2(uint8_t op, int opsize) {
    if (op >= 0x80 && op <= 0x8F) return 4;            // Jcc rel32
    switch (op) { case 0x70: case 0x71: case 0x72: case 0x73: case 0xA4: case 0xAC: case 0xBA: case 0xC2: case 0xC4: case 0xC5: case 0xC6: return 1; default: (void)opsize; return 0; }
}

// Consume ModRM (+SIB, displacement). Returns bytes used, or -1 if truncated. Sets reg field.
inline int modrm_len(const uint8_t *p, size_t n, int &reg) {
    if (n < 1) return -1;
    uint8_t m = p[0], mod = m >> 6, rm = m & 7; reg = (m >> 3) & 7;
    int len = 1;
    if (mod == 3) return len;
    if (rm == 4) { if (n < 2) return -1; uint8_t sib = p[1]; len++; if ((sib & 7) == 5 && mod == 0) len += 4; }
    else if (mod == 0 && rm == 5) len += 4;   // RIP-relative
    if (mod == 1) len += 1; else if (mod == 2) len += 4;
    return len;
}

void scan(const uint8_t *code, size_t size, cosmo_avx_result &r) {
    size_t i = 0;
    while (i < size) {
        size_t s = i; int opsize = 4; bool rexw = false;
        // legacy prefixes
        while (i < size) { uint8_t b = code[i]; if (b == 0x66) { opsize = 2; i++; } else if (b == 0x67 || b == 0xF2 || b == 0xF3 || b == 0xF0 || b == 0x2E || b == 0x36 || b == 0x3E || b == 0x26 || b == 0x64 || b == 0x65) i++; else break; }
        if (i >= size) break;
        uint8_t b = code[i];
        int reg = 0, ml;
        if (b == 0xC5 || b == 0xC4 || b == 0x62) {                     // VEX2 / VEX3 / EVEX
            int map = 1; size_t plen = (b == 0xC5) ? 2 : (b == 0xC4 ? 3 : 4);
            if (i + plen >= size) break;
            if (b == 0xC4) map = code[i + 1] & 0x1F; else if (b == 0x62) map = code[i + 1] & 0x07;
            uint8_t op = code[i + plen]; i += plen + 1;
            if (b == 0x62) r.evex++; else r.vex++;
            bool has_modrm = !(map == 1 && op == 0x77);                // vzeroupper / vzeroall
            if (has_modrm) { ml = modrm_len(code + i, size - i, reg); if (ml < 0) break; i += ml; }
            if (map == 3 || (map == 1 && (op == 0x70 || op == 0x71 || op == 0x72 || op == 0x73 || op == 0xC2 || op == 0xC4 || op == 0xC5 || op == 0xC6))) i += 1;   // imm8
        } else {
            if (b >= 0x40 && b <= 0x4F) { rexw = b & 8; i++; if (i >= size) break; b = code[i]; }
            if (b == 0x0F) {                                               // two/three-byte maps
                if (i + 1 >= size) break;
                uint8_t op = code[i + 1]; i += 2;
                if (op == 0x38 || op == 0x3A) {                            // 0F38 / 0F3A: ModRM, 0F3A has imm8
                    if (i >= size) break; i++;
                    ml = modrm_len(code + i, size - i, reg); if (ml < 0) break; i += ml;
                    if (op == 0x3A) i += 1;
                } else {
                    if (modrm2(op)) { ml = modrm_len(code + i, size - i, reg); if (ml < 0) break; i += ml; }
                    i += imm2(op, opsize);
                }
            } else {
                uint8_t op = b; i++;
                if (modrm1(op)) { ml = modrm_len(code + i, size - i, reg); if (ml < 0) break; i += ml; }
                i += imm1(op, opsize, rexw, reg);
            }
        }
        if (i <= s) i = s + 1;   // never stall
        r.instructions++;
    }
}

} // namespace

namespace {
// Untrusted input: headers and code sections come through the bounded reader; at most 96 sections and 1 GiB per section are scanned.
void avx_scan(const char *path, cosmo_avx_result &r) {
#ifdef COSMO_TEST_HOOKS
    if (getenv("COSMO_NATIVE_TEST_THROW")) throw std::bad_alloc();
#endif
    cosmo::File f(path);
    if (!f.ok()) { r.error = 1; return; }
    uint8_t mz[2];
    uint32_t pe, sig, machine, nsec, optsize;
    if (f.size() < 0x100 || !f.read(0, mz, 2) || mz[0] != 'M' || mz[1] != 'Z' || !f.u32(0x3C, pe) || !f.u32(pe, sig) || sig != 0x00004550) { r.error = 2; return; }
    if (!f.u16(uint64_t(pe) + 4, machine) || !f.u16(uint64_t(pe) + 6, nsec) || !f.u16(uint64_t(pe) + 20, optsize)) { r.error = 2; return; }
    if (machine != 0x8664) { r.error = 3; return; }
    const uint64_t sec = uint64_t(pe) + 24 + optsize;
    std::vector<uint8_t> code;
    for (uint32_t s = 0; s < std::min<uint32_t>(nsec, 96); s++) {
        uint8_t b[40];
        if (!f.read(sec + uint64_t(s) * 40, b, sizeof b)) break;
        auto le = [&](int o) { return uint32_t(b[o]) | uint32_t(b[o + 1]) << 8 | uint32_t(b[o + 2]) << 16 | uint32_t(b[o + 3]) << 24; };
        const uint32_t rawsize = le(16), rawptr = le(20), chars = le(36);
        const bool exec = (chars & 0x00000020) || (chars & 0x20000000);   // IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXECUTE
        if (!exec || rawptr >= f.size()) continue;
        const size_t n = size_t(std::min<uint64_t>({ uint64_t(rawsize), f.size() - rawptr, uint64_t(1) << 30 }));
        code.resize(n);
        if (n == 0 || !f.read(rawptr, code.data(), n)) continue;
        r.code_bytes += n; scan(code.data(), n, r);
    }
}
} // namespace

extern "C" cosmo_avx_result cosmo_avx_scan(const char *path) noexcept {
    cosmo_avx_result r{};
    if (!path) { r.error = 1; return r; }
    try { avx_scan(path, r); }
    catch (...) { r = cosmo_avx_result{}; r.error = 4; }   // nothing may escape into Swift
    return r;
}
