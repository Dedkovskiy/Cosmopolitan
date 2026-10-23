#!/bin/zsh
# Screenshots of the main window (Library, empty and with games), every onboarding screen, What's new, Advanced and Settings, taken from the
# GUI test build in throwaway homes (HOME and CFFIXED_USER_HOME both set). Your real install is only compared before and after.
# Usage: tests/ui/screens.sh OUTDIR
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
OUT="${1:?usage: screens.sh OUTDIR}"; mkdir -p "$OUT"
tw_snapshot
gui() {   # gui NAME SHEET [ENV=VALUE…]: opens the test build on that screen, waits for its window to settle, captures every window, quits
  local name=$1 sheet=$2; shift 2
  sandbox-exec -p "$(tw_sandbox_profile)" env CFFIXED_USER_HOME="$TH" HOME="$TH" COSMO_TEST_HOME="$TH" COSMO_TEST_SHEET="$sheet" "$@" \
    "$T/CosmopolitanTest.app/Contents/MacOS/Cosmopolitan" >/dev/null 2>&1 & local app=$!
  win() { "$T/winshot" $app "$T/probe" >/dev/null 2>&1; }; poll 30 win || { kill $app; fail "$name: no window"; }
  sleep ${GUI_WAIT:-3}   # let sheets finish animating and the first scan and checks draw (nothing to poll for in a picture)
  "$T/winshot" $app "$OUT/$name" | sed 's/^/  shot: /'; kill $app; wait $app 2>/dev/null
}
# 1. A fresh Mac: no engine, nothing accepted. Onboarding screens 0–6 (screens that appear only when needed are opened directly here).
TESTENV_NO_ENGINE=1 testenv_init >/dev/null || exit 1
swiftc -O "$TESTENV_REPO/tests/lib/winshot.swift" -o "$T/winshot" || fail "winshot"
for n in 0 1 2 3 4 5 6; do gui onboarding-$n onboarding-$n COSMO_TEST_NO_ROSETTA=1; done
K="$T/kit/Game Porting Toolkit"; mkdir -p "$K/redist/lib/external/D3DMetal.framework"
gui onboarding-3-found onboarding-3 COSMO_TEST_GPTK_VOLUME="$K"
testenv_cleanup
# 2. An installed Mac: the Library empty, then with games; What's new; Advanced; Settings.
testenv_init >/dev/null || exit 1
swiftc -O "$TESTENV_REPO/tests/lib/winshot.swift" -o "$T/winshot" || fail "winshot"
gui library-empty library
ct --newbottle Games >/dev/null 2>&1 && stress_build Games || fail "could not build the stand-in games"
# Stand-in games with made-up names, one folder each like real installs; one damaged on purpose; Apple's licence not accepted, so the
# Direct3D 12 one needs a fix.
PF="$(tprefix Games)/drive_c/Program Files"; ST="$(tprefix Games)/drive_c/StressTest"
for g in "Star Courier:d3d11-64" "Pixel Kingdom:ddraw-32" "Neon Drift:d3d12-64" "Old Fort:d3d9-32" "Ledger:dotnet"; do
  mkdir -p "$PF/${g%%:*}"; cp "$ST/stress-${g#*:}.exe" "$PF/${g%%:*}/${g%%:*}.exe"; done
mkdir -p "$PF/Broken Game"; head -c 2000 "$ST/stress-d3d11-64.exe" > "$PF/Broken Game/Broken Game.exe"
rm -f "$TS/d3dmetal-license.json"
GUI_WAIT=10 gui library library
gui whatsnew whatsnew
gui advanced advanced
gui settings settings
testenv_cleanup
tw_check || fail "your real data changed"
print "screens in $OUT"
