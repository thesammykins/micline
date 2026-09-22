#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/MicLine.app"
OUTPUT="$ROOT/build/MicLine.dmg"
VOLUME_NAME="MicLine"
NOTARIZE=0
SIGN_DMG=0
VALIDATE_ONLY=0

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage: package-dmg.sh [options]
  --app PATH           App bundle to package (default: build/MicLine.app)
  --output PATH        Output DMG (default: build/MicLine.dmg)
  --volume-name NAME   Mounted volume name (default: MicLine)
  --sign-dmg           Sign the DMG using MICLINE_SIGNING_IDENTITY
  --notarize           Submit, wait, staple, and validate notarization
  --validate-only      Validate inputs and tooling without creating a DMG
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || die "--app requires a path"
            APP="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || die "--output requires a path"
            OUTPUT="$2"
            shift 2
            ;;
        --volume-name)
            [[ $# -ge 2 ]] || die "--volume-name requires a name"
            VOLUME_NAME="$2"
            shift 2
            ;;
        --sign-dmg)
            SIGN_DMG=1
            shift
            ;;
        --notarize)
            NOTARIZE=1
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[[ "$(uname -s)" == "Darwin" ]] || die "DMG packaging requires macOS"
[[ -d "$APP" ]] || die "app bundle not found: $APP"
[[ "$VOLUME_NAME" =~ ^[A-Za-z0-9._\ -]+$ ]] || die "volume name contains unsupported characters"

for command_name in codesign hdiutil open osascript swift xcrun; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done
codesign --verify --deep --strict --verbose=2 "$APP"
swiftc -parse "$ROOT/scripts/generate-dmg-background.swift"

if ((SIGN_DMG)); then
    [[ -n "${MICLINE_SIGNING_IDENTITY:-}" ]] || die "MICLINE_SIGNING_IDENTITY is required with --sign-dmg"
fi
if ((NOTARIZE)); then
    [[ -n "${APPLE_NOTARY_KEY_ID:-}" ]] || die "APPLE_NOTARY_KEY_ID is required with --notarize"
    [[ -n "${APPLE_NOTARY_ISSUER_ID:-}" ]] || die "APPLE_NOTARY_ISSUER_ID is required with --notarize"
    [[ -f "${APPLE_NOTARY_KEY_PATH:-}" ]] || die "APPLE_NOTARY_KEY_PATH must name a readable API key with --notarize"
fi
if ((VALIDATE_ONLY)); then
    printf 'validated app and DMG packaging prerequisites\n'
    exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/micline-dmg.XXXXXX")"
STAGE="$WORK_DIR/stage"
MOUNT_POINT="/Volumes/$VOLUME_NAME"
READ_WRITE_DMG="$WORK_DIR/MicLine-rw.dmg"
ATTACHED=0

cleanup() {
    if ((ATTACHED)); then
        hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT INT TERM

[[ ! -e "$MOUNT_POINT" ]] || die "a volume is already mounted at $MOUNT_POINT"
mkdir -p "$STAGE/.background" "$(dirname "$OUTPUT")"
ditto "$APP" "$STAGE/MicLine.app"
ln -s /Applications "$STAGE/Applications"
swift "$ROOT/scripts/generate-dmg-background.swift" "$STAGE/.background/background.png"

hdiutil create \
    -quiet \
    -fs HFS+ \
    -format UDRW \
    -srcfolder "$STAGE" \
    -volname "$VOLUME_NAME" \
    "$READ_WRITE_DMG"

hdiutil attach \
    -quiet \
    -noautoopen \
    "$READ_WRITE_DMG"
ATTACHED=1

# macOS 27 does not register a -noautoopen image with Finder until its mount
# path is opened. Register it explicitly before addressing the disk by label.
open "$MOUNT_POINT"
sleep 2

osascript - "$VOLUME_NAME" "$MOUNT_POINT/.background/background.png" <<'APPLESCRIPT'
on run argv
    set volumeName to item 1 of argv
    set backgroundFile to POSIX file (item 2 of argv) as alias
    tell application "Finder"
        tell disk volumeName
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set bounds to {120, 120, 780, 560}
            end tell
            tell icon view options of container window
                set arrangement to not arranged
                set icon size to 112
                set text size to 13
                set background picture to backgroundFile
            end tell
            set position of item "MicLine.app" to {170, 220}
            set position of item "Applications" to {490, 220}
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

sync
hdiutil detach "$MOUNT_POINT" -quiet
ATTACHED=0

rm -f "$OUTPUT"
hdiutil convert \
    -quiet \
    "$READ_WRITE_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$OUTPUT"
hdiutil verify "$OUTPUT" >/dev/null

if ((SIGN_DMG)); then
    codesign --force --timestamp --sign "$MICLINE_SIGNING_IDENTITY" "$OUTPUT"
    codesign --verify --verbose=2 "$OUTPUT"
fi

if ((NOTARIZE)); then
    xcrun notarytool submit "$OUTPUT" \
        --key "$APPLE_NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" \
        --issuer "$APPLE_NOTARY_ISSUER_ID" \
        --wait
    xcrun stapler staple "$OUTPUT"
    xcrun stapler validate "$OUTPUT"
fi

printf '%s\n' "$OUTPUT"
