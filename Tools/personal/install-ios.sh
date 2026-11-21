#!/usr/bin/env bash
# Builds the NOOPiOS scheme from the current checkout, signs it with the team in
# Config/BundleIdSecrets.xcconfig, and installs it on a connected iPhone.
#
# Usage: Tools/personal/install-ios.sh [device-udid]
# Without an argument, the first connected physical iPhone is used.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if ! grep -q '^DEVELOPMENT_TEAM' Config/BundleIdSecrets.xcconfig 2>/dev/null; then
  echo "Config/BundleIdSecrets.xcconfig has no DEVELOPMENT_TEAM; see docs/IOS.md." >&2
  exit 1
fi

device="${1:-}"
if [[ -z "$device" ]]; then
  json="$(mktemp)"
  xcrun devicectl list devices --json-output "$json" >/dev/null
  device="$(python3 -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical":
        print(hw["udid"]); break
' "$json")"
  rm -f "$json"
fi
if [[ -z "$device" ]]; then
  echo "No connected iPhone found. Connect it by cable or pass its UDID." >&2
  exit 1
fi

mkdir -p build
echo "==> xcodegen generate"
xcodegen generate --quiet

echo "==> Building NOOPiOS for $device (log: build/ios-install.log)"
if ! xcodebuild -project Strand.xcodeproj -scheme NOOPiOS -configuration Debug \
     -destination "id=$device" -derivedDataPath build/dd -allowProvisioningUpdates \
     build >build/ios-install.log 2>&1; then
  grep -E 'error:' build/ios-install.log | sort -u | head -20 >&2
  echo "Build failed; full log in build/ios-install.log" >&2
  exit 1
fi

app=build/dd/Build/Products/Debug-iphoneos/NOOP.app
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Info.plist")"
echo "==> Installing NOOP $version ($build) @ $(git rev-parse --short HEAD)"
xcrun devicectl device install app --device "$device" "$app" >/dev/null
echo "Installed."
