#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
app="$PWD/build/Tangerine.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Tangerine "$app/Contents/MacOS/Tangerine"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.tangerine.mac</string>
<key>CFBundleName</key><string>Tangerine</string>
<key>CFBundleDisplayName</key><string>Tangerine</string>
<key>CFBundleExecutable</key><string>Tangerine</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [ -f .env ]; then
  # Parse only the generated hexadecimal token; never source executable .env content.
  token="$(sed -n 's/^TANGERINE_TOKEN=\([a-f0-9]*\)$/\1/p' .env)"
  if [[ "$token" =~ ^[a-f0-9]{64}$ ]]; then
    printf '%s' "$token" > "$app/Contents/Resources/worker-token"
    chmod 600 "$app/Contents/Resources/worker-token"
  fi
fi
codesign --force --sign - "$app"
printf 'Built %s\n' "$app"
