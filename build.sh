#!/bin/bash
set -e
echo ">> Compiling MiniPadle (Apple Silicon M1 Optimized, Ultra-Slim, Fast)..."

# Deteksi Apple Silicon atau buat native arm64
ARCH="arm64"
if [[ "$(uname -m)" == "x86_64" && "$1" != "arm64" ]]; then
    ARCH="x86_64"
fi

clang -x objective-c \
    -arch $ARCH \
    -Oz \
    -flto \
    -DNDEBUG \
    -mmacosx-version-min=11.0 \
    -fno-stack-protector \
    -fno-unwind-tables \
    -fno-asynchronous-unwind-tables \
    -fno-ident \
    -fvisibility=hidden \
    -Wl,-dead_strip \
    -Wl,-no_data_const \
    -Wl,-exported_symbol,_main \
    -framework Cocoa \
    -Isrc/Models \
    -Isrc/Controllers \
    -Isrc/App \
    src/Models/FileNode.m \
    src/Controllers/SettingsWindowController.m \
    src/Controllers/QuickOpenWindowController.m \
    src/Controllers/EditorWindowController.m \
    src/App/Logger.m \
    src/App/AppDelegate.m \
    src/main.m \
    -o MiniPadle

# Strip seluruh debug dan local symbol
strip -x MiniPadle

echo ">> Executable binary size:"
ls -lh MiniPadle
TOTAL_BYTES=$(wc -c < MiniPadle)
echo "Total bytes: $TOTAL_BYTES bytes"

if [ $TOTAL_BYTES -lt 51200 ]; then
    echo ">> [SUCCESS] Ukuran binary DIBAWAH 50KB ($(($TOTAL_BYTES / 1024)) KB)!"
else
    echo ">> [INFO] Ukuran binary: $(($TOTAL_BYTES / 1024)) KB"
fi

echo ">> Packaging MiniPadle.app bundle..."
rm -rf MiniPadle.app MiniPadle.dmg
mkdir -p MiniPadle.app/Contents/MacOS
mkdir -p MiniPadle.app/Contents/Resources
cp MiniPadle MiniPadle.app/Contents/MacOS/

if [ -f src/Resources/AppIcon.icns ]; then
    cp src/Resources/AppIcon.icns MiniPadle.app/Contents/Resources/AppIcon.icns
fi

echo "APPL????" > MiniPadle.app/Contents/PkgInfo

cat << 'PLISTEOF' > MiniPadle.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key><string>MiniPadle</string>
    <key>CFBundleExecutable</key><string>MiniPadle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.fauzan.minipadle</string>
    <key>CFBundleName</key><string>MiniPadle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLISTEOF

echo ">> Creating native macOS .dmg package..."
hdiutil create -volname "MiniPadle" -srcfolder MiniPadle.app -ov -format UDZO MiniPadle.dmg

echo ">> DMG Package Created Successfully:"
ls -lh MiniPadle.dmg

echo "Done! Buka aplikasi dengan: open MiniPadle.app atau buka file MiniPadle.dmg"
