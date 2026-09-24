# Releasing MicLine

Push a stable version tag on a commit in `main`:

```sh
git tag v0.1.0
git push origin v0.1.0
```

`Release MicLine` builds on Apple's ARM64 macOS 27/Xcode 27 runner, tests,
signs with Developer ID, notarizes and staples the app and DMG, signs Sparkle's
feed and delta, publishes GitHub Release assets, and deploys the feed to Pages.
No manual dispatch, enable flags, second reviewer or local appcast-signing step
is required. This policy follows Samantha's explicit tag-to-release request.
Only tag a build intended for public distribution.

The release workflow must be committed and pushed before tagging. Stable tags
are `vMAJOR.MINOR.PATCH`, each component 0 through 999, without leading zeros.
Build numbers are `major * 1000000 + minor * 1000 + patch`; `v0.0.0` is rejected.
A release must be newer than the previous published release. The first release
has no delta because there is no previous public archive.

## One-time GitHub setup

The repository `thesammykins/micline` is public. Pages uses Actions deployment.
The `release-signing` environment permits `v*` tags; it has no reviewer gate.
Keep credentials in environment secrets, using `gh secret set --env
release-signing` with file/stdin input. Never put credentials in command
arguments, source, logs, screenshots or release artifacts.

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64 of MicLine's dedicated Developer ID identity |
| `MACOS_CERTIFICATE_PASSWORD` | Password for that PKCS#12 identity |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64 of the dedicated MicLine Team API key |
| `SPARKLE_PRIVATE_KEY` | Sparkle Ed25519 seed in Sparkle's exported base64 format |

| Environment variable | Value |
| --- | --- |
| `MICLINE_SIGNING_CERTIFICATE_SHA1` | Exact dedicated Developer ID fingerprint |
| `APPLE_NOTARY_KEY_ID` | Dedicated Team API key ID |
| `APPLE_NOTARY_ISSUER_ID` | Team API issuer ID |
| `MICLINE_SPARKLE_FEED_URL` | `https://thesammykins.github.io/micline/updates/appcast.xml` |
| `MICLINE_SPARKLE_PUBLIC_ED_KEY` | `8xebTYbUJ0zu3ucaaJOs6W7nxPIaVf8AU7vZDDMDvx8=` |

The new Sparkle key is retained locally under Keychain account
`com.sammy.micline` and provisioned in GitHub. No public release used the earlier
unavailable key, so the first release establishes this key as its trust root.

A dedicated Developer ID identity was created on 24 September 2026, paired
with its local private key and provisioned in GitHub secrets. Its SHA-1 is
`EE3326E165ACAB5017293BFA8438034EFAC32F21`, SHA-256
`F1D0126217EEE0D868BAB6A9B8E9BBBE2D5D9630B20412D76E8626C596CCBBC5`,
team `7GF6N5U8ZH`, serial `566B53B6BEDEDF568B84D43E8104A6A9`.
If replaced, update the explicit pins in the build script, packaging script,
workflow and GitHub variable together. Do not substitute another product's
identity merely because its common name matches.

See [current setup state](RELEASE-SETUP.md) for current validation status.

## What the workflow verifies

- The tagged commit belongs to `main`; checkout is pinned to the event commit.
- Actual macOS and Xcode are version 27 or newer. The supported app is ARM64;
  a cross-built Intel slice is not a claim of supported macOS 27 Intel hardware.
- Swift tests and Sparkle's signed full/delta fixture pass before credentials load.
- The temporary signing Keychain contains only the pinned Developer ID identity.
- Hardened runtime, trusted timestamp and nested Sparkle signatures are present.
- Apple returns `Accepted` and its log contains no issues. The app is stapled
  before packaging; the DMG and its mounted app pass staple/Gatekeeper checks.
- The signed appcast contains the correct full archive fallback and available
  delta. Previous feed items retain their original version-specific URLs.
- Signing secrets never reach pull-request jobs. Notary credentials are scoped
  to submission steps; temporary identity files and Keychain are cleaned up.

The Sparkle fixture tests two consecutive releases, prior URL preservation,
signed feed/full archive/delta verification, delta reconstruction and rejection
of tampering or a wrong key. It does not substitute for a real installed-app
update test. Third-party AUs must be checked in the final hardened build; AUv2
may execute in-process and no universal compatibility or crash isolation is promised.

## Failure and retry

A failed notarization never publishes. A release is assembled as a draft before
becoming public. Retrying a draft can replace its incomplete assets. Once public,
release bytes are immutable in this workflow: rerunning stages the existing
verified appcast for Pages instead of replacing the download. A failed Pages
job can be rerun independently. Release jobs are serialized so feeds do not race.

A failed or cancelled build does not revoke credentials. Inspect the Actions
failure and rerun the failed job after fixing its cause. Do not retag an already
published version; ship a new patch version.

## Local development and packaging

```sh
MICLINE_SIGNING_CERTIFICATE_SHA1='APPROVED_APPLE_DEVELOPMENT_SHA1' ./scripts/build.sh
codesign --verify --strict --verbose=2 build/MicLine.app
```

For local Developer ID builds, set `MICLINE_SIGNING_MODE=developer-id`, the
pinned identity, version/build number and public Sparkle metadata. Signing never
falls back to ad-hoc. Keep bundle identity `com.sammy.micline` stable.

`scripts/package-dmg.sh` creates the Finder layout and Applications alias. It
requires a macOS login session. Inspect native selected/unselected icon labels
at actual scale; the background must not replace Finder labels with baked text.
Local notarization can use the named `MicLine` asc profile with
`scripts/notarize.sh`. Do not switch the global asc default or reuse RosterEase
or Trellis credentials.

Sparkle 2.10.0 is pinned. Automatic checks/downloads/installations and profiling
remain off until the user opts in; manual Check for Updates uses the signed feed.
The private update-signing key is available only to the tag release job and
local Keychain. Its public key is embedded in the app. Retain this private key
across future releases so installed copies can verify their updates.
