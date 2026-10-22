#!/bin/zsh
# Proves the tripwire's scope on a fake copy of your layout (your real data is only read, for the path listing in step 1).
# Lenient rule 1, cache markers: files under bottles/<name>/options/ except *.env count as a note only while your Cosmopolitan app runs.
# Lenient rule 2, registry: a bottle's *.reg files count as a note only while your Steam runs (the test build is sandboxed).
# Everything else always fails: bottles added or removed, a bottle's top-level files, options/*.env, the support folder's top level, the
# engine's bin folder, and your log being truncated or rewritten. The sandbox profile itself is shown to block writes.
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
REAL_SUPPORT_REAL="$REAL_SUPPORT"; REAL_LOG_REAL="$REAL_LOG"
F=$(mktemp -d /private/tmp/cosmorules.XXXXXX); trap 'rm -rf "$F"' EXIT

# 1. The exact scope of the marker rule, and what it matches in your real bottles right now.
print "marker rule scope: find \"\$REAL_SUPPORT/bottles/<bottle>/options\" -type f ! -name '*.env'   (nothing outside a bottle's options folder)"
for b in "$REAL_SUPPORT_REAL"/bottles/*(N/); do
  m=("${(@f)$(cd "$b/options" 2>/dev/null && find . -type f ! -name '*.env' | sed 's|^\./||' | sort)}")
  print "  in your bottle '$b:t': ${#m} files, all under $b:t/options/: ${(j:, :)${m[1,6]}}${${m[7]:+, …}}"
  for x in $m; do [[ "$x" == *.reg || "$x" == *drive_c* || "$x" == *Cosmopolitan.log* ]] && fail "marker rule would cover $x"; done
done

# 2. A fake layout for the rules.
REAL_SUPPORT="$F/support"; REAL_LOG="$F/Cosmopolitan.log"; B="$REAL_SUPPORT/bottles/Steam"
mkdir -p "$B/options" "$B/drive_c" "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin"
print a > "$B/options/.gfx-game.exe"; print 'DRIVERS=dxmt' > "$B/options/game.exe.env"; print 'X=1' > "$B/cosmopolitan.env"
print 'reg' > "$B/user.reg"; print 'first line of your log' > "$REAL_LOG"
expect() {   # expect fail|note|pass DESCRIPTION SHELL-MUTATION (run with the TW_FAKE_* settings given before the call)
  local want=$1 what=$2 mut=$3
  tw_snapshot; eval "$mut"; local out; out=$(tw_check 2>&1); local rc=$?
  case $want in
    fail) (( rc != 0 )) || fail "$what: should fail the run, got: $out";;
    note) (( rc == 0 )) && [[ "$out" == *"note:"* ]] || fail "$what: should be a note, got rc $rc: $out";;
    pass) (( rc == 0 )) && [[ "$out" != *"note:"* ]] || fail "$what: should pass cleanly, got rc $rc: $out";;
  esac
  print "ok: $what → $want"
}
TW_FAKE_APP=1 TW_FAKE_STEAM=0 expect note "cache marker options/.gfx-game.exe changed, your app running" 'print b > "$B/options/.gfx-game.exe"'
TW_FAKE_APP=0 TW_FAKE_STEAM=0 expect fail "cache marker changed, no app running" 'print c > "$B/options/.gfx-game.exe"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "a bottle added (app and Steam running)" 'mkdir "$REAL_SUPPORT/bottles/C1"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "a bottle removed (app and Steam running)" 'rmdir "$REAL_SUPPORT/bottles/C1"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "bottle file cosmopolitan.env changed" 'print X=2 > "$B/cosmopolitan.env"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "settings file options/game.exe.env changed" 'print DRIVERS=dxvk > "$B/options/game.exe.env"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "new item in the support folder" 'mkdir "$REAL_SUPPORT/stray"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "file added to the engine's bin folder" 'print x > "$REAL_SUPPORT/engines/$ENGINE/wswine.bundle/bin/StressTest"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "your log truncated" 'print -n x > "$REAL_LOG"'
TW_FAKE_APP=1 TW_FAKE_STEAM=1 expect fail "your log rewritten at the same size" 'print -n y > "$REAL_LOG"'
TW_FAKE_APP=1 TW_FAKE_STEAM=0 expect fail "registry file user.reg changed, Steam not running (app running)" 'print reg2 > "$B/user.reg"'
TW_FAKE_APP=0 TW_FAKE_STEAM=1 expect note "registry file user.reg changed while Steam runs" 'print reg3 > "$B/user.reg"'
TW_FAKE_APP=0 TW_FAKE_STEAM=0 expect pass "your log appended to (the app appends)" 'print more >> "$REAL_LOG"'

# 3. The sandbox every test-build run uses really blocks writes to the protected paths.
sandbox-exec -p "$(tw_sandbox_profile)" /usr/bin/touch "$B/drive_c/probe" 2>/dev/null && fail "sandbox let a write into a bottle's drive_c through"
sandbox-exec -p "$(tw_sandbox_profile)" /bin/sh -c "print x >> '$REAL_LOG'" 2>/dev/null && fail "sandbox let a write to the log through"
sandbox-exec -p "$(tw_sandbox_profile)" /usr/bin/touch "$F/allowed" || fail "sandbox blocks writes outside the protected paths too"
print "ok: the test sandbox blocks writes into bottles (drive_c too) and the log, and allows everything else"
print "PASS tripwire_rules"
