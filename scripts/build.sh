#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MICLINE_APP_PATH:-$ROOT/build/MicLine.app}"
MINIMUM_MAJOR=27

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
    for command_name in swift xcrun codesign lipo otool plutil sw_vers; do
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

validate_update_metadata() {
    local feed_url="$1" public_key="$2" key_size

    [[ "$feed_url" == https://* ]] || die "MICLINE_SPARKLE_FEED_URL must use HTTPS"
    [[ ! "$feed_url" =~ [[:space:]] ]] || die "MICLINE_SPARKLE_FEED_URL must not contain whitespace"
    if ! swift -e '
        import Foundation
        let value = CommandLine.arguments[1]
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            exit(1)
        }
    ' "$feed_url"; then
        die "MICLINE_SPARKLE_FEED_URL must include a host and must not contain credentials, a query, or a fragment"
    fi

    [[ -n "$public_key" ]] || die "MICLINE_SPARKLE_PUBLIC_ED_KEY is required for developer-id builds"
    [[ ! "$public_key" =~ [[:space:]] ]] || die "MICLINE_SPARKLE_PUBLIC_ED_KEY must not contain whitespace"
    if ! key_size="$(printf '%s' "$public_key" | base64 -D 2>/dev/null | wc -c | tr -d '[:space:]')"; then
        die "MICLINE_SPARKLE_PUBLIC_ED_KEY must be valid base64"
    fi
    [[ "$key_size" == "32" ]] || die "MICLINE_SPARKLE_PUBLIC_ED_KEY must decode to 32 bytes"
}

verify_architectures() {
    local binary="$1" actual arch
    shift
    actual="$(lipo -archs "$binary")"
    for arch in "$@"; do
        [[ " $actual " == *" $arch "* ]] || die "$binary is missing requested $arch architecture (found: $actual)"
    done
}

sign_item() {
    local path="$1" preserve_entitlements="${2:-0}"
    local -a arguments=(--force --sign "$IDENTITY")

    if [[ "$SIGNING_MODE" == "developer-id" ]]; then
        arguments+=(--options runtime --timestamp)
    fi
    if [[ "$preserve_entitlements" == "1" ]]; then
        arguments+=(--preserve-metadata=entitlements)
    fi
    codesign "${arguments[@]}" "$path"
}

check_environment
COMMAND="${1:-build}"
case "$COMMAND" in
    build)
        [[ $# -eq 0 ]] || die "usage: $0 [--check-environment|--check-release-configuration]"
        ;;
    --check-environment)
        [[ $# -eq 1 ]] || die "usage: $0 [--check-environment|--check-release-configuration]"
        printf 'macOS %s; SDK %s\n' "$(sw_vers -productVersion)" "$(xcrun --sdk macosx --show-sdk-version)"
        exit 0
        ;;
    --check-release-configuration)
        [[ $# -eq 1 ]] || die "usage: $0 [--check-environment|--check-release-configuration]"
        ;;
    *)
        die "usage: $0 [--check-environment|--check-release-configuration]"
        ;;
esac

SIGNING_MODE="${MICLINE_SIGNING_MODE:-development}"
VERSION="${MICLINE_VERSION:-}"
BUILD_NUMBER="${MICLINE_BUILD_NUMBER:-}"
ARCHITECTURE_LIST="${MICLINE_ARCHITECTURES:-arm64}"
read -r -a ARCHITECTURES <<< "$ARCHITECTURE_LIST"
(( ${#ARCHITECTURES[@]} > 0 )) || die "MICLINE_ARCHITECTURES must name at least one architecture"

for arch in "${ARCHITECTURES[@]}"; do
    [[ "$arch" == "arm64" || "$arch" == "x86_64" ]] || die "unsupported architecture: $arch"
done
if (( ${#ARCHITECTURES[@]} == 2 )); then
    [[ "${ARCHITECTURES[0]}" != "${ARCHITECTURES[1]}" ]] || die "MICLINE_ARCHITECTURES contains a duplicate architecture"
elif (( ${#ARCHITECTURES[@]} > 2 )); then
    die "MICLINE_ARCHITECTURES may contain only arm64 and x86_64"
fi

if [[ -n "$VERSION" && ! "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
    die "MICLINE_VERSION must contain one to three dot-separated integers"
fi
if [[ -n "$BUILD_NUMBER" && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    die "MICLINE_BUILD_NUMBER must be an integer"
fi

if [[ "$COMMAND" == "--check-release-configuration" ]]; then
    [[ -n "$VERSION" ]] || die "MICLINE_VERSION is required for developer-id builds"
    [[ -n "$BUILD_NUMBER" ]] || die "MICLINE_BUILD_NUMBER is required for developer-id builds"
    [[ -n "${MICLINE_SPARKLE_FEED_URL:-}" ]] || die "MICLINE_SPARKLE_FEED_URL is required for developer-id builds"
    validate_update_metadata "$MICLINE_SPARKLE_FEED_URL" "${MICLINE_SPARKLE_PUBLIC_ED_KEY:-}"
    printf 'validated release version, build number, architectures, and public Sparkle metadata\n'
    exit 0
fi

case "$SIGNING_MODE" in
    development)
        EXPECTED_IDENTITY_TYPE='Apple Development:'
        ;;
    developer-id)
        EXPECTED_IDENTITY_TYPE='Developer ID Application:'
        [[ -n "$VERSION" ]] || die "MICLINE_VERSION is required for developer-id builds"
        [[ -n "$BUILD_NUMBER" ]] || die "MICLINE_BUILD_NUMBER is required for developer-id builds"
        [[ -n "${MICLINE_SPARKLE_FEED_URL:-}" ]] || die "MICLINE_SPARKLE_FEED_URL is required for developer-id builds"
        validate_update_metadata "$MICLINE_SPARKLE_FEED_URL" "${MICLINE_SPARKLE_PUBLIC_ED_KEY:-}"
        ;;
    *)
        die "MICLINE_SIGNING_MODE must be development or developer-id"
        ;;
esac
IDENTITY="${MICLINE_SIGNING_CERTIFICATE_SHA1:-}"
[[ "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || die "MICLINE_SIGNING_CERTIFICATE_SHA1 must be a 40-character certificate fingerprint"
IDENTITY="$(printf '%s' "$IDENTITY" | tr '[:lower:]' '[:upper:]')"
[[ "$(security find-identity -v -p codesigning | awk -v fingerprint="$IDENTITY" -v label="$EXPECTED_IDENTITY_TYPE" '
    toupper($2) == fingerprint && index($0, "\"" label) { count++ }
    END { print count + 0 }
')" == "1" ]] || die "the selected $EXPECTED_IDENTITY_TYPE certificate is not uniquely available"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
BIN_PATHS=()
for arch in "${ARCHITECTURES[@]}"; do
    scratch_path="$ROOT/.build/micline-release-$arch"
    swift build \
        --package-path "$ROOT" \
        --product MicLine \
        -c release \
        --sdk "$SDK_PATH" \
        --arch "$arch" \
        --scratch-path "$scratch_path"
    bin_path="$(swift build \
        --package-path "$ROOT" \
        -c release \
        --sdk "$SDK_PATH" \
        --arch "$arch" \
        --scratch-path "$scratch_path" \
        --show-bin-path)"
    [[ -x "$bin_path/MicLine" ]] || die "release executable was not produced at $bin_path/MicLine"
    [[ -d "$bin_path/Sparkle.framework" ]] || die "Sparkle.framework was not produced at $bin_path/Sparkle.framework"
    BIN_PATHS+=("$bin_path")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
if (( ${#BIN_PATHS[@]} == 1 )); then
    install -m 0755 "${BIN_PATHS[0]}/MicLine" "$APP/Contents/MacOS/MicLine"
else
    executables=()
    for bin_path in "${BIN_PATHS[@]}"; do
        executables+=("$bin_path/MicLine")
    done
    lipo -create "${executables[@]}" -output "$APP/Contents/MacOS/MicLine"
    chmod 0755 "$APP/Contents/MacOS/MicLine"
fi
ditto "${BIN_PATHS[0]}/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install -m 0644 "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
install -m 0644 "$ROOT/Resources/Sparkle-LICENSE.txt" "$APP/Contents/Resources/Sparkle-LICENSE.txt"

if [[ -n "$VERSION" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
fi
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
    plutil -insert SUFeedURL -string "$MICLINE_SPARKLE_FEED_URL" "$APP/Contents/Info.plist"
    plutil -insert SUPublicEDKey -string "$MICLINE_SPARKLE_PUBLIC_ED_KEY" "$APP/Contents/Info.plist"
fi

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    install -m 0644 "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconFile' "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$APP/Contents/Info.plist"
elif [[ "${MICLINE_REQUIRE_APP_ICON:-0}" == "1" ]]; then
    die "Resources/AppIcon.icns is required for this build"
fi

plutil -lint "$APP/Contents/Info.plist" >/dev/null
verify_architectures "$APP/Contents/MacOS/MicLine" "${ARCHITECTURES[@]}"
otool -l "$APP/Contents/MacOS/MicLine" | grep -F '@executable_path/../Frameworks' >/dev/null || \
    die "MicLine executable is missing the embedded-framework runtime search path"
xattr -cr "$APP"

SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for path in \
    "$SPARKLE/XPCServices/Installer.xpc" \
    "$SPARKLE/XPCServices/Downloader.xpc" \
    "$SPARKLE/Autoupdate" \
    "$SPARKLE/Updater.app" \
    "$APP/Contents/Frameworks/Sparkle.framework"; do
    [[ -e "$path" ]] || die "required Sparkle code was not embedded: $path"
done

# Sparkle's nested code must be signed inside-out with the host identity. Only
# Downloader.xpc preserves Sparkle's supplied sandbox/network entitlements.
sign_item "$SPARKLE/XPCServices/Installer.xpc"
sign_item "$SPARKLE/XPCServices/Downloader.xpc" 1
sign_item "$SPARKLE/Autoupdate"
sign_item "$SPARKLE/Updater.app"
sign_item "$APP/Contents/Frameworks/Sparkle.framework"

main_sign_arguments=(--force --sign "$IDENTITY" --entitlements "$ROOT/Resources/MicLine.entitlements")
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
    main_sign_arguments+=(--options runtime --timestamp)
fi
codesign "${main_sign_arguments[@]}" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
    codesign --display --verbose=4 "$APP" 2>&1 | grep -q 'flags=.*runtime' || \
        die "Developer ID app is not signed with the hardened runtime"
fi

printf '%s\n' "$APP"
