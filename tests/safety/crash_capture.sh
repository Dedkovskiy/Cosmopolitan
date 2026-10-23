#!/bin/zsh
# Item 34: crash capture. A stand-in prints a marker line and exits with code 5; a crash record appears with the last log lines (the
# marker), the driver set and the versions, and the bug report attaches it automatically, with your username and home folder removed.
source "${0:A:h}/../lib/testenv.sh"; testenv_init >/dev/null || exit 1; trap testenv_cleanup EXIT
fail() { print "FAIL: $*"; exit 1; }
tw_snapshot
ct --newbottle K >/dev/null 2>&1; [[ -d "$(tprefix K)/drive_c" ]] || fail "throwaway bottle not created"
mkdir -p "$(tprefix K)/drive_c/Program Files/Crashy"; EXE="$(tprefix K)/drive_c/Program Files/Crashy/Crashy.exe"
print '#include <stdio.h>\nint main(void){ puts("stand-in crash marker 7c41"); fflush(stdout); return 5; }' > "$T/c.c"
x86_64-w64-mingw32-gcc -O2 -s "$T/c.c" -o "$EXE" || fail "could not build the stand-in"
ct --launch K "$EXE" --wait 60 >/dev/null 2>&1; rc=$?; (( rc == 5 )) || fail "the stand-in exited with $rc, expected 5"
rec=$(ls "$TS/crash-reports/" 2>/dev/null | grep '^Crashy ' | tail -1); [[ -n "$rec" ]] || fail "no crash record in $TS/crash-reports"
R="$TS/crash-reports/$rec"
grep -q "Crashy exited with code 5" "$R" && grep -q "^Drivers: " "$R" && grep -q "^Versions: Cosmopolitan " "$R" && grep -q "stand-in crash marker 7c41" "$R" || fail "the record lacks a part: $(cat "$R" | head -8)"
print -r -- "ok: crash record '$rec': $(grep -E '^(Drivers|Versions):' "$R" | cut -c1-110 | tr '\n' ' ')… and the marker line from the log"
rep=$(ct --bugreport-text K "$EXE" 2>&1)
[[ "$rep" == *"### Last crash"* && "$rep" == *"Crashy exited with code 5"* && "$rep" == *"stand-in crash marker 7c41"* ]] || fail "the bug report doesn't attach the crash: $(print -r -- "$rep" | grep -n 'Last crash' | head -2)"
[[ "$rep" != *"$(id -un)"* ]] || fail "the bug report contains the username"
print "ok: the bug report attaches the crash record automatically, with the username and home folder removed"
tw_check || fail "your real data changed"
print "PASS crash_capture"
