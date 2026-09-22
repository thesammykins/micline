#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"

# RFC 8032 test vector 1. This seed is public test data with no production
# security value. Every Sparkle invocation receives it over stdin so this test
# cannot read, create, import, or export a Keychain signing identity.
PUBLIC_TEST_SEED='nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A='
PUBLIC_TEST_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
WRONG_PUBLIC_TEST_SEED='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
DOWNLOAD_PREFIX='https://updates.example.invalid/micline/'

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for command_name in ditto plutil python3 stat xmllint; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done
[[ -x "$GENERATE_APPCAST" ]] || die "build MicLine first to materialize Sparkle's generate_appcast tool"
[[ -x "$SIGN_UPDATE" ]] || die "build MicLine first to materialize Sparkle's sign_update tool"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/micline-sparkle-fixture.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT INT TERM

APP="$WORK_DIR/MicLineFixture.app"
UPDATES="$WORK_DIR/updates"
ARCHIVE="$UPDATES/MicLineFixture-1.1.0.zip"
APPCAST="$UPDATES/appcast.xml"
mkdir -p "$APP/Contents/MacOS" "$UPDATES" "$WORK_DIR/home"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MicLineFixture</string>
    <key>CFBundleIdentifier</key>
    <string>com.sammy.micline.sparkle-fixture</string>
    <key>CFBundleName</key>
    <string>MicLine Sparkle Fixture</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>SUFeedURL</key>
    <string>${DOWNLOAD_PREFIX}appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>${PUBLIC_TEST_KEY}</string>
    <key>SURequireSignedFeed</key>
    <true/>
    <key>SUVerifyUpdateBeforeExtraction</key>
    <true/>
</dict>
</plist>
EOF
plutil -lint "$APP/Contents/Info.plist" >/dev/null

printf '#!/bin/sh\nexit 0\n' > "$APP/Contents/MacOS/MicLineFixture"
chmod 0755 "$APP/Contents/MacOS/MicLineFixture"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

generate_output="$(
    printf '%s\n' "$PUBLIC_TEST_SEED" | \
        CFFIXED_USER_HOME="$WORK_DIR/home" HOME="$WORK_DIR/home" \
        "$GENERATE_APPCAST" \
            --ed-key-file - \
            --download-url-prefix "$DOWNLOAD_PREFIX" \
            --maximum-deltas 0 \
            "$UPDATES"
)"
[[ "$generate_output" != *"does not match"* ]] || die "fixture app and signing key do not match"
[[ -f "$APPCAST" ]] || die "generate_appcast did not create appcast.xml"
xmllint --noout "$APPCAST"

verify_with_seed() {
    local seed="$1"
    shift
    printf '%s\n' "$seed" | "$SIGN_UPDATE" --ed-key-file - --verify "$@"
}

expect_rejection() {
    local description="$1" seed="$2"
    shift 2
    if verify_with_seed "$seed" "$@" >/dev/null 2>&1; then
        die "$description unexpectedly verified"
    fi
    printf 'rejected: %s\n' "$description"
}

archive_signature="$(xmllint --xpath \
    "string((//*[local-name()='enclosure'])[1]/@*[local-name()='edSignature'])" \
    "$APPCAST")"
declared_length="$(xmllint --xpath \
    "string((//*[local-name()='enclosure'])[1]/@length)" \
    "$APPCAST")"
download_url="$(xmllint --xpath \
    "string((//*[local-name()='enclosure'])[1]/@url)" \
    "$APPCAST")"
minimum_system_version="$(xmllint --xpath \
    "string((//*[local-name()='minimumSystemVersion'])[1])" \
    "$APPCAST")"

[[ -n "$archive_signature" ]] || die "appcast archive signature is missing"
[[ "$declared_length" == "$(stat -f %z "$ARCHIVE")" ]] || die "appcast archive length does not match"
[[ "$download_url" == "${DOWNLOAD_PREFIX}$(basename "$ARCHIVE")" ]] || die "appcast download URL is not the approved HTTPS fixture origin"
[[ "$minimum_system_version" == "27.0" ]] || die "appcast minimum system version is not 27.0"

verify_with_seed "$PUBLIC_TEST_SEED" "$APPCAST" >/dev/null
verify_with_seed "$PUBLIC_TEST_SEED" "$ARCHIVE" "$archive_signature" >/dev/null
printf 'verified: signed appcast and archive\n'

UNSIGNED_APPCAST="$WORK_DIR/unsigned-appcast.xml"
cat > "$UNSIGNED_APPCAST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Unsigned fixture</title></channel></rss>
EOF
expect_rejection "unsigned appcast" "$PUBLIC_TEST_SEED" "$UNSIGNED_APPCAST"

TAMPERED_APPCAST="$WORK_DIR/tampered-appcast.xml"
cp "$APPCAST" "$TAMPERED_APPCAST"
python3 - "$TAMPERED_APPCAST" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_text()
original = "<title>MicLineFixture</title>"
if original not in data:
    raise SystemExit("expected appcast title was not found")
path.write_text(data.replace(original, "<title>Tampered Fixture</title>", 1))
PY
expect_rejection "tampered signed appcast" "$PUBLIC_TEST_SEED" "$TAMPERED_APPCAST"

TAMPERED_ARCHIVE="$WORK_DIR/tampered-update.zip"
cp "$ARCHIVE" "$TAMPERED_ARCHIVE"
printf 'tampered' >> "$TAMPERED_ARCHIVE"
[[ "$(stat -f %z "$TAMPERED_ARCHIVE")" != "$declared_length" ]] || die "archive tamper did not change its declared length"
expect_rejection "tampered update archive" "$PUBLIC_TEST_SEED" "$TAMPERED_ARCHIVE" "$archive_signature"
expect_rejection "wrong update signing key" "$WRONG_PUBLIC_TEST_SEED" "$ARCHIVE" "$archive_signature"

printf 'Sparkle fixture passed: official tools accepted valid signed material and rejected all negative controls\n'
