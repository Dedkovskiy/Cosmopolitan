// PE (Windows executable) facts read natively: kind (dos / win16 / pe), machine, subsystem and linker versions, and the import
// table *including delay-load imports* (which the Swift walker never read — games that delay-load d3d12.dll or xinput are now seen).
#include "cosmo_native.h"
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

namespace {
struct Img { std::vector<uint8_t> d; uint32_t u16(size_t o) const { return o + 2 <= d.size() ? d[o] | (d[o+1] << 8) : 0; } uint32_t u32(size_t o) const { return o + 4 <= d.size() ? u16(o) | (u16(o+2) << 16) : 0; } };
bool load(const char *path, Img &img) {
    FILE *f = fopen(path, "rb"); if (!f) return false;
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    if (len < 0x40) { fclose(f); return false; }
    img.d.resize((size_t)len); bool ok = fread(img.d.data(), 1, (size_t)len, f) == (size_t)len; fclose(f); return ok;
}
}

extern "C" cosmo_pe_info cosmo_pe_read(const char *path, char *imports, size_t cap) {
    cosmo_pe_info r{}; if (cap) imports[0] = 0;
    Img img; if (!load(path, img)) { r.kind = 0; return r; }
    const auto &d = img.d;
    if (d[0] != 'M' || d[1] != 'Z') { r.kind = 0; return r; }
    size_t h = img.u32(0x3C);
    if (h + 4 >= d.size()) { r.kind = 1; return r; }                       // plain DOS
    if (d[h] == 'N' && d[h+1] == 'E') { r.kind = 2; return r; }              // Win16
    if (!(d[h] == 'P' && d[h+1] == 'E')) { r.kind = 1; return r; }
    r.kind = 3; r.machine = (uint16_t)img.u16(h + 4);
    size_t opt = h + 24; bool plus = img.u16(opt) == 0x20b; uint16_t nsec = (uint16_t)img.u16(h + 6);
    r.linker_major = d[opt + 2]; r.subsystem_major = (uint16_t)img.u16(opt + 48);
    size_t secs = opt + img.u16(h + 20);
    auto off = [&](uint32_t rva) -> long { for (uint16_t i = 0; i < nsec; i++) { size_t s = secs + i * 40; uint32_t va = img.u32(s + 12), vs = img.u32(s + 8), rs = img.u32(s + 16); uint32_t sz = vs > rs ? vs : rs; if (rva >= va && rva < va + sz) return (long)(rva - va + img.u32(s + 20)); } return -1; };
    std::string list;
    auto add = [&](long nameoff) { if (nameoff < 0 || (size_t)nameoff >= d.size()) return; std::string n((const char *)&d[nameoff], strnlen((const char *)&d[nameoff], 256)); for (auto &c : n) c = (char)tolower(c); if (n.empty() || list.find(n + ",") != std::string::npos || list.rfind(n) == list.size() - n.size()) return; if (!list.empty()) list += ","; list += n; };
    size_t dd = opt + (plus ? 112 : 96);
    // Import directory (index 1): 20-byte descriptors, name RVA at +12.
    long imp = off(img.u32(dd + 8));
    if (imp >= 0) for (size_t i = (size_t)imp; img.u32(i + 12) != 0 && i + 20 <= d.size(); i += 20) add(off(img.u32(i + 12)));
    // Delay-load directory (index 13): 32-byte descriptors, name RVA at +4.
    long del = off(img.u32(dd + 13 * 8));
    if (del >= 0) for (size_t i = (size_t)del; img.u32(i + 4) != 0 && i + 32 <= d.size(); i += 32) { add(off(img.u32(i + 4))); r.delay_imports++; }
    if (cap) { strncpy(imports, list.c_str(), cap - 1); imports[cap - 1] = 0; }
    return r;
}
