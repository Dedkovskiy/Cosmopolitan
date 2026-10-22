#!/bin/sh
# Builds Cosmopolitan.app next to this script.
set -e; cd "$(dirname "$0")/.."   # repo root (scripts/ lives one level down)
rm -rf Cosmopolitan.app; mkdir -p Cosmopolitan.app/Contents/MacOS Cosmopolitan.app/Contents/Resources Cosmopolitan.app/Contents/Frameworks
# Sparkle (MIT) for auto-updates: framework embedded, EdDSA public key in Info.plist, feed URL set in release.sh's appcast.
cp -R Sparkle/Sparkle.framework Cosmopolitan.app/Contents/Frameworks/
# -g keeps debug info; dsymutil moves it into a separate Cosmopolitan.app.dSYM (shipped next to releases, never inside the app).
swiftc -parse-as-library -O -g -F Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o Cosmopolitan.app/Contents/MacOS/Cosmopolitan $(find Sources -name '*.swift' | sort)
dsymutil Cosmopolitan.app/Contents/MacOS/Cosmopolitan -o Cosmopolitan.app.dSYM 2>/dev/null
strip -S Cosmopolitan.app/Contents/MacOS/Cosmopolitan 2>/dev/null   # app stays small; symbols live in the dSYM
PUBKEY=$(cat Sparkle/public-key.txt 2>/dev/null); FEED=${COSMO_FEED_URL:-https://cyber-prinzesse.github.io/Cosmopolitan/appcast.xml}
cp AppIcon.icns Cosmopolitan.app/Contents/Resources/  # built once from icon.png: sips -z … + iconutil -c icns
cp TERMS.txt THIRD_PARTY_NOTICES.md README.md Cosmopolitan.app/Contents/Resources/   # shown on first run / referenced from the UI
cat > Cosmopolitan.app/Contents/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>CFBundleName</key><string>Cosmopolitan</string><key>CFBundleExecutable</key><string>Cosmopolitan</string>
<key>CFBundleIdentifier</key><string>local.cosmopolitan</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>AppIcon</string><key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.games</string>
<key>CFBundleShortVersionString</key><string>${COSMO_VERSION:-1.0}</string><key>CFBundleVersion</key><string>${COSMO_BUILD:-$(date +%Y%m%d%H%M)}</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>local.cosmopolitan</string><key>CFBundleURLSchemes</key><array><string>cosmopolitan</string></array></dict></array>
<key>SUFeedURL</key><string>$FEED</string><key>SUPublicEDKey</key><string>$PUBKEY</string><key>SUEnableAutomaticChecks</key><true/></dict></plist>
P
codesign --force --sign - Cosmopolitan.app
