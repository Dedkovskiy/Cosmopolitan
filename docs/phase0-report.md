# Phase 0 report: how Cosmopolitan works today

Date: 2026-10-22. Code at commit `42aee00` plus this document. Everything below was read from the code or measured; nothing is assumed.
Hardware and OS claims are marked **verified** (with a source) or **unverified**. Line numbers refer to `42aee00`.

Machine used: MacBook Pro M2 Max, 32 GB, macOS 27.0.1, Xcode 27.1, Swift 6.4 (`swiftlang-6.4.0.34.1`), Apple clang 21.0.0.

---

## 1. Graphics backends: how they are abstracted and routed

**Abstraction.** A backend is a folder, not a type. Each lives in `~/Library/Application Support/Cosmopolitan/engines/renderer/<name>/wine/{i386,x86_64}-windows/*.dll`, with an optional `version` text file.
- `Sources/Core/Paths.swift:16` maps folder names to engine "slots": `dxmt→DXMT`, `dxvk→DXVK`, `dxvk3→DXVK`, `d9vk→D9VK`, `d3dmetal→D3DMETAL`, `cnc_ddraw→CNCD`.
- `Sources/Core/LaunchEnvironment.swift:32-36` turns a driver list into environment variables `WINEDLLPATH_<SLOT>=<folder>/wine`. Only the Sikarugir Wine build honours these per-slot variables: it then loads that folder's DLLs as builtins. Plain `WINEDLLPATH` was tried and reverted because it broke `steamwebhelper` (comment at `LaunchEnvironment.swift:30-31`).
- D3DMetal additionally gets `D3DMETAL_FRAMEWORK_PATH` (`LaunchEnvironment.swift:36`).

**Driver sets.**
- Bottle default: `autoDriverSet = dxmt, d9vk, cnc_ddraw` (`Paths.swift:19`); a bottle containing a Direct3D 12 program gets `autoDriverSetDX12 = d3dmetal, d9vk, cnc_ddraw` (`Paths.swift:22`) through the marker file `<bottle>/.needs-dx12`, written by `verifyAll()` (`LaunchCheck.swift:113-125`).
- `driverList()` (`Sources/Core/Drivers.swift:3`) returns the set from `cosmopolitan.env` `DRIVERS=` or the auto set, minus D3DMetal without an accepted licence, minus unusable drivers.
- `driverUsable()` (`Drivers.swift:13`) excludes any driver whose `version` file names DXVK 3 or newer (regex). This is the "never load DXVK 3" rule from the last session. It is a version blacklist, which Feature 1 replaces with a capability check.

**Routing per program.** `driverPlan()` (`Sources/Features/DriverPlan.swift:61`):
1. APIs used = PE imports (normal and delay-load, from C++) plus Direct3D DLL names found as ASCII or UTF-16 strings in the exe and in engine DLLs beside it larger than 1 MB (`graphicsAPIs`, `DriverPlan.swift:27`, cached in `options/.gfx-<exe>`).
2. 32/64-bit from the PE machine field.
3. Per API, the first preferred installed driver whose folder really contains that DLL for that architecture (`preference`, `DriverPlan.swift:15`): D3D12 → d3dmetal; D3D11 → dxmt, dxvk3, dxvk, d3dmetal; D3D10 → dxmt, dxvk3, dxvk; D3D9 → d9vk, dxvk3, dxvk; D3D8 → d9vk, dxvk3; DirectDraw → cnc_ddraw.
4. Drivers whose DLLs overlap are never combined. DirectDraw, D3D8 and D3D9 without a driver fall back to "Wine's own" (wined3d); D3D10–12 without one is a red light.
5. `serves()` (`DriverPlan.swift:90`) decides whether the bottle's set already covers the plan; if not, the launch gets a per-launch driver list.

Other inputs: Highball's per-title renderer only reorders preferences (`LaunchCheck.swift:51`); store clients get a fixed DXMT set (`Stores.swift:39`); per-program `DRIVERS=` in `options/<exe>.env` overrides everything (`LaunchCheck.swift:93-95`).

**Updates.** `DriverUpdates.swift` fetches DXMT (3Shain) and DXVK-macOS (Gcenx) GitHub releases weekly, keeps one `.old` copy, and also downloads the newest Sikarugir Template and Sikarugir Wine engines (`DriverUpdates.swift:38-48`). See section 11 (provenance).

## 2. Wine prefix layout

Root: `support = NSHomeDirectory() + "/Library/Application Support/Cosmopolitan"` (`Paths.swift:5`). Note that `NSHomeDirectory()` follows `CFFIXED_USER_HOME`, not `HOME` (measured, section 12).

| Path | What it holds |
|---|---|
| `bottles/<name>/` | the Wine prefix: `drive_c/`, `dosdevices/`, `system.reg`, `user.reg`, `userdef.reg` |
| `bottles/<name>/cosmopolitan.env` | per-bottle settings (`DRIVERS=`, `FULL_DISK=`, `AUTOSTART_STEAM=`, any `KEY=VALUE` env) |
| `bottles/<name>/cosmopolitan.apps` | "Find apps" result |
| `bottles/<name>/options/<exe>.env` | per-program overrides (`ARGS`, `DRIVERS`, env) — `Options.swift:4` |
| `bottles/<name>/options/.gfx-* .avx-* .exe-* .scanned-* .overrides-* .playtime-* .fps-*.csv .tuned-* .epic-installed.json` | caches and markers |
| `bottles/<name>/fixes/<appid>.{json,py,highball.json}` | ProtonDB / umu-protonfixes / Highball cache |
| `bottles/<name>/art/`, `mods/`, `windata/`, `desktopdata/` | cover art, mod overlays, Wine data |
| `bottles/<name>/.needs-dx12`, `.backup-exclusions-set`, `.metadata_never_index` | markers |
| `bottles/.auto-<name>-<date>/` | hidden APFS clone snapshots, pruned after 30 days (`Snapshots.swift:4-9`) |
| `engines/<WineBuild>/wswine.bundle/` | Wine engine; `bin/<AppName>` are 31 KB copies of the loader named after programs, for Dock labels (`Launch.swift:16-28`) |
| `engines/renderer/<name>/` | graphics backends (section 1) |
| `engines/gstreamer/` | GStreamer framework |
| `d3dmetal-license.json`, `terms-accepted.json` | acceptance records (date + SHA-256) |

New bottles: `createBottle()` (`Sources/Model/Bottles.swift:4-16`) runs `wineboot -u`, sets winebus `DisableHidraw=1`, `winecfg -v win10`, removes `z:`. First-run setup does the same with a plain environment (`Setup.swift:64-71`).

## 3. DLL overrides

Four mechanisms, all live today:
1. **Driver slots**: `WINEDLLPATH_<SLOT>` per launch (section 1). Environment, so per process tree.
2. **Bottle-global registry** `HKCU\Software\Wine\DllOverrides`: community fixes from umu-protonfixes are written here for the whole bottle (`Launch.swift:102-106`), after a snapshot.
3. **Per-exe registry** `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides`: Steam's `steam.exe` (xinput/dinput disabled) and `steamwebhelper.exe` (d3d11/dxgi/d3d10core builtin) — `Stores.swift:110-111`, `Repair.swift:19-21`.
4. **`WINEDLLOVERRIDES` environment**: from `options/<exe>.env` (`Options.swift:33`), and during `wineboot` (`Bottles.swift:8`, `Setup.swift:69`: `mscoree,mshtml=`).

## 4. Windows version per program

- New bottles report Windows 10 (`Bottles.swift:5`; the picker `Model.template`, `Model.swift:49`, defaults to `"auto"`).
- At launch, `launchNeeds()` (`LaunchCheck.swift:33-49`) classifies the exe:
  - DOS → DOSBox; Win16 → win98 + 1024x768 virtual desktop;
  - installers and .NET programs (imports `mscoree.dll`) → no era treatment (`LaunchCheck.swift:42-45`);
  - 32-bit only (`LaunchCheck.swift:46`): subsystem ≤ 4 from a Microsoft/Borland linker, or a `ddraw.dll` import → win98 + 1280x960 virtual desktop + Retina off;
  - subsystem 5 with linker 6–9 → winxp.
- `prepare()` writes the result into the prefix (`Launch.swift:107-119`): `AppDefaults\<exe>\Version`, `AppDefaults\<exe>\Explorer\Desktop`, `AppDefaults\<exe>\Mac Driver\RetinaMode`, `Explorer\Desktops\Cosmopolitan`.
- These keys are keyed by **file name only and never removed**. Section 10, N3 shows the consequence.

## 5. How Steam and games are launched

- `Model.launch(exe)` (`Launch.swift:74-92`): skip if already running → Epic via Legendary, or → `prepare()` (launch check + registry) → `start()`.
- `launchCmd()` (`SteamLaunch.swift:4-10`): a Steam library game becomes `steam.exe <cef flags> -applaunch <appid>`, so DRM and the overlay work; everything else runs its own exe.
- `start()` (`Start.swift:4-30`): side jobs (playtime, cloud saves, replay, keyboard layout, …); if a Steam game needs a different driver set or env, Steam is stopped and restarted with it (`stopSteam`, `Model.swift:71`), because a Steam game inherits the running Steam's environment. Missing runtimes go through Homebrew `winetricks -q` first, with Steam stopped while it runs.
- `wine()` (`Process.swift:28-31`) runs `exec()` with `launchEnv()`; the executable is a loader copy named after the program (`Launch.swift:16-28`).
- Steam itself autostarts with the app when a bottle has it (`Model.swift:87`).
- **Launches started inside Steam's own window are not intercepted at all.** They get Steam's environment (the bottle set) and whatever `AppDefaults` keys exist for that exe name.

## 6. Logging

- One string, `Model.log`, shown in the log pane and mirrored to `~/Library/Logs/Cosmopolitan.log` (`Shell.swift:3-6`). Child process output is streamed into it (`Process.swift:15-18`).
- `WINEDEBUG=-all` by default (`LaunchEnvironment.swift:6`), so Wine logs almost nothing unless a per-program option changes it.
- No per-launch log files, no structured records, no rotation.
- Crash triage: `triage()` (`CrashTriage.swift:15`) matches log signatures when a program exits non-zero within 60 s, then runs Troubleshoot; `CrashExplainer.swift:12` asks the on-device model for an explanation.
- **Defect**: the log file is created with `createFile`, which truncates it, by every process that logs, including CLI runs. Each CLI run wipes the GUI's log.

## 7. The stress suite

`tests/stress/`: `build.sh` (mingw-w64 for C, Wine Mono `mcs.exe` inside the bottle for C#), `run.sh` (launch check + launch through the app CLI + result lines), `common.h`, `d3d9.c`, `d3d11.c` (also builds D3D10), `d3d12.c`, `ddraw.c`, `dotnet.cs`.

| Covered | Not covered |
|---|---|
| D3D9, D3D10, D3D11 in 32 and 64-bit; D3D12 64-bit; DirectDraw 32 and 64-bit; .NET 4 WinForms + GDI+ + LINQ/Tasks | D3D8, Vulkan, OpenGL; DXVK's D3D10/11; D3DMetal's D3D11 |
| launch-check plan printed per test | Steam-launched path (`-applaunch`), store clients, installers |
| result file per test, exit code 1 unless all OK | a crashing exe, a hanging exe, an AVX2 exe, audio, video (GStreamer), controllers |
| | **isolation**: it builds into and runs in your real `Steam` bottle through your real app binary (violates your new rules) |
| | clean state between tests, random/reverse order, timing tolerance |
| | unit tests, C++ tests, sanitizers, fuzzing, CI (there is no `.github/`) |

The .NET test only passes in bottles where Wine Mono is registered; it fails in bottles Cosmopolitan creates (section 10, N2).

## 8. C++ module and the Swift boundary

Files in `Sources/Native/` (304 lines): `pe.cpp` (PE header + import table), `avxscan.cpp` (x86-64 length decoder counting VEX/EVEX), `sysinfo.cpp` (IOKit HID controllers, power source, process search), `cosmo_native.h`.

**Interop mode: plain C ABI.** The header declares `extern "C"` functions; `scripts/build.sh` imports it as a bridging header (`-import-objc-header`), and `Package.swift` imports it as module `CosmoNative`. Swift's C++ interoperability mode is not enabled anywhere. No Objective-C++.

| Boundary function | Memory ownership | Called from (thread) | Can throw? |
|---|---|---|---|
| `cosmo_pe_read(path, imports, cap)` → `cosmo_pe_info` | value struct returned; Swift owns the 16 KB `imports` buffer (`Native.swift`) | main actor: `launchNeeds`, `exeEra`, `driverPlan` (`verifyAll`, launches); CLI main thread | yes: `std::vector`/`std::string` allocation (`bad_alloc`), whole file read into memory with no size cap |
| `cosmo_avx_scan(path)` → `cosmo_avx_result` | value struct | detached background task (`AVX.swift:18-20`), cooperative pool | yes: whole-file `std::vector` |
| `cosmo_controllers(out, cap)` | Swift owns the 2 KB buffer | main actor (status timer every 5 s, input check) | yes: `std::string`/`std::vector` |
| `cosmo_on_battery()` | none | main actor and any thread building `launchEnv()` | no allocations of note |
| `cosmo_proc_find(needle, pids, cap)` | Swift owns the 256-entry pid array | main actor (status, `isRunning`), CLI | yes: `std::vector` sized `KERN_ARGMAX` |

- No function is `noexcept` and none catches. **verified**: Swift cannot catch C++ exceptions, and in interop mode "the running program terminates with a fatal error when a C++ exception that's not caught by C++ code reaches Swift code" ([swift.org C++ interop status](https://www.swift.org/documentation/cxx-interop/status/)). Through a plain C ABI, standard C++ ends an uncaught exception in `std::terminate`. Either way an allocation failure is an app crash.
- All five functions are reentrant: no globals or statics hold state, so they are safe to call concurrently. That safety is undocumented.
- **Defect, with evidence**: `pe.cpp:30` reads `d[opt + 2]` after checking only `h + 4 < size`. A truncated executable (69 bytes, `MZ` + `PE\0\0`) gives an AddressSanitizer `heap-buffer-overflow` READ at `pe.cpp:30`. The parser runs inside the app process on every exe in a bottle.
- Smaller issues seen while reading, not yet proven by tests: `strnlen` in `pe.cpp` `add()` can read up to 256 bytes past the buffer end; `tolower` on a negative `char` is undefined; `cosmo_proc_find` runs `strlen` on a kernel buffer without a bound.

## 9. C++ build setup

| | `scripts/build.sh` (shipped app) | `Package.swift` (`swift build`) |
|---|---|---|
| Standard | `-std=c++17` | not set → clang 21's default, **C++14** (`__cplusplus 201402L`, measured) |
| Exceptions / RTTI | on (clang defaults; no `-fno-exceptions`/`-fno-rtti`) | on |
| Warnings | none (`-O2` only) | SwiftPM defaults |
| Tests | none | none (no test targets) |
| Sanitizers | Apple clang ships ASan, UBSan and TSan runtimes; `swiftc -sanitize=address`, `thread` and `undefined` all link (measured) | same |
| Fuzzing | Apple clang 21 has **no** libFuzzer runtime (`libclang_rt.fuzzer_osx.a` not found, measured); Homebrew LLVM 23.1.4 has it | same |

## 10. Issues A–D now, and new defects found in Phase 0

**A. D3DMetal downgrade.** Installed: D3DMetal **3.0** (`D3DMetal.framework` Info.plist `CFBundleShortVersionString` = 3.0), licence accepted 2026-10-22 18:45 UTC. The previous **4.0b3** is at `~/Cosmopolitan-testrun-2032/d3dmetal-old`. 3.0 has 26 `D3DM_*` setting names; 4.0b3 additionally has `D3DM_MAX_FPS` and `D3DM_MTL4` (string scan of both frameworks). Nothing in the install path compares versions (`D3DMetal.swift:16`).

**B. Battery cap.** `LaunchEnvironment.swift:26-28` sets `D3DM_MAX_FPS=60` and DXMT's `preferredMaxFrameRate=60` on battery and logs "60 fps cap … active". With D3DMetal 3.0 the variable does not exist, so Direct3D 12 is uncapped: the D3D12 test ran at 128–441 fps on battery while D3D10/11 on DXMT held at 60.

**C. 64-bit DirectDraw after cnc-ddraw.** Root cause **not found yet**, but narrowed. In your Steam bottle it failed 3 of 3 times: every blit failed with `DDERR_INVALIDRECT`, the primary surface was 800x600 while Windows reported 1800x1169, and no registry value changed. In throwaway prefixes it passed every time (test build, section 12):

| Throwaway experiment | Result |
|---|---|
| fresh prefix, cnc-ddraw 32-bit then DirectDraw 64-bit, one persistent msync wineserver | pass |
| same, wineserver restarted in between | pass |
| same, with a long-lived default desktop process (like Steam's) | pass |
| same, with your Steam bottle's `user.reg`, `system.reg`, `userdef.reg` copied in | pass |

So it is not caused by prefix files or saved registry. It needs your live Steam session: a wineserver alive since 20:32 that had built up about ten display-adapter entries, and/or Steam's processes. Two clues: 800x600 is Wine's default virtual-desktop size, and cnc-ddraw calls `ChangeDisplaySettings`, which fails with `-2` there. Confirming it needs either a Steam restart or a read-only `reg query` inside your Steam bottle. Both touch your setup, so they wait for your go-ahead.

**D. Sikarugir's D3DMetal 4.0b3.** It is at `~/Cosmopolitan-testrun-2032/d3dmetal-old`, unused. I will not reuse it. Deleting it is your call.

**New defects (evidence in brackets):**

| # | Severity | Defect | Where |
|---|---|---|---|
| N1 | high | `createBottle` runs `wineboot` with the driver slots active, so new prefixes get DXMT's `d3d11/dxgi/d3d10core/winemetal` baked into `system32` and `syswow64`, and cnc-ddraw baked in as `syswow64\ddraw.dll`. [SHA-256 of a fresh prefix's files equals the backend files; your Steam bottle has Wine's own] | `Bottles.swift:8` via `wine()` → `launchEnv()` |
| N2 | high | Bottles Cosmopolitan creates cannot run .NET: `wineboot` runs with `mscoree` disabled, so Wine Mono is never registered. The launch check still says "Wine Mono present" because it only checks the engine folder. [the .NET test fails with `err:mscoree … Wine Mono is not installed`, exit 255, while the light is green] | `Bottles.swift:8`, `Setup.swift:69`, `LaunchCheck.swift:59-64` |
| N3 | high | Per-exe registry keys (Windows version, virtual desktop, Retina, mouse warp) are keyed by file name and never removed. They outlive fixes and hit unrelated programs with the same name (every RPG Maker game is `Game.exe`). [`AppDefaults\stress-dotnet.exe\Version = "win98"` is still in your Steam bottle after the .NET fix, so that exe still runs as Windows 98] | `Launch.swift:107-119` |
| N4 | medium | Community DLL overrides go into the bottle-global key, so one game's fix applies to every program in the bottle. | `Launch.swift:105` |
| N5 | critical | Repair runs `pkill -9 -f '\.exe'` and `pkill -9 -f wineserver`: it SIGKILLs every process on the Mac whose command line contains ".exe" and every Wine server, in every bottle and outside Cosmopolitan. Troubleshoot counts Wine servers system-wide and recommends Repair when it sees more than one. [Troubleshoot output "✗ One wineserver (3 running) → … Repair kills all Wine processes" during a throwaway run, with your Steam running in another prefix] | `Repair.swift:13`, `Troubleshoot.swift:38-39` |
| N6 | medium | Every process truncates `~/Library/Logs/Cosmopolitan.log`, including CLI runs; two processes write it concurrently. | `Shell.swift:5` |
| N7 | high | Truncated executables cause an out-of-bounds read in the app process. [ASan, section 8] | `pe.cpp:30` |
| N8 | medium | The on-device crash explainer gives wrong advice. ["Try installing Mono from the Mac App Store" for a Wine Mono error] | `CrashExplainer.swift:12` |
| N9 | low | `swift build` compiles the C++ as C++14, the shipped build as C++17. | `Package.swift` |
| N10 | high | The stress suite runs in your real bottle through your real app binary, writes registry keys and caches there, and truncates your log. | `tests/stress/run.sh`, `build.sh` |
| N11 | high | Provenance: section 11. | |
| N12 | medium | A Wine process started without `WINEMSYNC=1` against a msync wineserver dies at once (SIGFPE, exit 136 in your Steam bottle; exit 1 for a launch in a throwaway prefix whose server I had started without msync). Every Cosmopolitan helper uses `launchEnv()`, which sets it; the first-run setup doesn't, but only ever runs on a new prefix. | engine behaviour; `Setup.swift:69` |

## 11. Component provenance (against your new rule)

Your rule: no redistributable components from third-party templates or wrappers. Today almost the whole stack comes from Sikarugir:

| Component | Where it comes from now |
|---|---|
| Wine engine `WS12WineSikarugir10.0_8` | Sikarugir-App/Engines GitHub release; first-run setup downloads it (`Setup.swift:36`) |
| ~28 engine dylibs (MoltenVK `libMVK`, Vulkan loader, SDL2/SDL3, freetype, gnutls, …) | copied from the Sikarugir Template's Frameworks (`EnginePrep.swift:10-13`) |
| `dxmt`, `dxvk`, `dxvk3`, `d9vk`, `cnc_ddraw` | Sikarugir Template `SharedSupport/renderer`; the first-run setup copies them (`Setup.swift:56-58`); the weekly updater replaces dxmt and dxvk from 3Shain and Gcenx releases |
| GStreamer framework | Sikarugir Template |
| Weekly job | downloads the newest Sikarugir Template (which contains a copy of Apple's D3DMetal) into `~/Library/Application Support/Sikarugir/Template` and newer Sikarugir engines (`DriverUpdates.swift:38-48`). It doesn't install that D3DMetal, but the download itself conflicts with "never download D3DMetal". A button tooltip still says "D3DMetal from the newest Sikarugir template" (`ContentView.swift:69`) |
| D3DMetal 3.0 (installed) | your own GPTK 3.0 DMG |

Replacing any of these is your decision under your rules. Official upstream sources are in the design doc.

## 12. Changes to your system

**Phase 0 (this message):**
1. `bottles/C1` was created in your real bottles folder at 21:56:34 by my first test-build run. `HOME` doesn't redirect `NSHomeDirectory()`; `CFFIXED_USER_HOME` does (verified with a 2-line test program). I stopped C1's own wineserver and deleted the folder about two minutes later. It held only a freshly booted empty prefix. Your Steam bottle and Steam were untouched. Net change: none.
2. The same run truncated `~/Library/Logs/Cosmopolitan.log` (defect N6). The GUI session's log lines from 21:33 to 21:56 are gone; this can't be undone.
3. A test build `CosmopolitanTest.app` (bundle ID `local.cosmopolitan.test`, so it has its own settings) and a throwaway home exist under `/private/tmp/claude-501/…/scratchpad/cosmotest/`. Engine and backends are APFS clones there, using almost no extra space. Every later run passed a tripwire: your bottle list and log timestamp stayed unchanged.
4. New repo file `docs/phase0-report.md`.

**Left over from last session's stress runs**, before your rules existed. Nothing removed yet; undo steps for each:
| What | Where | Undo |
|---|---|---|
| test programs, results, DXVK caches | Steam bottle `drive_c/StressTest/` | delete the folder |
| 20 cache markers | Steam bottle `options/.gfx-stress-*`, `.scanned-stress-*` | delete those files |
| registry keys | Steam bottle `HKCU\Software\Wine\AppDefaults\stress-ddraw-32.exe` and `…\stress-dotnet.exe` (Version win98, virtual desktop, Retina off) | `reg delete` both keys (needs a `reg` run inside the bottle) |
| loader copy named "StressTest" (31 KB) | `engines/WS12WineSikarugir10.0_8/wswine.bundle/bin/StressTest` | delete the file |
| log truncations | `~/Library/Logs/Cosmopolitan.log` | none possible |
| app restart at 21:33 (to load the crash fix) | Cosmopolitan pid 27140; Steam kept running | none needed |
| clean-test install and old D3DMetal | `~/Cosmopolitan-testrun-2032/` | delete when you no longer need it |

## 13. Decisions that need you

1. **Provenance** (section 11): keep the Sikarugir stack until upstream replacements are tested, or start replacing now? Swapping the engine could bring back the black Steam window seen on Wine 11.x.
2. **Issue C**: may I restart Steam's session, or run a read-only `reg query` inside your Steam bottle, to confirm the root cause?
3. **Cleanup**: may I remove the leftovers in section 12?
4. **D3DMetal 4.x**: only you can download it from Apple and accept the licence. The design doc says where.
