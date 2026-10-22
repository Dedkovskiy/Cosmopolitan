// The compatibility decision table (docs/design/compat-gate.md §3.6), first matching row wins:
//  1 kernel anti-cheat → block · 2 Rosetta can't run x86 → block · 3 needs AVX2, the AVX2 probe failed → block · 4 AVX-512 paths → warning
//  5 no backend can serve the game's main API → incompatible, ranked alternatives · 6 per-game pin can serve → use it
//  7 per-game pin can't serve → ask, with the best other choice · 8 DB known-good backend can serve → use it
//  9 DB known-good backend's installed version crashed this game here → ask: roll back side by side · 10 capability heuristic → use
//  11 global default, when it is among the capable backends → use it. Precedence: blockers > per-game pin > DB > heuristic > global default.
// Pure: plain values in, plain values out; no I/O, no globals; nothing throws across the boundary.
#include "cosmo_native.h"
#include <cstdlib>
#include <initializer_list>
#include <new>

namespace {
uint32_t mainApi(uint32_t apis) { for (uint32_t b = COSMO_API_D3D12; b; b >>= 1) if (apis & b) return b; return 0; }
// Preference per API when nothing else decides (DXVK's D3D9 is the 2.3 build; DXVK 3 never qualifies because serves[] reflects capabilities).
int prefs(uint32_t api, int out[4]) {
    static const int d12[] = { COSMO_BE_D3DMETAL, COSMO_BE_VKD3D_PROTON }, d11[] = { COSMO_BE_DXMT, COSMO_BE_DXVK, COSMO_BE_D3DMETAL, COSMO_BE_WINED3D },
                     d10[] = { COSMO_BE_DXMT, COSMO_BE_DXVK, COSMO_BE_WINED3D }, d9[] = { COSMO_BE_DXVK, COSMO_BE_WINED3D }, dd[] = { COSMO_BE_CNC_DDRAW, COSMO_BE_WINED3D };
    const int *p = d9; int n = 2;
    switch (api) { case COSMO_API_D3D12: p = d12; n = 2; break; case COSMO_API_D3D11: p = d11; n = 4; break; case COSMO_API_D3D10: p = d10; n = 3; break;
                   case COSMO_API_DDRAW: p = dd; n = 2; break; default: break; }
    for (int i = 0; i < n; i++) out[i] = p[i];
    return n;
}
bool valid(int b) { return b > COSMO_BE_NONE && b < COSMO_BE_COUNT; }

cosmo_decision decide(const cosmo_decision_input &in) {
#ifdef COSMO_TEST_HOOKS
    if (getenv("COSMO_NATIVE_TEST_THROW")) throw std::bad_alloc();
#endif
    cosmo_decision d{};
    if ((in.ram_gb && in.ram_gb <= 8) || (in.game_min_ram_gb && in.game_min_ram_gb > in.ram_gb)) d.warnings |= COSMO_WARN_RAM;
    if (in.rt_on_in_game && in.gpu_family < 9) d.warnings |= COSMO_WARN_RT_NO_HARDWARE;
    if (in.avx512_paths) d.warnings |= COSMO_WARN_AVX512;                                                    // row 4: a warning, not a verdict
    auto set = [&](int verdict, int row, int backend) { d.verdict = verdict; d.row = row; d.backend = backend; return d; };
    auto option = [&](int b, bool avail) { if (d.noptions < 4) { d.options[d.noptions] = b; d.option_available[d.noptions] = avail; d.noptions++; } };
    if (in.kernel_anticheat) return set(COSMO_BLOCK, 1, COSMO_BE_NONE);
    if (!in.rosetta_ok) return set(COSMO_BLOCK, 2, COSMO_BE_NONE);
    if (in.needs_avx2 && !in.rosetta_avx2_ok) return set(COSMO_BLOCK, 3, COSMO_BE_NONE);
    const uint32_t api = mainApi(in.apis);
    if (!api) return set(COSMO_USE, 10, COSMO_BE_NONE);                                                      // not a graphics program
    auto can = [&](int b) { return valid(b) && (in.serves[b] & api) && !in.failed_here[b]; };
    int order[4]; const int n = prefs(api, order);
    int heuristic = COSMO_BE_NONE;
    for (int i = 0; i < n && heuristic == COSMO_BE_NONE; i++) if (can(order[i])) heuristic = order[i];
    bool anyServes = false;
    for (int b = 1; b < COSMO_BE_COUNT; b++) if (in.serves[b] & api) anyServes = true;
    if (!anyServes) {                                                                                        // row 5: hard incompatibility
        if (valid(in.db_known_good) && (in.implements[in.db_known_good] & api)) option(in.db_known_good, false);
        for (int rank : { COSMO_DB_KNOWN_GOOD, COSMO_DB_UNKNOWN, COSMO_DB_EXPERIMENTAL, COSMO_DB_BROKEN })
            for (int b = 1; b < COSMO_BE_COUNT; b++)
                if ((in.implements[b] & api) && in.db_status[b] == rank && b != in.db_known_good && d.noptions < 3) option(b, false);
        option(COSMO_BE_NONE, true);
        return set(COSMO_INCOMPATIBLE, 5, d.noptions > 1 ? d.options[0] : COSMO_BE_NONE);
    }
    if (valid(in.game_pin)) {
        if (can(in.game_pin)) return set(COSMO_USE, 6, in.game_pin);
        const int proposal = can(in.db_known_good) ? in.db_known_good : heuristic;                           // row 7: never override silently
        option(proposal, proposal != COSMO_BE_NONE); option(in.game_pin, false); option(COSMO_BE_NONE, true);
        return set(COSMO_ASK, 7, proposal);
    }
    if (can(in.db_known_good)) return set(COSMO_USE, 8, in.db_known_good);
    if (valid(in.db_known_good) && (in.serves[in.db_known_good] & api) && in.failed_here[in.db_known_good]) {   // row 9
        option(in.db_known_good, true); if (heuristic != COSMO_BE_NONE) option(heuristic, true); option(COSMO_BE_NONE, true);
        return set(COSMO_ASK, 9, in.db_known_good);
    }
    if (valid(in.global_pin) && can(in.global_pin)) return set(COSMO_USE, 11, in.global_pin);                 // global default among the capable
    if (heuristic != COSMO_BE_NONE) return set(COSMO_USE, 10, heuristic);
    for (int b = 1; b < COSMO_BE_COUNT; b++) if (in.serves[b] & api) option(b, true);                       // every capable one failed here
    option(COSMO_BE_NONE, true);
    return set(COSMO_ASK, 9, d.options[0]);
}
} // namespace

extern "C" cosmo_decision cosmo_decide(const cosmo_decision_input *in) noexcept {
    if (!in) { cosmo_decision d{}; d.error = 1; return d; }
    try { return decide(*in); }
    catch (...) { cosmo_decision d{}; d.error = 2; return d; }   // nothing may escape into Swift
}
