#!/bin/sh
set -eu
cd "$(dirname "$0")"
swift build --package-path mac -c release
app="$(pwd)/Toolbox.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp mac/.build/release/ToolboxApp "$app/Contents/MacOS/ToolboxApp"
cp mac/Info.plist "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"
iconset="$(pwd)/mac/.build/AppIcon.iconset"
mkdir -p "$iconset"
master="$iconset/icon_512x512@2x.png"
sips -s format png mac/Assets/AppIcon.svg --out "$master" >/dev/null
for spec in \
  '16 icon_16x16.png' '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' '512 icon_256x256@2x.png' \
  '512 icon_512x512.png'; do
  pixels="${spec%% *}"
  name="${spec#* }"
  sips -z "$pixels" "$pixels" "$master" --out "$iconset/$name" >/dev/null
done
iconutil -c icns -o "$app/Contents/Resources/AppIcon.icns" "$iconset"
printf '%s\n' "Built $app"
