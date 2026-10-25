#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
DESKNAMES_CACHE="../../work/DeskNames-build/cache-$(pwd | cksum | awk '{print $1}')"
mkdir -p "$DESKNAMES_CACHE"
# Some Command Line Tools installations ship duplicate SwiftBridging module maps.
# A compiler-only overlay avoids changing the installed toolchain.
EXTRA_FLAGS=()
if [[ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
    mkdir -p ../../work/toolchain
    print '// Provided by bridging.modulemap' > ../../work/toolchain/empty.modulemap
    python3 - <<'PYOVERLAY'
import json, os
folder = os.path.abspath("../../work/toolchain")
with open(folder + "/overlay.json", "w") as out:
    json.dump({"version": 0, "roots": [{"type": "file", "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap", "external-contents": folder + "/empty.modulemap"}]}, out)
PYOVERLAY
    EXTRA_FLAGS=(-vfsoverlay ../../work/toolchain/overlay.json)
fi
swiftc "${EXTRA_FLAGS[@]}" -O -swift-version 5 -module-cache-path "$DESKNAMES_CACHE" -target arm64-apple-macosx13.0 Sources/DeskNames/*.swift -o ../../work/DeskNames-build/DeskNames
APP="${DESKNAMES_APP_OUTPUT:-../DeskNames.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
DESKNAMES_ICONSET="../../work/DeskNames.iconset"
mkdir -p "$DESKNAMES_ICONSET"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" Resources/AppIcon.png --out "$DESKNAMES_ICONSET/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" Resources/AppIcon.png --out "$DESKNAMES_ICONSET/icon_${points}x${points}@2x.png" >/dev/null
done
python3 Resources/package_icon.py "$DESKNAMES_ICONSET" Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp ../../work/DeskNames-build/DeskNames "$APP/Contents/MacOS/DeskNames"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DeskNames</string>
<key>CFBundleIdentifier</key><string>local.desknames.app</string>
<key>CFBundleName</key><string>DeskNames</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>20</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

# Package the signed app for distribution.
ditto -c -k --sequesterRsrc --keepParent "$APP" ../DeskNames.zip
