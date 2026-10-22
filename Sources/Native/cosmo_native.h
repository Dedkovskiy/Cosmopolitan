// C interface of Cosmopolitan's native (C++) module. Imported into Swift as the bridging header.
#pragma once
#include <stdint.h>
#include <stddef.h>
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

typedef struct {
    int32_t  kind;             // 0 not an executable, 1 DOS, 2 Win16 (NE), 3 PE
    uint16_t machine;          // 0x8664 x86-64, 0x14c i386, 0xaa64 arm64
    uint16_t subsystem_major;  // 4 = Win95/NT4 era, 5 = 2000/XP, 6+ = Vista and later
    uint8_t  linker_major;     // 6 = VC6, 7–9 = VC2002–2008, 10+ = 2010+, 2 = GNU ld
    uint32_t delay_imports;    // number of delay-load import entries (also included in the imports list)
} cosmo_pe_info;
// Reads header facts and writes the comma-separated, lower-cased import DLL list (normal + delay-load) into `imports`.
cosmo_pe_info cosmo_pe_read(const char *path, char *imports, size_t cap);

// Connected game controllers via IOKit HID (gamepads, joysticks, multi-axis). Writes comma-separated product names; returns count.
int cosmo_controllers(char *out, size_t cap);
// 1 on battery, 0 on mains, -1 unknown (IOKit power sources).
int cosmo_on_battery(void);
// PIDs whose executable path or argv[0] contains `needle` (excluding the caller); later arguments are ignored on purpose. Returns the number written.
int cosmo_proc_find(const char *needle, int32_t *pids, int cap);

#ifdef __cplusplus
}
#endif
