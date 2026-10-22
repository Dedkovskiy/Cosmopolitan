// C interface of Cosmopolitan's native (C++) module. Imported into Swift as the bridging header.
#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t instructions;   // instructions walked in executable sections
    uint64_t vex;            // VEX-encoded (AVX / AVX2 / FMA / BMI)
    uint64_t evex;           // EVEX-encoded (AVX-512) — Rosetta cannot execute these
    uint64_t code_bytes;     // bytes of executable sections scanned
    int32_t  error;          // 0 ok, 1 cannot open, 2 not a PE, 3 not x86-64
} cosmo_avx_result;

// Scans a Windows PE32+ executable or DLL. Takes ~0.1 s for 25 MB; never executes anything.
cosmo_avx_result cosmo_avx_scan(const char *path);

#ifdef __cplusplus
}
#endif
