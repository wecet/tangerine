#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test -f .signing-identity
identity="$(cat .signing-identity)"
[[ "$identity" =~ ^[A-Fa-f0-9]{40}$ ]]
app="$PWD/build/Tangerine.app"
updated="$PWD/build/SigningUpdateCheck.app"
requirement="identifier \"local.tangerine.mac\" and certificate leaf = H\"$identity\""
/usr/bin/ditto "$app" "$updated"
plutil -replace CFBundleVersion -string 2 "$updated/Contents/Info.plist"
codesign --force --sign "$identity" --requirements "=designated => $requirement" --timestamp=none "$updated"
codesign --verify --strict --test-requirement "=$requirement" "$app"
codesign --verify --strict --test-requirement "=$requirement" "$updated"
first_hash="$(codesign -dvvv "$app" 2>&1 | sed -n 's/^CDHash=//p')"
updated_hash="$(codesign -dvvv "$updated" 2>&1 | sed -n 's/^CDHash=//p')"
test "$first_hash" != "$updated_hash"
printf 'Changed bundle hash; original and update both satisfy the same certificate-pinned requirement.\n'
