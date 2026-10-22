#!/bin/sh
# Release: builds the app, zips it, signs it with the Sparkle EdDSA key and (re)generates dist/appcast.xml.
# Usage: COSMO_VERSION=1.1 ./release.sh      then upload dist/*.zip and dist/appcast.xml to the feed location (SUFeedURL in build.sh,
# override with COSMO_FEED_URL=https://… ). The private key lives in the login Keychain (created by Sparkle/bin/generate_keys).
set -e; cd "$(dirname "$0")/.."
export COSMO_VERSION=${COSMO_VERSION:-1.0}; export COSMO_BUILD=${COSMO_BUILD:-$(date +%Y%m%d%H%M)}
scripts/build.sh
mkdir -p dist; rm -f "dist/Cosmopolitan-$COSMO_VERSION.zip" "dist/Cosmopolitan-$COSMO_VERSION.dSYM.zip"
ditto -c -k --sequesterRsrc --keepParent Cosmopolitan.app "dist/Cosmopolitan-$COSMO_VERSION.zip"
# Debug symbols: separate archive, same version. Symbolicate a crash report with:
#   atos -o Cosmopolitan.app.dSYM/Contents/Resources/DWARF/Cosmopolitan -arch arm64 -l <load address> <crash addresses>
mkdir -p dsyms; ditto -c -k --keepParent Cosmopolitan.app.dSYM "dist/Cosmopolitan-$COSMO_VERSION.dSYM.zip"
cp -R Cosmopolitan.app.dSYM "dsyms/Cosmopolitan-$COSMO_VERSION-$COSMO_BUILD.dSYM"   # local archive of every shipped build's symbols
# Appcast: generate_appcast signs every app archive in dist/ and writes dist/appcast.xml (older entries are kept). dSYM zips are not update items.
mkdir -p dist/appcast && cp "dist/Cosmopolitan-$COSMO_VERSION.zip" dist/appcast/ && ./Sparkle/bin/generate_appcast dist/appcast/ && mv dist/appcast/appcast.xml dist/appcast.xml && rm -rf dist/appcast
echo "Release $COSMO_VERSION ($COSMO_BUILD):"
echo "  dist/Cosmopolitan-$COSMO_VERSION.zip        the app (Sparkle update item)"
echo "  dist/Cosmopolitan-$COSMO_VERSION.dSYM.zip   debug symbols (attach to the GitHub release; never inside the app)"
echo "  dist/appcast.xml                          signed feed; host it at the SUFeedURL in build.sh"
# Upload when a GitHub remote exists: the appcast can be served straight from the release assets
#   (SUFeedURL = https://github.com/<user>/<repo>/releases/latest/download/appcast.xml).
if command -v gh >/dev/null && git remote get-url origin >/dev/null 2>&1; then
  gh release create "v$COSMO_VERSION" "dist/Cosmopolitan-$COSMO_VERSION.zip" "dist/Cosmopolitan-$COSMO_VERSION.dSYM.zip" dist/appcast.xml --title "Cosmopolitan $COSMO_VERSION" --notes "Build $COSMO_BUILD" || echo "gh release failed (already exists?)"
else echo "No GitHub remote yet: add one (git remote add origin …) and rerun to upload with gh."; fi
echo "Note: the app zip contains no D3DMetal; engines/drivers are fetched by the app itself (see dist.sh for the full offline bundle)."
