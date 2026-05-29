#!/bin/bash
# Native arm64 (or universal) build of Avro Keyboard input method using Command Line Tools.
# Usage: ./build.sh [arch...]   default: arm64    (e.g. ./build.sh arm64 x86_64 for universal)
set -euo pipefail
cd "$(dirname "$0")"
SDK="$(xcrun --show-sdk-path)"
ARCHES="${*:-arm64}"
ARCHFLAGS=""; for a in $ARCHES; do ARCHFLAGS="$ARCHFLAGS -arch $a"; done
APP="build/Avro Keyboard.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/English.lproj"

clang $ARCHFLAGS -isysroot "$SDK" -mmacosx-version-min=11.0 \
  -I. -include AvroKeyboard_Prefix.pch -fobjc-exceptions -fno-objc-arc -w \
  ./*.m \
  -framework Cocoa -framework InputMethodKit -lsqlite3 -licucore \
  -o "$APP/Contents/MacOS/Avro Keyboard"

cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Avro Keyboard" "$APP/Contents/Info.plist" 2>/dev/null || true
printf 'APPL????' > "$APP/Contents/PkgInfo"
cp avro.icns autodict.dct data.json database.db3 regex.json preferences.plist \
   Icons/AutoCorrect.png Icons/Credits.png Icons/General.png "$APP/Contents/Resources/"
cp -R Credits.rtfd "$APP/Contents/Resources/"
cp -R English.lproj/MainMenu.nib English.lproj/preferences.nib English.lproj/InfoPlist.strings \
   "$APP/Contents/Resources/English.lproj/"
codesign --force --sign - "$APP"
echo "BUILT: $APP"
