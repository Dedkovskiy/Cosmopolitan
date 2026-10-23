#!/bin/zsh
# Shared test environment. Source it, then call testenv_init. Gives:
#   ct ARGS…        the test build (bundle id local.cosmopolitan.test → its own settings) with a throwaway home (HOME, CFFIXED_USER_HOME
#                   and COSMO_TEST_HOME all point at it, so the app's support folder, bottles and log live there)
#   tw_snapshot / tw_check   tripwire over YOUR real data: bottles folder, Cosmopolitan log, Steam bottle, running Steam and app
#   testenv_cleanup  stops the throwaway prefixes' wineservers and removes the throwaway folder
# Nothing here writes outside the throwaway folder. The engine and backends are APFS clones (no extra disk space).

zmodload zsh/datetime   # EPOCHREALTIME, for timing every wait
TESTENV_REPO="${${(%):-%x}:A:h:h:h}"
REAL_HOME="$(dscl . -read /Users/$(id -un) NFSHomeDirectory | awk '{print $2}')"
REAL_SUPPORT="$REAL_HOME/Library/Application Support/Cosmopolitan"
REAL_LOG="$REAL_HOME/Library/Logs/Cosmopolitan.log"
ENGINE="${COSMO_ENGINE:-WS12WineSikarugir10.0_8}"

testenv_init() {
  emulate -L zsh
  T="$(mktemp -d /private/tmp/cosmotest.XXXXXX)" || return 1
  TH="$T/home"; TS="$TH/Library/Application Support/Cosmopolitan"
  mkdir -p "$TS/engines" "$TH/Library/Logs"
  cp -cR "$TESTENV_REPO/Cosmopolitan.app" "$T/CosmopolitanTest.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.cosmopolitan.test" -c "Set :CFBundleName CosmopolitanTest" "$T/CosmopolitanTest.app/Contents/Info.plist"
  codesign --force --deep --sign - "$T/CosmopolitanTest.app" 2>/dev/null
  if [[ -z "$TESTENV_NO_ENGINE" ]]; then   # a --setup test wants an empty support folder
    cp -cR "$REAL_SUPPORT/engines/$ENGINE" "$REAL_SUPPORT/engines/renderer" "$TS/engines/" 2>/dev/null
    [[ -d "$REAL_SUPPORT/engines/gstreamer" ]] && cp -cR "$REAL_SUPPORT/engines/gstreamer" "$TS/engines/"
    local bin="$TS/engines/$ENGINE/wswine.bundle/bin" f
    for f in "$bin"/*(N.); do [[ "$f:t" != wine ]] && cmp -s "$f" "$bin/wine" && rm -f "$f"; done   # loader copies named after your programs (exact copies of bin/wine)
    cp "$REAL_SUPPORT/terms-accepted.json" "$TS/" 2>/dev/null
    [[ -f "$REAL_SUPPORT/d3dmetal-license.json" ]] && cp "$REAL_SUPPORT/d3dmetal-license.json" "$TS/"
  fi
  mkdir -p "$TS/cache"; for f in "$TESTENV_REPO"/.cache/*(N.) "$REAL_SUPPORT"/cache/*(N.); do cp -c "$f" "$TS/cache/" 2>/dev/null; done   # pinned downloads (hash-checked on use)
  print "test env: $T"
}

# Every test-build run is sandboxed: writes to your real Cosmopolitan folders, log and Sikarugir folder are impossible for it and for every
# Wine process it starts, so a change there during a test can only come from your own running Steam or app.
ct() { sandbox-exec -p "$(tw_sandbox_profile)" env CFFIXED_USER_HOME="$TH" HOME="$TH" COSMO_TEST_HOME="$TH" "$T/CosmopolitanTest.app/Contents/MacOS/Cosmopolitan" "$@"; }
tprefix() { print -r -- "$TS/bottles/$1"; }
# poll MAX_SECONDS CMD…: runs CMD every 0.5 s until it succeeds or MAX_SECONDS pass; POLL_TOOK = seconds it actually took.
poll() { local max=$1 t0=$EPOCHREALTIME; shift
  while ! "$@" >/dev/null 2>&1; do (( EPOCHREALTIME - t0 > max )) && { POLL_TOOK=$(printf '%.1f' $(( EPOCHREALTIME - t0 ))); return 1; }; sleep 0.5; done
  POLL_TOOK=$(printf '%.1f' $(( EPOCHREALTIME - t0 ))); }
# tlaunch BOTTLE EXE [MAX]: launches through the test build with --wait (it polls every 0.5 s, up to MAX, default 120 s) and returns its
# exit status: the program's own exit code, or 124 if it was still running at MAX. LAUNCH_CODE = that status, LAUNCH_TOOK = seconds,
# LAUNCH_LINE = the app's own line.
tlaunch() { local out; out=$(ct --launch "$1" "$2" --wait "${3:-120}" 2>&1); LAUNCH_CODE=$?
  LAUNCH_LINE=$(print -r -- "$out" | grep '^launch: ' | tail -1); LAUNCH_TOOK=$(print -r -- "$LAUNCH_LINE" | sed -n 's/.* after \([0-9.]*\) s.*/\1 s/p')
  return $LAUNCH_CODE; }
twine() {   # twine BOTTLE ARGS… — Wine in a throwaway prefix, msync like the app
  local b="$1"; shift
  sandbox-exec -p "$(tw_sandbox_profile)" env CFFIXED_USER_HOME="$TH" HOME="$TH" WINEPREFIX="$(tprefix "$b")" WINEMSYNC=1 WINEDEBUG=-all "$TS/engines/$ENGINE/wswine.bundle/bin/wine" "$@"
}
twineserver() { local b="$1"; shift; WINEPREFIX="$(tprefix "$b")" "$TS/engines/$ENGINE/wswine.bundle/bin/wineserver" "$@"; }

# ---- tripwire over the real data ----
_tw_state() {
  emulate -L zsh
  print "bottles: $(ls -1 "$REAL_SUPPORT/bottles" 2>/dev/null | tr '\n' ' ')"
  print "support-top: $(ls -1A "$REAL_SUPPORT" 2>/dev/null | tr '\n' ' ')"
  print "engines-bin: $(ls -1 "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin" 2>/dev/null | tr '\n' ' ')"
  for b in "$REAL_SUPPORT"/bottles/*(N/); do
    print "bottle $b:t: $(cd "$b" && find . -maxdepth 1 ! -name '*.reg' ! -name 'drive_c' ! -name 'dosdevices' ! -name '.update-timestamp' | sort | tr '\n' ' ')"
    for f in cosmopolitan.env cosmopolitan.apps; do [[ -f "$b/$f" ]] && print "  $f $(shasum -a 256 "$b/$f" | cut -c1-16)"; done
    [[ -d "$b/options" ]] && print "  options-settings $(cd "$b/options" && find . -type f -name '*.env' -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | cut -c1-16)"
  done
  if [[ -f "$REAL_LOG" ]]; then print "log-inode: $(stat -f %i "$REAL_LOG")"; fi
  print "steam-pid: $(pgrep -f 'Steam.steam\.exe' | head -1)"
  print "app-pid: $(pgrep -f "$TESTENV_REPO/Cosmopolitan.app/Contents/MacOS/Cosmopolitan\$" | head -1)"
}
# Cache markers your running Cosmopolitan app updates by itself (scan results, playtime, AVX counts, the registry ledger).
_tw_markers() { emulate -L zsh; for b in "$REAL_SUPPORT"/bottles/*(N/); do [[ -d "$b/options" ]] && print "$b:t $(cd "$b/options" && find . -type f ! -name '*.env' -print0 | sort -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | cut -c1-16)"; done; }
_tw_regs() { emulate -L zsh; for b in "$REAL_SUPPORT"/bottles/*(N/); do for r in system user userdef; do [[ -f "$b/$r.reg" ]] && print "$b:t/$r.reg $(shasum -a 256 "$b/$r.reg" | cut -c1-16)"; done; done; }
tw_snapshot() {
  TW_STATE="$(_tw_state)"; TW_REGS="$(_tw_regs)"; TW_MARKERS="$(_tw_markers)"
  TW_LOG_SIZE=$( [[ -f "$REAL_LOG" ]] && stat -f %z "$REAL_LOG" || print 0 )
  TW_LOG_HEAD=$( [[ -f "$REAL_LOG" ]] && head -c "$TW_LOG_SIZE" "$REAL_LOG" | shasum -a 256 | cut -c1-16 )
}
# tw_check [sandboxed]: fails on any change to your data. A .reg change is attributed to your running Steam only when the test ran
# sandboxed (writes to your Cosmopolitan folder impossible) and Steam's own wineserver is up in that bottle.
# Whether your own Cosmopolitan app or your Steam is running (TW_FAKE_APP / TW_FAKE_STEAM = 0/1 override them, for the rule test only).
_tw_app_running() { [[ -n "$TW_FAKE_APP" ]] && { [[ "$TW_FAKE_APP" == 1 ]]; return; }; [[ -n "$(pgrep -f "$TESTENV_REPO/Cosmopolitan.app/Contents/MacOS/Cosmopolitan\$|/Applications/Cosmopolitan.app/Contents/MacOS/Cosmopolitan\$")" ]]; }
_tw_steam_running() { [[ -n "$TW_FAKE_STEAM" ]] && { [[ "$TW_FAKE_STEAM" == 1 ]]; return; }; [[ -n "$(pgrep -f 'Steam.steam\.exe')" ]]; }
tw_check() {
  emulate -L zsh
  local ok=1 now="$(_tw_state)" regs="$(_tw_regs)"
  [[ "$now" == "$TW_STATE" ]] || { ok=0; print "TRIPWIRE: real data changed:"; diff <(print -r -- "$TW_STATE") <(print -r -- "$now") | sed 's/^/  /'; }
  if [[ -f "$REAL_LOG" ]]; then
    local size=$(stat -f %z "$REAL_LOG") head=$(head -c "$TW_LOG_SIZE" "$REAL_LOG" | shasum -a 256 | cut -c1-16)
    (( size >= TW_LOG_SIZE )) && [[ "$head" == "$TW_LOG_HEAD" ]] || { ok=0; print "TRIPWIRE: your Cosmopolitan.log was truncated or rewritten"; }
  fi
  local markers="$(_tw_markers)"
  if [[ "$markers" != "$TW_MARKERS" ]]; then
    if _tw_app_running; then
      print "note: cache markers in your bottle's options folder changed while your Cosmopolitan app was running (it updates them itself; the test build can't reach them)"
    else ok=0; print "TRIPWIRE: cache markers in your bottle's options folder changed with no Cosmopolitan app running"; fi
  fi
  if [[ "$regs" != "$TW_REGS" ]]; then
    if _tw_steam_running; then   # ct and twine are sandboxed, so the test couldn't have written them
      print "note: registry files changed while your Steam was running; the test could not write there (sandboxed), so Steam's own Wine server wrote them:"
      diff <(print -r -- "$TW_REGS") <(print -r -- "$regs") | grep '^[<>]' | sed 's/^/  /'
    else ok=0; print "TRIPWIRE: registry files of your bottles changed:"; diff <(print -r -- "$TW_REGS") <(print -r -- "$regs") | sed 's/^/  /'; fi
  fi
  (( ok )) && print "tripwire: your bottles, log, Steam and app are untouched"
  (( ok ))
}
# Sandbox profile that makes writes to your real Cosmopolitan data impossible for the test and everything it starts.
tw_sandbox_profile() {
  print "(version 1)(allow default)(deny file-write* (subpath \"$REAL_SUPPORT\") (literal \"$REAL_LOG\") (subpath \"$REAL_HOME/Applications/Cosmopolitan Apps\") (subpath \"$REAL_HOME/Library/Application Support/Sikarugir\"))"
}

testenv_cleanup() {
  emulate -L zsh
  [[ -n "$T" && "$T" == /private/tmp/cosmotest.* ]] || return 0
  for b in "$TS"/bottles/*(N/); do WINEPREFIX="$b" "$TS/engines/$ENGINE/wswine.bundle/bin/wineserver" -k 2>/dev/null; done
  rm -rf "$T"
}
# pid of the wineserver serving a throwaway prefix (it holds /tmp/.wine-<uid>/server-<dev>-<ino>/lock), empty if none
tserverpid() { local p="$(tprefix "$1")"; [[ -d "$p" ]] || return 0; lsof -t "$(printf '/tmp/.wine-%d/server-%x-%x/lock' $(id -u) $(stat -f '%d %i' "$p"))" 2>/dev/null | head -1; }
# Builds the stress test programs into a throwaway bottle (C:\StressTest), with the mingw compilers and the bottle's own Wine Mono.
stress_build() { HOME="$TH" "$TESTENV_REPO/tests/stress/build.sh" "$1" >/dev/null 2>&1 && [[ -f "$(tprefix "$1")/drive_c/StressTest/stress-d3d11-64.exe" ]]; }
