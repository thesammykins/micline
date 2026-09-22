#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MICLINE_APP_PATH:-$ROOT/build/MicLine.app}"
MINIMUM_MAJOR=27
DEFAULT_DEVELOPMENT_IDENTITY="Apple Development: Created via API (8K7KPLC29D)"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

check_environment() {
    local host_version host_major sdk_version sdk_major

    [[ "$(uname -s)" == "Darwin" ]] || die "MicLine must be built on macOS"
    for command_name in swift xcrun codesign plutil sw_vers; do
        require_command "$command_name"
    done

    host_version="$(sw_vers -productVersion)"
    host_major="${host_version%%.*}"
    [[ "$host_major" =~ ^[0-9]+$ ]] || die "could not parse macOS version: $host_version"
    ((host_major >= MINIMUM_MAJOR)) || die "macOS $MINIMUM_MAJOR or newer is required (found $host_version)"

    sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
    sdk_major="${sdk_version%%.*}"
    [[ "$sdk_major" =~ ^[0-9]+$ ]] || die "could not parse macOS SDK version: $sdk_version"
    ((sdk_major >= MINIMUM_MAJOR)) || die "macOS SDK $MINIMUM_MAJOR or newer is required (found $sdk_version)"
}

check_environment
if [[ "${1:-}" == "--check-environment" ]]; then
    printf 'macOS %s; SDK %s\n' "$(sw_vers -productVersion)" "$(xcrun --sdk macosx --show-sdk-version)"
    exit 0
fi
[[ $# -eq 0 ]] || die "usage: $0 [--check-environment]"

SIGNING_MODE="${MICLINE_SIGNING_MODE:-development}"
VERSION="${MICLINE_VERSION:-}"
BUILD_NUMBER="${MICLINE_BUILD_NUMBER:-}"

if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    die "MICLINE_VERSION must contain one to three dot-separated integers"
fi
if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    die "MICLINE_BUILD_NUMBER must be an integer"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
swift build --package-path "$ROOT" -c release --sdk "$SDK_PATH"
BIN_PATH="$(swift build --package-path "$ROOT" -c release --sdk "$SDK_PATH" --show-bin-path)"
[[ -x "$BIN_PATH/MicLine" ]] || die "release executable was not produced at $BIN_PATH/MicLine"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 0755 "$BIN_PATH/MicLine" "$APP/Contents/MacOS/MicLine"
install -m 0644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [[ -n "$VERSION" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    install -m 0644 "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
elif [[ "${MICLINE_REQUIRE_APP_ICON:-0}" == "1" ]]; then
    die "Resources/AppIcon.icns is required for this build"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
xattr -cr "$APP"

case "$SIGNING_MODE" in
    development)
        # Keep this stable identity as the local default so rebuilds preserve the
        # app's designated requirement and existing microphone consent.
        IDENTITY="${MICLINE_SIGNING_IDENTITY:-$DEFAULT_DEVELOPMENT_IDENTITY}"
        ;;
    developer-id)
        IDENTITY="${MICLINE_SIGNING_IDENTITY:-}"
        [[ -n "$IDENTITY" ]] || die "MICLINE_SIGNING_IDENTITY is required for developer-id signing"
        [[ "$IDENTITY" == "Developer ID Application:"* ]] || die "developer-id signing requires a Developer ID Application identity"
        ;;
    *)
        die "MICLINE_SIGNING_MODE must be development or developer-id"
        ;;
esac

if [[ "$SIGNING_MODE" == "developer-id" ]]; then
    codesign \
        --force \
        --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$ROOT/Resources/MicLine.entitlements" \
        "$APP"
else
    codesign \
        --force \
        --sign "$IDENTITY" \
        --entitlements "$ROOT/Resources/MicLine.entitlements" \
        "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

printf '%s\n' "$APP"
