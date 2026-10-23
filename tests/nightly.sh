#!/bin/zsh
# Item 38: the nightly self-test. Runs every suite in throwaway homes (tests/run-all.sh: the test build, HOME and CFFIXED_USER_HOME set to a
# throwaway folder, the isolation guard and sandbox on, the tripwire over your real data) and reports only failures: a notification and the
# log kept in ~/Library/Logs/Cosmopolitan self-test/. A passing night leaves nothing behind. COSMO_NIGHTLY_CMD replaces the suite (tests).
emulate -L zsh
REPO="${0:A:h:h}"; OUT="$HOME/Library/Logs/Cosmopolitan self-test"; mkdir -p "$OUT"
stamp=$(date +%Y-%m-%d-%H%M); log="$OUT/$stamp.log"
( cd "$REPO" && eval "${COSMO_NIGHTLY_CMD:-tests/run-all.sh 30}" ) > "$log" 2>&1; rc=$?
if (( rc == 0 )); then rm -f "$log"; exit 0; fi
failed=$(grep -E '^== .*exit [1-9]' "$log" | sed 's/^== //; s/: exit.*//' | tr '\n' ' ')
[[ "${COSMO_NIGHTLY_NOTIFY:-1}" == 1 ]] && osascript -e "display notification \"${failed:-the run} failed (exit $rc). Log: Library/Logs/Cosmopolitan self-test/$stamp.log\" with title \"Cosmopolitan self-test\"" >/dev/null 2>&1
print "self-test failed (exit $rc): $failed— $log"
exit $rc
