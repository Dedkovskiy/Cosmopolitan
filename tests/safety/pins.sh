#!/bin/zsh
# Item 8: no automatic Sikarugir downloads, D3DMetal never extracted from the template, pinned engine/template enforced.
source "${0:A:h}/../lib/testenv.sh"
fail() { print "FAIL: $*"; exit 1; }
REPO="$TESTENV_REPO"

# 1. The code: no "newest" Sikarugir lookups, no template download outside the pinned setup step, D3DMetal never copied from a template.
grep -rn "NewestVersion.txt\|EngineList.txt" "$REPO/Sources" && fail "code still looks up the newest Sikarugir template or engine"
[[ $(grep -rln "Sikarugir-App/Template/releases" "$REPO/Sources") == "$REPO/Sources/Core/Components.swift" ]] || fail "template URL used outside the pins"
grep -rn "renderer/d3dmetal" "$REPO/Sources" | grep -v "exclude\|Components.swift" && fail "something copies d3dmetal from a template"
grep -rn -i "Cosmopolitan-testrun\|d3dmetal-old" "$REPO/Sources" "$REPO/scripts" "$REPO/Resources" "$REPO/tests" --exclude=pins.sh && fail "code references the Sikarugir D3DMetal copy in ~/Cosmopolitan-testrun-2032"
print "ok: no newest-version lookups; the template URL exists only as a pin; d3dmetal only appears in the extraction exclude; nothing references the Sikarugir D3DMetal copy"

# 2. The extraction command from Setup.swift, run on a fake template archive: d3dmetal and apple_gptk must not come out.
W="$(mktemp -d /private/tmp/cosmopins.XXXXXX)"; trap 'rm -rf "$W"; testenv_cleanup' EXIT
mkdir -p "$W/src/Template-1.0.24.app/Contents/SharedSupport/renderer/"{d3dmetal/wine,apple_gptk,dxmt/wine}
print x > "$W/src/Template-1.0.24.app/Contents/SharedSupport/renderer/d3dmetal/wine/d3d12.dll"; print y > "$W/src/Template-1.0.24.app/Contents/SharedSupport/renderer/dxmt/wine/d3d11.dll"
(cd "$W/src" && tar cJf "$W/t.tar.xz" Template-1.0.24.app)
cmd=$(grep -o "tar xf t.tar.xz --exclude '[^']*' --exclude '[^']*'" "$REPO/Sources/Features/Setup.swift") || fail "extraction command not found in Setup.swift"
mkdir -p "$W/out" && cp "$W/t.tar.xz" "$W/out/" && (cd "$W/out" && eval "$cmd")
[[ -f "$W/out/Template-1.0.24.app/Contents/SharedSupport/renderer/dxmt/wine/d3d11.dll" ]] || fail "extraction lost dxmt"
[[ ! -e "$W/out/Template-1.0.24.app/Contents/SharedSupport/renderer/d3dmetal" && ! -e "$W/out/Template-1.0.24.app/Contents/SharedSupport/renderer/apple_gptk" ]] || fail "d3dmetal or apple_gptk was extracted"
print "ok: setup's extraction leaves out d3dmetal and apple_gptk ($cmd)"

# 3. --update only checks: nothing downloaded, nothing replaced.
testenv_init >/dev/null || exit 1
before=$(ct --tree-hash "$TS/engines/renderer/dxmt" "$TS/engines/renderer/dxvk" 2>/dev/null | grep -v '^$')
out=$(ct --update 2>&1)
after=$(ct --tree-hash "$TS/engines/renderer/dxmt" "$TS/engines/renderer/dxvk" 2>/dev/null | grep -v '^$')
[[ "$before" == "$after" ]] || fail "--update changed installed drivers"
[[ "$out" != *"downloading"* && ! -e "$TH/Library/Application Support/Sikarugir/Template" && -z "$(ls "$TS/engines" | grep -v -e '^WS12WineSikarugir10.0_8$' -e '^renderer$' -e '^gstreamer$')" ]] || fail "--update downloaded something: $out"
print -r -- "ok: --update only reports: $(print -r -- "$out" | grep -E '^[•✓]' | tr '\n' ' ')"
testenv_cleanup

# 4. Setup refuses a template part that doesn't match its pin, and an engine that doesn't match its SHA-256.
TESTENV_NO_ENGINE=1 testenv_init >/dev/null || exit 1
SK="$TH/Library/Application Support/Sikarugir"; mkdir -p "$SK/Engines" "$SK/Template"
cp -c "$REAL_HOME/Library/Application Support/Sikarugir/Engines/$ENGINE.tar.xz" "$SK/Engines/"
cp -cR "$REAL_HOME/Library/Application Support/Sikarugir/Template/Template-1.0.24.app" "$SK/Template/"; rm -rf "$SK"/Template/*/Contents/SharedSupport/renderer/{d3dmetal,apple_gptk}
f=$(ls "$SK"/Template/Template-1.0.24.app/Contents/SharedSupport/renderer/dxmt/wine/x86_64-windows/*.dll | head -1); cp "$f" "$f.x"; mv "$f.x" "$f"; printf 'Z' | dd of="$f" bs=1 seek=100 conv=notrunc 2>/dev/null
out=$(ct --setup 2>&1); rc=$?
[[ $rc != 0 && "$out" == *"doesn't match the pinned Template-1.0.24 (SharedSupport/renderer/dxmt)"* ]] || fail "setup accepted a changed template file (exit $rc): $(print -r -- "$out" | tail -2)"
[[ ! -d "$TS/engines/renderer/dxmt" ]] || fail "a driver was installed from a mismatching template"
print "ok: setup refused a template whose dxmt differs by one byte; nothing installed"
rm -rf "$SK/Template/Template-1.0.24.app"; cp -cR "$REAL_HOME/Library/Application Support/Sikarugir/Template/Template-1.0.24.app" "$SK/Template/"; rm -rf "$SK"/Template/*/Contents/SharedSupport/renderer/{d3dmetal,apple_gptk}
head -c 3000000 /dev/urandom > "$SK/Engines/$ENGINE.tar.xz"; head -c 3000000 /dev/urandom > "$W/bad-engine.tar.xz"
out=$(COSMO_TEST_URL_WS12WineSikarugir10_0_8_tar_xz="file://$W/bad-engine.tar.xz" ct --setup 2>&1); rc=$?
[[ $rc != 0 && "$out" == *"didn't match its pinned SHA-256"* && ! -e "$TS/engines/$ENGINE/wswine.bundle" ]] || fail "setup used an engine that doesn't match its pin (exit $rc): $(print -r -- "$out" | tail -2)"
print "ok: setup refused an engine tarball with the wrong SHA-256 (local copy and download); nothing installed"
print "PASS pins"
