#!/bin/bash
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo "Release publication runs only in GitHub Actions" >&2; exit 1; }
: "${GH_TOKEN:?GitHub Actions token is required}"
: "${GH_REPO:?}"
: "${RELEASE_TAG:?}"
: "${MICLINE_VERSION:?}"
: "${MICLINE_BUILD_NUMBER:?}"
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY GitHub secret is required}"
[[ "$GH_REPO" == "thesammykins/micline" && "$RELEASE_TAG" == "v$MICLINE_VERSION" ]] || exit 1
./scripts/release-version.py "$RELEASE_TAG" >/dev/null
notes="docs/releases/$MICLINE_VERSION.md"
[[ -s "$notes" ]] || { echo "Missing release notes: $notes" >&2; exit 1; }
sparkle="$PWD/.build/artifacts/sparkle/Sparkle/bin"
updates="$PWD/build/updates"
site="$PWD/build/site/updates"
mkdir -p "$updates" "$site"
printf '%s\n' '<!doctype html><title>MicLine</title><a href="https://github.com/thesammykins/micline/releases/latest">Download MicLine</a>' > build/site/index.html
# List succeeds even for the first release; network/auth failures must not be
# mistaken for an empty release history.
releases="$(gh api "repos/$GH_REPO/releases?per_page=100")"
existing="$(printf '%s' "$releases" | jq -r --arg tag "$RELEASE_TAG" '.[] | select(.tag_name == $tag) | .draft')"
if [[ "$existing" == false ]]; then
    # Recover the latest published feed, even when rerunning an older tag.
    latest="$(gh api "repos/$GH_REPO/releases/latest" --jq .tag_name)"
    ./scripts/release-version.py "$latest" >/dev/null
    gh release download "$latest" --pattern appcast.xml --dir "$site" --clobber
    printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sparkle/sign_update" --ed-key-file - --verify "$site/appcast.xml"
    exit 0
fi
previous="$(printf '%s' "$releases" | jq -r --arg tag "$RELEASE_TAG" '[.[] | select(.draft == false and .prerelease == false and .tag_name != $tag)][0].tag_name // empty')"
if [[ -n "$previous" ]]; then
    ./scripts/release-version.py "$previous" > "$RUNNER_TEMP/previous-version"
    previous_build="$(sed -n 's/^MICLINE_BUILD_NUMBER=//p' "$RUNNER_TEMP/previous-version")"
    [[ "$MICLINE_BUILD_NUMBER" -gt "$previous_build" ]] || { echo "Tag must be newer than the previous release" >&2; exit 1; }
    gh release download "$previous" --pattern 'MicLine-*.dmg' --pattern appcast.xml --dir "$updates"
    printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sparkle/sign_update" --ed-key-file - --verify "$updates/appcast.xml"
    cp "$updates/appcast.xml" "$RUNNER_TEMP/previous-appcast.xml"
    python3 scripts/prepare-release-feed.py --normalize "$updates/appcast.xml"
fi
cp "build/MicLine-$MICLINE_VERSION.dmg" "$updates/"
# Sparkle rewrites URLs for every archive present. Restore previous feed items
# below before signing the final feed, keeping their original release URLs.
if ! printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sparkle/generate_appcast" \
    --ed-key-file - --versions "$MICLINE_BUILD_NUMBER" --maximum-deltas 1 \
    --download-url-prefix "https://github.com/$GH_REPO/releases/download/$RELEASE_TAG/" \
    "$updates" > "$RUNNER_TEMP/micline-appcast-generation.log" 2>&1; then
    cat "$RUNNER_TEMP/micline-appcast-generation.log" >&2
    exit 1
fi
if grep -q 'does not match' "$RUNNER_TEMP/micline-appcast-generation.log"; then
    echo "Sparkle key does not match the application's public key" >&2; exit 1
fi
python3 scripts/prepare-release-feed.py "$updates/appcast.xml" "$updates" "$RELEASE_TAG" "$MICLINE_BUILD_NUMBER" "${previous:+$RUNNER_TEMP/previous-appcast.xml}" "$notes"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sparkle/sign_update" --ed-key-file - "$updates/appcast.xml"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sparkle/sign_update" --ed-key-file - --verify "$updates/appcast.xml"
cp "$updates/appcast.xml" "$site/appcast.xml"
assets=("build/MicLine-$MICLINE_VERSION.dmg" "build/MicLine-$MICLINE_VERSION.dmg.sha256" "$updates/appcast.xml")
shopt -s nullglob
for delta in "$updates"/*.delta; do assets+=("$delta"); done
if [[ -z "$existing" ]]; then
    gh release create "$RELEASE_TAG" --verify-tag --draft --title "MicLine $MICLINE_VERSION" --notes-file "$notes"
fi
gh release upload "$RELEASE_TAG" "${assets[@]}" --clobber
gh release edit "$RELEASE_TAG" --draft=false --latest
