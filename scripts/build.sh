#!/bin/bash
set -euo pipefail
ROOT="$(dirname "$(dirname "$(realpath "$0")")")"
swift build --package-path "$ROOT" -c release --sdk "$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/build/MicLine.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/release/MicLine" "$APP/Contents/MacOS/MicLine"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# A stable Apple signing identity preserves the designated requirement across
# rebuilds. Do not silently fall back to ad-hoc signing and reset microphone trust.
IDENTITY="${MICLINE_SIGNING_IDENTITY:-Apple Development: Created via API (8K7KPLC29D)}"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/Resources/MicLine.entitlements" "$APP"
codesign --verify --strict "$APP"
echo "$APP"
