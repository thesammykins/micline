#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
BINARY_DELTA="$SPARKLE_BIN/BinaryDelta"

# RFC 8032 test vector 1. This seed is public test data with no production
# security value. Every Sparkle invocation receives it over stdin so this test
# cannot read, create, import, or export a Keychain signing identity.
PUBLIC_TEST_SEED='nWGxne/9WmC6hEr0kuwsxERJxWl7MmkZcDusAxyuf2A='
PUBLIC_TEST_KEY='11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo='
WRONG_PUBLIC_TEST_SEED='AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
DOWNLOAD_PREFIX='https://github.com/thesammykins/micline/releases/download/v1.1.0/'

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

for command_name in ditto plutil python3 stat xmllint; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done
[[ -x "$GENERATE_APPCAST" ]] || die "build MicLine first to materialize Sparkle's generate_appcast tool"
[[ -x "$SIGN_UPDATE" ]] || die "build MicLine first to materialize Sparkle's sign_update tool"
[[ -x "$BINARY_DELTA" ]] || die "build MicLine first to materialize Sparkle's BinaryDelta tool"

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
# Stable incompressible content makes a small version change worth a delta.
mkdir -p "$APP/Contents/Resources" "$WORK_DIR/previous"
python3 - "$APP/Contents/Resources/payload" <<'PY'
from pathlib import Path
import random
import sys
Path(sys.argv[1]).write_bytes(random.Random(8032).randbytes(1024 * 1024))
PY
OLD_APP="$WORK_DIR/previous/MicLineFixture.app"
ditto "$APP" "$OLD_APP"
plutil -replace CFBundleVersion -string 1 "$OLD_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string 1.0.0 "$OLD_APP/Contents/Info.plist"
ditto -c -k --sequesterRsrc --keepParent "$OLD_APP" "$UPDATES/MicLineFixture-1.0.0.zip"
printf '%s\n' "$PUBLIC_TEST_SEED" | "$GENERATE_APPCAST" --ed-key-file - \
    --download-url-prefix 'https://github.com/thesammykins/micline/releases/download/v1.0.0/' \
    "$UPDATES" >/dev/null
python3 "$ROOT/scripts/prepare-release-feed.py" "$APPCAST" "$UPDATES" v1.0.0 1 ""
printf '%s\n' "$PUBLIC_TEST_SEED" | "$SIGN_UPDATE" --ed-key-file - "$APPCAST" >/dev/null
cp "$APPCAST" "$WORK_DIR/previous-appcast.xml"
python3 "$ROOT/scripts/prepare-release-feed.py" --normalize "$APPCAST"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"

generate_output="$(
    printf '%s\n' "$PUBLIC_TEST_SEED" | \
        CFFIXED_USER_HOME="$WORK_DIR/home" HOME="$WORK_DIR/home" \
        "$GENERATE_APPCAST" \
            --ed-key-file - \
            --download-url-prefix "$DOWNLOAD_PREFIX" \
            --maximum-deltas 1 \
            "$UPDATES"
)"
[[ "$generate_output" != *"does not match"* ]] || die "fixture app and signing key do not match"
[[ -f "$APPCAST" ]] || die "generate_appcast did not create appcast.xml"
python3 "$ROOT/scripts/prepare-release-feed.py" "$APPCAST" "$UPDATES" v1.1.0 2 "$WORK_DIR/previous-appcast.xml"
printf '%s\n' "$PUBLIC_TEST_SEED" | "$SIGN_UPDATE" --ed-key-file - "$APPCAST" >/dev/null
old_url="$(xmllint --xpath "string(//item[*[local-name()='version']='1']/enclosure/@url)" "$APPCAST")"
[[ "$old_url" == 'https://github.com/thesammykins/micline/releases/download/v1.0.0/MicLineFixture-1.0.0.zip' ]] || die "previous release URL was rewritten"
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

delta_url="$(xmllint --xpath "string(//*[local-name()='deltas']/*[local-name()='enclosure']/@url)" "$APPCAST")"
delta_signature="$(xmllint --xpath "string(//*[local-name()='deltas']/*[local-name()='enclosure']/@*[local-name()='edSignature'])" "$APPCAST")"
delta_from="$(xmllint --xpath "string(//*[local-name()='deltas']/*[local-name()='enclosure']/@*[local-name()='deltaFrom'])" "$APPCAST")"
delta_length="$(xmllint --xpath "string(//*[local-name()='deltas']/*[local-name()='enclosure']/@length)" "$APPCAST")"
[[ "$delta_from" == "1" && "$delta_url" == "${DOWNLOAD_PREFIX}"*.delta ]] || die "expected a delta from build 1"
DELTA="$UPDATES/$(basename "$delta_url")"
[[ -n "$delta_signature" && "$delta_length" == "$(stat -f %z "$DELTA")" ]] || die "delta signature or length is missing or incorrect"
verify_with_seed "$PUBLIC_TEST_SEED" "$DELTA" "$delta_signature" >/dev/null
"$BINARY_DELTA" apply "$OLD_APP" "$WORK_DIR/patched.app" "$DELTA"
diff -r "$APP" "$WORK_DIR/patched.app"
expect_rejection "wrong delta signing key" "$WRONG_PUBLIC_TEST_SEED" "$DELTA" "$delta_signature"
cp "$DELTA" "$WORK_DIR/tampered.delta"
printf 'tampered' >> "$WORK_DIR/tampered.delta"
expect_rejection "tampered delta" "$PUBLIC_TEST_SEED" "$WORK_DIR/tampered.delta" "$delta_signature"
printf 'verified: signed delta reconstructs the new app; full archive remains available\n'

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
