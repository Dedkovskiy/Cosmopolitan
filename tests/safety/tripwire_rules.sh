#!/bin/zsh
# Proves the tripwire's scope on a fake copy of your layout (your real data is only read, for the path listing in step 1).
# Lenient rule 1, cache markers: files under bottles/<name>/options/ except *.env count as a note only while your Cosmopolitan app runs.
# Lenient rule 2, registry: a bottle's .reg keys count as a note only while your Steam runs (the test build is sandboxed), except keys
# Cosmopolitan owns (every AppDefaults key, DllOverrides, and the keys in the bottle's registry ledger): those always fail.
# Every note and failure names the changed files, and for .reg files the changed keys.
# Everything else always fails: bottles added or removed, a bottle's top-level files, options/*.env, the support folder's top level, the
# engine's bin folder, and your log being truncated or rewritten. The sandbox profile itself is shown to block writes.
# set -u, and every path this script writes to is checked to be inside its own throwaway folder before the write.
set -u
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
F=$(mktemp -d /private/tmp/cosmorules.XXXXXX) && [[ "$F" == /private/tmp/cosmorules.?* && -d "$F" ]] || fail "could not make a throwaway folder"
trap 'rm -rf "$F"' EXIT
inF() { local p; for p; do [[ "${p:A}" == "$F"/?* ]] || fail "refusing to write outside $F: $p"; done; }
swap() { inF "$1"; local s="$(<"$1")"; [[ "$s" == *"$2"* ]] || fail "swap: '$2' not in $1"; print -r -- "${s/${(b)2}/$3}" > "$1"; }   # literal, first match
REAL_SUPPORT_REAL="$REAL_SUPPORT"
( inF "$REAL_SUPPORT/bottles/x" ) >/dev/null 2>&1 && fail "control: inF let a path outside $F through"
( inF "$F/../x" ) >/dev/null 2>&1 && fail "control: inF let $F/../x through"
( : "$TRIPWIRE_RULES_UNSET_PROBE" ) 2>/dev/null && fail "control: set -u is not in force"
print "ok: controls: inF refuses your real support folder and $F/../x; set -u stops on an unset variable"

# 1. The exact scope of the marker rule, and what it matches in your real bottles right now.
print "marker rule scope: find \"\$REAL_SUPPORT/bottles/<bottle>/options\" -type f ! -name '*.env'   (nothing outside a bottle's options folder)"
for b in "$REAL_SUPPORT_REAL"/bottles/*(N/); do
  m=("${(@f)$(cd "$b/options" 2>/dev/null && find . -type f ! -name '*.env' | sed 's|^\./||' | sort)}")
  print "  in your bottle '$b:t': ${#m} files, all under $b:t/options/: ${(j:, :)${m[1,6]}}${${m[7]:-}:+, …}"
  for x in $m; do [[ "$x" == *.reg || "$x" == *drive_c* || "$x" == *Cosmopolitan.log* ]] && fail "marker rule would cover $x"; done
done

# 2. A fake layout for the rules.
REAL_SUPPORT="$F/support"; REAL_LOG="$F/Cosmopolitan.log"; B="$REAL_SUPPORT/bottles/Steam"
inF "$REAL_SUPPORT" "$REAL_LOG" "$B" "$B/options" "$B/drive_c" "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin"
mkdir -p "$B/options" "$B/drive_c" "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin"
inF "$B/options/.gfx-game.exe"; print a > "$B/options/.gfx-game.exe"
inF "$B/options/game.exe.env"; print 'DRIVERS=dxmt' > "$B/options/game.exe.env"
inF "$B/cosmopolitan.env"; print 'X=1' > "$B/cosmopolitan.env"
inF "$REAL_LOG"; print 'first line of your log' > "$REAL_LOG"
inF "$B/options/.registry-ledger.json"; print -r -- '[ { "exe" : "game.exe", "key" : "HKCU\\Software\\Wine\\Explorer\\Desktops", "name" : "Cosmopolitan", "owner" : "bottle", "value" : "1280x960" } ]' > "$B/options/.registry-ledger.json"
inF "$B/user.reg"; cat > "$B/user.reg" <<'R'
WINE REGISTRY Version 2
;; All keys relative to \\User\\S-1-5-21-0-0-0-1000

[Control Panel\\Desktop] 1729700000
"LogPixels"=dword:00000060

[Software\\Valve\\Steam] 1729700000
"RunningAppID"=dword:00000000

[Software\\Wine\\AppDefaults\\game.exe\\DllOverrides] 1729700000
"d3d11"="native,builtin"

[Software\\Wine\\DllOverrides] 1729700000
"winemenubuilder.exe"=""

[Software\\Wine\\Explorer\\Desktops] 1729700000
"Cosmopolitan"="1280x960"
R
expect() {   # expect fail|note|pass DESCRIPTION PATH MUTATION [TEXT]: MUTATION is eval'd with $P = PATH, checked to be inside $F first;
  local want=$1 what=$2 P=$3 mut=$4 text=${5:-}   # TEXT, if given, must appear in the tripwire's output (it names files and keys)
  inF "$P"; tw_snapshot; eval "$mut"; local out rc; out=$(tw_check 2>&1); rc=$?
  case $want in
    fail) (( rc != 0 )) || fail "$what: should fail the run, got: $out";;
    note) (( rc == 0 )) && [[ "$out" == *"note:"* ]] || fail "$what: should be a note, got rc $rc: $out";;
    pass) (( rc == 0 )) && [[ "$out" != *"note:"* ]] || fail "$what: should pass cleanly, got rc $rc: $out";;
  esac
  [[ -z "$text" || "$out" == *"$text"* ]] || fail "$what: the output does not name $text: $out"
  print -r -- "ok: $what → $want${text:+ (names $text)}"
}
TW_FAKE_APP=1 TW_FAKE_STEAM=0 expect note "cache marker changed, your app running" "$B/options/.gfx-game.exe" 'print b > "$P"' 'Steam/options/.gfx-game.exe'
TW_FAKE_APP=0 TW_FAKE_STEAM=0 expect fail "cache marker changed, no app running" "$B/options/.gfx-game.exe" 'print c > "$P"' 'Steam/options/.gfx-game.exe'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "a bottle added (app and Steam running)" "$REAL_SUPPORT/bottles/C1" 'mkdir "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "a bottle removed (app and Steam running)" "$REAL_SUPPORT/bottles/C1" 'rmdir "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "bottle file cosmopolitan.env changed" "$B/cosmopolitan.env" 'print X=2 > "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "settings file options/game.exe.env changed" "$B/options/game.exe.env" 'print DRIVERS=dxvk > "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "new item in the support folder" "$REAL_SUPPORT/stray" 'mkdir "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "file added to the engine's bin folder" "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin/StressTest" 'print x > "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "your log truncated" "$REAL_LOG" 'print -n x > "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "your log rewritten at the same size" "$REAL_LOG" 'print -n y > "$P"'
TW_FAKE_APP=1 TW_FAKE_STEAM=0 expect fail "registry key changed, Steam not running (app running)" "$B/user.reg" 'swap "$P" dword:00000000 dword:00000001' 'Steam/user.reg: [Software\\Valve\\Steam]'
TW_FAKE_APP=0 TW_FAKE_STEAM=1 expect note "registry key changed while Steam runs" "$B/user.reg" 'swap "$P" dword:00000001 dword:00000002' 'Steam/user.reg: [Software\\Valve\\Steam]'
TW_FAKE_APP=0 TW_FAKE_STEAM=1 expect fail "owned AppDefaults key changed while Steam runs" "$B/user.reg" 'swap "$P" native,builtin builtin' 'Steam/user.reg: [Software\\Wine\\AppDefaults\\game.exe\\DllOverrides]'
TW_FAKE_APP=0 TW_FAKE_STEAM=1 expect fail "owned DllOverrides key changed while Steam runs" "$B/user.reg" 'swap "$P" winemenubuilder.exe winebrowser.exe' 'Steam/user.reg: [Software\\Wine\\DllOverrides]'
TW_FAKE_APP=0 TW_FAKE_STEAM=1 expect fail "ledger key Explorer\\Desktops changed while Steam runs" "$B/user.reg" 'swap "$P" 1280x960 1024x768' 'Steam/user.reg: [Software\\Wine\\Explorer\\Desktops]'
TW_FAKE_APP=0 TW_FAKE_STEAM=0 expect pass "your log appended to (the app appends)" "$REAL_LOG" 'print more >> "$P"'

# 3. The sandbox every test-build run uses really blocks writes to the protected paths.
inF "$B/drive_c/probe" "$REAL_LOG" "$F/allowed" "$F/control"
/bin/sh -c 'printf x >> "$1"' sh "$F/control" || fail "control: the append probe can't write even without the sandbox"
sandbox-exec -p "$(tw_sandbox_profile)" /usr/bin/touch "$B/drive_c/probe" 2>/dev/null && fail "sandbox let a write into a bottle's drive_c through"
sandbox-exec -p "$(tw_sandbox_profile)" /bin/sh -c 'printf x >> "$1"' sh "$REAL_LOG" 2>/dev/null && fail "sandbox let a write to the log through"
sandbox-exec -p "$(tw_sandbox_profile)" /usr/bin/touch "$F/allowed" || fail "sandbox blocks writes outside the protected paths too"
print "ok: the test sandbox blocks writes into bottles (drive_c too) and the log, and allows everything else"
print "PASS tripwire_rules"
