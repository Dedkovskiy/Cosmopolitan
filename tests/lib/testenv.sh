#!/bin/zsh
# Shared test environment. Source it, then call testenv_init. Gives:
#   ct ARGS…        the test build (bundle id local.cosmopolitan.test → its own settings) with a throwaway home (HOME, CFFIXED_USER_HOME
#                   and COSMO_TEST_HOME all point at it, so the app's support folder, bottles and log live there)
#   tw_snapshot / tw_check   tripwire over YOUR real data: bottles folder, Cosmopolitan log, Steam bottle, running Steam and app
#   testenv_cleanup  stops the throwaway prefixes' wineservers and removes the throwaway folder
# Nothing here writes outside the throwaway folder. The engine and backends are APFS clones (no extra disk space).

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

ct() { CFFIXED_USER_HOME="$TH" HOME="$TH" COSMO_TEST_HOME="$TH" "$T/CosmopolitanTest.app/Contents/MacOS/Cosmopolitan" "$@"; }
tprefix() { print -r -- "$TS/bottles/$1"; }
twine() {   # twine BOTTLE ARGS… — Wine in a throwaway prefix, msync like the app
  local b="$1"; shift
  CFFIXED_USER_HOME="$TH" HOME="$TH" WINEPREFIX="$(tprefix "$b")" WINEMSYNC=1 WINEDEBUG=-all "$TS/engines/$ENGINE/wswine.bundle/bin/wine" "$@"
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
    [[ -d "$b/options" ]] && print "  options $(cd "$b/options" && find . -type f -exec stat -f '%N %z %m' {} + | sort | shasum -a 256 | cut -c1-16)"
  done
  if [[ -f "$REAL_LOG" ]]; then print "log-inode: $(stat -f %i "$REAL_LOG")"; fi
  print "steam-pid: $(pgrep -f 'Steam.steam\.exe' | head -1)"
  print "app-pid: $(pgrep -f "$TESTENV_REPO/Cosmopolitan.app/Contents/MacOS/Cosmopolitan\$" | head -1)"
}
_tw_regs() { emulate -L zsh; for b in "$REAL_SUPPORT"/bottles/*(N/); do for r in system user userdef; do [[ -f "$b/$r.reg" ]] && print "$b:t/$r.reg $(shasum -a 256 "$b/$r.reg" | cut -c1-16)"; done; done; }
tw_snapshot() {
  TW_STATE="$(_tw_state)"; TW_REGS="$(_tw_regs)"
  TW_LOG_SIZE=$( [[ -f "$REAL_LOG" ]] && stat -f %z "$REAL_LOG" || print 0 )
  TW_LOG_HEAD=$( [[ -f "$REAL_LOG" ]] && head -c "$TW_LOG_SIZE" "$REAL_LOG" | shasum -a 256 | cut -c1-16 )
}
# tw_check [sandboxed]: fails on any change to your data. A .reg change is attributed to your running Steam only when the test ran
# sandboxed (writes to your Cosmopolitan folder impossible) and Steam's own wineserver is up in that bottle.
tw_check() {
  emulate -L zsh
  local ok=1 now="$(_tw_state)" regs="$(_tw_regs)"
  [[ "$now" == "$TW_STATE" ]] || { ok=0; print "TRIPWIRE: real data changed:"; diff <(print -r -- "$TW_STATE") <(print -r -- "$now") | sed 's/^/  /'; }
  if [[ -f "$REAL_LOG" ]]; then
    local size=$(stat -f %z "$REAL_LOG") head=$(head -c "$TW_LOG_SIZE" "$REAL_LOG" | shasum -a 256 | cut -c1-16)
    (( size >= TW_LOG_SIZE )) && [[ "$head" == "$TW_LOG_HEAD" ]] || { ok=0; print "TRIPWIRE: your Cosmopolitan.log was truncated or rewritten"; }
  fi
  if [[ "$regs" != "$TW_REGS" ]]; then
    if [[ "$1" == sandboxed && -n "$(pgrep -f 'Steam.steam\.exe')" ]]; then
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
