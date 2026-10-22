#!/bin/sh
# Release: builds the app, zips it, signs it with the Sparkle EdDSA key and (re)generates dist/appcast.xml.
# Usage: COSMO_VERSION=1.1 ./release.sh      then upload dist/*.zip and dist/appcast.xml to the feed location (SUFeedURL in build.sh,
# override with COSMO_FEED_URL=https://… ). The private key lives in the login Keychain (created by Sparkle/bin/generate_keys).
set -e; cd "$(dirname "$0")"
export COSMO_VERSION=${COSMO_VERSION:-1.0}; export COSMO_BUILD=${COSMO_BUILD:-$(date +%Y%m%d%H%M)}
./build.sh
mkdir -p dist; rm -f "dist/Cosmopolitan-$COSMO_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent Cosmopolitan.app "dist/Cosmopolitan-$COSMO_VERSION.zip"
# Appcast: generate_appcast signs every archive in dist/ and writes dist/appcast.xml (older appcast entries are kept).
./Sparkle/bin/generate_appcast dist/
echo "Release $COSMO_VERSION ($COSMO_BUILD): dist/Cosmopolitan-$COSMO_VERSION.zip + dist/appcast.xml"
echo "Note: the app zip contains no D3DMetal; engines/drivers are fetched by the app itself (see dist.sh for the full offline bundle)."
