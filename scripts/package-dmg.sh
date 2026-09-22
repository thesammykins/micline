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
  --sign-dmg           Sign the DMG using MICLINE_SIGNING_CERTIFICATE_SHA1
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

for command_name in codesign diskutil hdiutil open osascript swift xcrun; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done
codesign --verify --deep --strict --verbose=2 "$APP"
swiftc -parse "$ROOT/scripts/generate-dmg-background.swift"

if ((SIGN_DMG)); then
    SIGNING_FINGERPRINT="${MICLINE_SIGNING_CERTIFICATE_SHA1:-}"
    [[ "$SIGNING_FINGERPRINT" =~ ^[[:xdigit:]]{40}$ ]] || \
        die "MICLINE_SIGNING_CERTIFICATE_SHA1 must be a 40-character certificate fingerprint with --sign-dmg"
    SIGNING_FINGERPRINT="$(printf '%s' "$SIGNING_FINGERPRINT" | tr '[:lower:]' '[:upper:]')"
    [[ "$(security find-identity -v -p codesigning | awk -v fingerprint="$SIGNING_FINGERPRINT" '
        toupper($2) == fingerprint && /"Developer ID Application:/ { count++ }
        END { print count + 0 }
    ')" == "1" ]] || die "the selected Developer ID Application certificate is not uniquely available"
fi
if ((NOTARIZE)); then
    ((SIGN_DMG)) || die "--notarize requires --sign-dmg"
    [[ -n "${APPLE_NOTARY_KEYCHAIN_PROFILE:-}" ]] || \
        die "APPLE_NOTARY_KEYCHAIN_PROFILE is required with --notarize"
    [[ -z "${APPLE_NOTARY_KEY_ID:-}" && -z "${APPLE_NOTARY_ISSUER_ID:-}" && -z "${APPLE_NOTARY_KEY_PATH:-}" ]] || \
        die "file-based notary credentials are unsupported; use an existing Keychain profile"
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
        diskutil eject "$MOUNT_POINT" >/dev/null 2>&1 || true
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

diskutil image attach \
    --mountPoint "$MOUNT_POINT" \
    "$READ_WRITE_DMG" >/dev/null
ATTACHED=1

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
                set label position to bottom
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
diskutil eject "$MOUNT_POINT" >/dev/null
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
    codesign --force --timestamp --sign "$SIGNING_FINGERPRINT" "$OUTPUT"
    codesign --verify --verbose=2 "$OUTPUT"
fi

if ((NOTARIZE)); then
    xcrun notarytool submit "$OUTPUT" \
        --keychain-profile "$APPLE_NOTARY_KEYCHAIN_PROFILE" \
        --wait
    xcrun stapler staple "$OUTPUT"
    xcrun stapler validate "$OUTPUT"
fi

printf '%s\n' "$OUTPUT"
