#!/bin/zsh
# Issue B: on battery, Direct3D 12 games get D3DMetal's documented frame cap only when the installed D3DMetal has it (4.0 beta); with 3.0 the
# launch check says the cap isn't available and no ignored variable is set. Fake toolkits only; battery simulated in the test build.
source "${0:A:h}/../lib/testenv.sh"; testenv_init >/dev/null || exit 1; trap testenv_cleanup EXIT
tw_snapshot
fail() { print "FAIL: $*"; exit 1; }
R="$TS/engines/renderer"; rm -rf "$R/d3dmetal" "$TS/d3dmetal-license.json"
mkkit() { local d="$1" v="$2"; shift 2; local fw="$d/redist/lib/external/D3DMetal.framework"
  mkdir -p "$fw/Versions/A/Resources" "$d/redist/lib/wine/x86_64-windows"; /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $v" "$fw/Versions/A/Resources/Info.plist" >/dev/null
  print -r -- "fake $*" > "$fw/D3DMetal"; for f in d3d12 d3d11 dxgi; do print fake > "$d/redist/lib/wine/x86_64-windows/$f.dll"; done
  print -r -- '{\rtf1 Fake license}' > "$d/License.rtf"; print -r -- "{\\rtf1 Evaluation environment for Windows games $v README}" > "$d/Read Me.rtf"; }
mkkit "$T/kit3" 3.0 D3DM_SUPPORT_DXR D3DM_ENABLE_METALFX
mkkit "$T/kit4" 4.0b3 D3DM_SUPPORT_DXR D3DM_ENABLE_METALFX D3DM_MTL4 D3DM_MAX_FPS
ct --newbottle B >/dev/null 2>&1; stress_build B || fail "could not build the stress test programs into the throwaway bottle"
EXE="$(tprefix B)/drive_c/StressTest/stress-d3d12-64.exe"
note() { COSMO_TEST_ON_BATTERY=1 ct --check B "$EXE" 2>&1 | grep -o 'battery[^;]*' | head -1; }
envcap() { COSMO_TEST_ON_BATTERY=1 ct --print-env B 2>&1 | grep -E '^(D3DM_MAX_FPS|DXMT_CONFIG)=' | tr '\n' ' '; }

ct --install-d3dmetal "$T/kit3" >/dev/null 2>&1; ct --accept-d3dmetal >/dev/null 2>&1
n=$(note); e=$(envcap)
[[ "$n" == "battery 60 fps cap: not available for this game (D3DMetal 3.0 has no frame limiter)" ]] || fail "3.0: note was '$n'"
[[ "$e" != *D3DM_MAX_FPS* && "$e" == *DXMT_CONFIG=* ]] || fail "3.0: environment '$e'"
print -r -- "ok: D3DMetal 3.0 on battery → '$n'; env: $e"
ct --install-d3dmetal "$T/kit4" >/dev/null 2>&1; ct --accept-d3dmetal >/dev/null 2>&1
n=$(note); e=$(envcap)
[[ "$n" == "battery: D3DMetal caps this game at 60 fps" && "$e" == *"D3DM_MAX_FPS=60"* ]] || fail "4.0b3: note '$n', env '$e'"
print -r -- "ok: D3DMetal 4.0 beta 3 on battery → '$n'; env: $e"
tw_check || fail "your real data changed"
print "PASS battery_cap"
