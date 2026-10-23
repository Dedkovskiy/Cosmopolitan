#!/bin/zsh
# Item 38: the nightly runner reports only failures. With a stand-in suite in a throwaway home: a failing run keeps its log and names the
# failed suite; a passing run leaves nothing behind. The installer's LaunchAgent plist is checked with plutil (not loaded here).
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
W=$(mktemp -d /private/tmp/cosmonightly.XXXXXX) && [[ -d "$W" ]] || fail "no throwaway folder"; trap 'rm -rf "$W"' EXIT
O="$W/Library/Logs/Cosmopolitan self-test"
out=$(HOME="$W" COSMO_NIGHTLY_NOTIFY=0 COSMO_NIGHTLY_CMD='print "== native: exit 0 after 1s"; print "== repair_scope: exit 1 after 2s"; exit 1' "$TESTENV_REPO/tests/nightly.sh"); rc=$?
(( rc == 1 )) && [[ "$out" == "self-test failed (exit 1): repair_scope — $O/"*.log && $(ls "$O" | wc -l) -eq 1 ]] || fail "failing run: rc $rc, '$out', logs: $(ls "$O" 2>/dev/null)"
print -r -- "ok: a failing night: '${out//$W/~}', log kept"
rm -rf "$O"; out=$(HOME="$W" COSMO_NIGHTLY_NOTIFY=0 COSMO_NIGHTLY_CMD='print "== native: exit 0 after 1s"; exit 0' "$TESTENV_REPO/tests/nightly.sh"); rc=$?
(( rc == 0 )) && [[ -z "$out" && -z "$(ls "$O" 2>/dev/null)" ]] || fail "passing run: rc $rc, '$out', logs: $(ls "$O" 2>/dev/null)"
print "ok: a passing night prints nothing and leaves no log"
grep -q 'launchctl bootstrap "gui/$(id -u)" "$PLIST"' "$TESTENV_REPO/scripts/install-nightly.sh" || fail "installer doesn't load the agent"
P=$(sed -n '/^cat > "\$PLIST" <<P$/,/^P$/p' "$TESTENV_REPO/scripts/install-nightly.sh" | sed '1d;$d' | sed "s|\$LABEL|local.cosmopolitan.selftest|g; s|\$REPO|$TESTENV_REPO|g")
print -r -- "$P" > "$W/agent.plist"; plutil -lint "$W/agent.plist" >/dev/null || fail "the LaunchAgent plist is invalid"
print "ok: the LaunchAgent plist is valid ($(plutil -extract StartCalendarInterval json -o - "$W/agent.plist"), runs tests/nightly.sh)"
print "PASS nightly"
