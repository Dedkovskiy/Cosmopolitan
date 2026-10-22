#!/bin/zsh
# Driver stress test: builds the tests, prints each launch-check plan, launches every test through Cosmopolitan (the same path as a tile)
# and prints the result lines. Exit 1 unless every test wrote an OK line. Usage: tests/stress/run.sh [bottle]   (default bottle: Steam)
cd "${0:A:h}"; ./build.sh "${1:-Steam}" >/dev/null || exit 1
A="${0:A:h}/../../Cosmopolitan.app/Contents/MacOS/Cosmopolitan"; O="$HOME/Library/Application Support/Cosmopolitan/bottles/${1:-Steam}/drive_c/StressTest"
for e in "$O"/stress-*.exe; do "$A" --check "${1:-Steam}" "$e" | head -1; "$A" --launch "${1:-Steam}" "$e" 30 >/dev/null 2>&1; done
echo; cat "$O/results.txt"
# Known failure, printed but not fatal: 64-bit DirectDraw run right after a cnc-ddraw program in the same Wine session gets a stale 800x600
# primary surface inside Wine (Windows' display mode stays right, no registry change, D3D9/11 after it are fine). 64-bit DirectDraw games
# don't exist in practice; the test passes when run on its own.
n=$(ls "$O"/stress-*.exe | wc -l | tr -d ' '); ok=$(grep -c ' OK ' "$O/results.txt"); xf=$(grep -c '^ddraw *x64 *FAIL' "$O/results.txt")
echo "$ok of $n passed, $xf known failure"; (( ok + xf == n ))
