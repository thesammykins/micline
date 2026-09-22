# Releasing MicLine

MicLine's release automation prepares a signed disk image on the runner only.
Artifact upload is disabled: GitHub Actions artifacts are not private storage
once a repository becomes public, including artifacts retained before that change.
Retrieving signed output requires separately approved access-controlled storage
or explicit publication authorization. The workflow does not publish a GitHub
Release, push a tag, deploy, or upload the app anywhere except Apple's notarization
service when explicitly requested.

## Platform requirements

- A macOS 27 or newer host.
- Xcode 27 with the macOS 27 SDK selected by `xcrun`.
- `Resources/AppIcon.icns` for CI release builds.
- A Developer ID Application certificate for distribution outside the Mac App
  Store.

`scripts/build.sh` checks both the running macOS version and SDK version. Do not
substitute a macOS 26 runner: static validation may run there or on Linux, but an
app built there does not meet this package's macOS 27 contract.

GitHub's public-preview [`xcode-27` hosted runner](https://github.blog/changelog/2026-09-10-xcode-27-runner-image-now-runs-on-macos-27/)
is ARM64 macOS 27 with Xcode 27 and the macOS 27 SDK; its installed software is
listed in the [runner image manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md).
Both ordinary CI and the signed workflow assert that runtime contract rather than
using `macos-latest`, which currently means macOS 26. This repository does not
require or authorize a self-hosted runner.

The deployment target remains macOS 27. Apple lists macOS 27 as compatible only
with [Macs with Apple silicon](https://support.apple.com/en-us/127255). The build
script can cross-compile and merge an `x86_64` slice for feasibility testing, but
there is no supported Intel Mac that can run macOS 27. A universal Mach-O must
not be described as Intel hardware support. That would require an authorized
older-deployment-target/API compatibility effort and testing on Intel hardware.

## Local builds

The default keeps the existing development identity so repeated local rebuilds
retain their designated requirement and microphone permission:

```sh
./scripts/build.sh
```

To make a Developer ID build, select that mode and provide the exact identity
already present in the keychain:

```sh
MICLINE_SIGNING_MODE=developer-id \
MICLINE_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
MICLINE_VERSION=0.1.0 \
MICLINE_BUILD_NUMBER=1 \
MICLINE_REQUIRE_APP_ICON=1 \
MICLINE_SPARKLE_FEED_URL='https://updates.example.com/micline/appcast.xml' \
MICLINE_SPARKLE_PUBLIC_ED_KEY='BASE64_PUBLIC_KEY' \
./scripts/build.sh
```

Developer ID mode always enables the hardened runtime and a trusted timestamp.
The script never falls back to ad-hoc signing. It also requires the release
version, build number, and public Sparkle metadata:

- `MICLINE_SPARKLE_FEED_URL`: an HTTPS appcast URL without embedded credentials,
  query parameters, or a fragment.
- `MICLINE_SPARKLE_PUBLIC_ED_KEY`: the existing 32-byte Ed25519 public key,
  base64 encoded.

Neither value is secret. The corresponding private EdDSA key must remain in the
release operator's Keychain or managed signing service. This repository does not
generate, import, or export it.

The supported artifact is ARM64. To verify cross-build/lipo mechanics without
claiming Intel runtime support, an operator may explicitly use:

```sh
MICLINE_ARCHITECTURES='arm64 x86_64' ./scripts/build.sh
```

Swift emits an expected warning that `x86_64` is deprecated for the macOS 27
deployment target.

Package the signed app with the branded Finder layout and Applications alias:

```sh
MICLINE_SIGNING_IDENTITY='Developer ID Application: Example (TEAMID)' \
./scripts/package-dmg.sh \
  --app build/MicLine.app \
  --output build/MicLine-0.1.0.dmg \
  --volume-name 'MicLine 0.1.0' \
  --sign-dmg
```

The package script uses Finder to persist the disk image layout, so run it in a
macOS login session. `--validate-only` checks the signed app, required tools, and
the Swift background generator without mounting a disk image or opening Finder.
The mounted image must be checked at actual scale in both Finder appearances.
Finder controls icon-label color and exposes no supported label-color or
label-visibility setting. Do not depend on a global preference, invisible item
names, or unsupported `.DS_Store` edits. The background uses one continuous
neutral rail behind both genuine Finder labels; it must not replace them with
baked text or per-item label pills. Verify selected and unselected native labels
in the mounted image before release.

For local notarization, the package script accepts only an existing `notarytool`
Keychain profile. Creating or modifying that profile is a separate credential
operation and is not part of release packaging. Once an authorized profile
already exists, add `--notarize` and set its name without exposing credential
values:

```sh
APPLE_NOTARY_KEYCHAIN_PROFILE='EXISTING_PROFILE_NAME' \
./scripts/package-dmg.sh ... --sign-dmg --notarize
```

The script passes `--keychain-profile` to `notarytool --wait`, staples the
accepted ticket, and validates the staple. It rejects file-based notary
credentials. A profile's presence is not proof that Apple will accept a future
submission; validate it only during an explicitly authorized notarization.

## GitHub Actions configuration

GitHub Actions supports [repository secrets, environment secrets, and organization
secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions).
It does not have personal-account-global Actions secrets; account-specific secrets
are a separate [Codespaces feature](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces).
For this repository under a personal account, release credentials must use the
`release-signing` environment rather than repository secrets. Organization
secrets become available only if the repository is owned by an organization.

The `release-signing` environment is configured with a custom deployment-branch
policy that admits only the exact `main` branch. The workflow independently checks
the `main` ref before credential use. Required reviewers, self-review prevention,
and wait timers are not available for a private personal repository on GitHub
Free or Pro; GitHub makes those rules available on public repositories. Repository
visibility must not be changed to obtain them without separate authorization.
If the repository later becomes public, add an independent required reviewer and
prevent self-review before enabling signed builds. The repository currently has
only one collaborator, so that two-person gate cannot be configured usefully yet.
Do not fall back to broader repository secrets. No environment secrets or
variables are currently configured.

Repository privacy is not a release security boundary. Pull-request jobs must
remain credential-free, and signed jobs must remain manual, `main`-only,
environment-scoped, fail-closed, and artifact-only if the source becomes public.

Add these environment secrets using secure credential tooling, never plaintext
chat or source:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID certificate and private key in PKCS#12 format |
| `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_DEVELOPER_ID_APPLICATION` | Exact `Developer ID Application: … (TEAMID)` identity |

Add public environment variables `MICLINE_SPARKLE_FEED_URL` and
`MICLINE_SPARKLE_PUBLIC_ED_KEY`. Set repository variable
`MICLINE_ENABLE_SIGNED_RELEASE` to `true` only after the protected environment,
public update metadata, and distribution origin have been reviewed. Leaving it
unset makes the manually dispatched job fail explicitly before loading signing
credentials. The workflow validates the host, SDK, version, architecture, and
public Sparkle metadata before the certificate is loaded.

The prepared hosted workflow currently must decode the PKCS#12 certificate into
a temporary file because `security import` consumes a path. Current authority
prohibits certificate and private-key files, including temporary ones. Therefore
repository variable `MICLINE_ALLOW_EPHEMERAL_CREDENTIAL_FILES` must remain unset:
the job fails before loading secrets. Set it only after Sammy separately approves
this exact ephemeral-file mechanism, or replace the mechanism with a verified
supported approach that does not create the file. Choosing a secret scope or
enabling `MICLINE_ENABLE_SIGNED_RELEASE` is not that approval. The random
ephemeral-keychain password remains only in the step process memory.

Hosted notarization is also disabled. A fresh GitHub-hosted runner has no
pre-provisioned `notarytool` Keychain profile, and no approved fileless mechanism
has been established for provisioning one. Selecting the `notarize` input fails
before credential loading. Do not replace that stop with an App Store Connect key
file unless the file mechanism receives separate approval.

To build an artifact, manually dispatch **Build signed release artifact**, enter
the version and integer build number, leave notarization disabled, and type
`SIGN_ARTIFACT_ONLY`. The job:

1. verifies macOS and SDK 27 before loading credentials;
2. imports the certificate into an ephemeral keychain;
3. builds the hardened, timestamped app and branded DMG;
4. computes the DMG SHA-256 without uploading or retaining either file; and
5. removes the certificate file and ephemeral keychain in an unconditional
   cleanup step.

The workflow has only `contents: read` permission. Creating tags, GitHub Releases,
or public downloads remains a separate human-authorized action.

The signed workflow is intentionally untested until the required secrets and
protected environment exist and ephemeral certificate-file handling is approved.
A local Developer ID identity being present does not prove CI import or
timestamping. Hosted notarization remains disabled; local notarization requires
an existing authorized `notarytool` Keychain profile and explicit submission
authorization.

## Sparkle update boundary

MicLine pins the official Sparkle Swift package to 2.10.0. The updater is not
started unless the bundle contains both validated public configuration values.
Automatic checks, automatic downloads, automatic installation, and system
profiling default off. The user must explicitly opt in or request a manual check.
Sparkle requires a signed feed and verifies the update signature before extraction.
The complete upstream Sparkle license and bundled-code notices are copied into
the app as `Contents/Resources/Sparkle-LICENSE.txt`.

`scripts/verify-sparkle-fixture.sh` uses Sparkle's pinned `generate_appcast` and
`sign_update` binaries with [RFC 8032 test vector 1](https://www.rfc-editor.org/rfc/rfc8032#section-7.1),
which is public test data with no production security value. The disposable
fixture proves that Sparkle accepts its signed appcast and archive and rejects
an unsigned feed, tampered feed, tampered archive, and wrong signing key. Every
tool call receives the fixture seed over stdin, so the test never accesses a
Keychain item or creates a key file. This validates the release format and
negative controls, not a live updater download: an end-to-end `SPUUpdater` check
still requires a separately authorized HTTPS staging feed and prior-version app.

The app embeds `Sparkle.framework` under `Contents/Frameworks` and signs Sparkle's
nested XPC services, helper, updater app, and framework inside-out with the same
identity before signing the host app. The script does not use `codesign --deep`
for signing. MicLine requests `.loadOutOfProcess` when instantiating AUv2 plugins,
but AUv2 plugins may still execute in the host process; this is not a crash-
isolation guarantee. The hardened app therefore receives no preemptive
`com.apple.security.cs.disable-library-validation`, JIT, or executable-page
entitlement expansion. Validate supported third-party AUs in the final hardened
Developer ID build. If a real plugin fails because of library validation, stop
and review the narrowest entitlement change and its security tradeoff rather
than weakening the release globally.

A private GitHub repository is not a usable public Sparkle feed. Choose a public
HTTPS signed feed/artifact origin or a dedicated authenticated distribution
service. Never embed a GitHub token or other feed credential in the app. Follow
Sparkle's official [security guidance](https://sparkle-project.org/documentation/security-and-reliability/),
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
and [sandboxing/XPC guidance](https://sparkle-project.org/documentation/sandboxing/).

## Prepare and validate an appcast (blocked)

This is a local preparation procedure, not publication authorization. Do not run
the signing commands until an existing MicLine Sparkle Ed25519 key is authorized
for use from the operator's login Keychain. Do not run `generate_keys` without
`-p`, use `-x` or `-f`, pass `--ed-key-file`, or create, import, export, or rotate
a key as part of this procedure. Never place the private key in source, a release
directory, an environment variable, a prompt, or a log.

Prerequisites:

- a final hardened, Developer ID-signed, notarized, and stapled MicLine archive;
- its final `CFBundleVersion` and `CFBundleShortVersionString`;
- an approved public HTTPS feed and download origin without credentials, query,
  or fragment components;
- the name of the existing Keychain account holding MicLine's Sparkle key; and
- explicit authorization to use that Keychain item. Keychain access may display
  a system consent prompt and must fail closed if access is denied.

Materialize the pinned package artifact, then verify that the tools come from the
exact Sparkle 2.10.0 revision recorded in `Package.resolved`:

```sh
swift build --product MicLine -c release

SPARKLE_VERSION=2.10.0
SPARKLE_REVISION=eef1a539a373c1f1a320624b1130fc5de7b2e100
SPARKLE_BIN="$PWD/.build/artifacts/sparkle/Sparkle/bin"

test "$(git -C .build/checkouts/Sparkle describe --tags --exact-match HEAD)" = "$SPARKLE_VERSION"
test "$(git -C .build/checkouts/Sparkle rev-parse HEAD)" = "$SPARKLE_REVISION"
test -x "$SPARKLE_BIN/generate_keys"
test -x "$SPARKLE_BIN/generate_appcast"
test -x "$SPARKLE_BIN/sign_update"
```

Work in a disposable local staging directory outside the repository because
`generate_appcast` writes or updates `appcast.xml`, may create deltas, and may
move superseded files to `old_updates/`. Copy only the final archive and optional
matching release-notes file into it. Before signing, read only the existing
public key and require it to match the key embedded in the final app:

```sh
SPARKLE_ACCOUNT='EXISTING_MICLINE_KEYCHAIN_ACCOUNT'
STAGING_DIR='/absolute/path/to/private/micline-appcast-staging'
ARCHIVE="$STAGING_DIR/MicLine-0.1.0.dmg"
APP='build/MicLine.app'

KEYCHAIN_PUBLIC="$($SPARKLE_BIN/generate_keys --account "$SPARKLE_ACCOUNT" -p)"
BUNDLED_PUBLIC="$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist")"
test -n "$KEYCHAIN_PUBLIC"
test "$KEYCHAIN_PUBLIC" = "$BUNDLED_PUBLIC"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
xcrun stapler validate "$ARCHIVE"
```

After all prerequisites and credential use are authorized, generate a local
candidate using Keychain lookup. Omit `--ed-key-file`; the tool then uses the
named Keychain account. This command signs update archives and the required
signed feed because MicLine sets both `SUVerifyUpdateBeforeExtraction` and
`SURequireSignedFeed`:

```sh
DOWNLOAD_PREFIX='https://updates.example.com/micline/'
"$SPARKLE_BIN/generate_appcast" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  "$STAGING_DIR"
```

Validate the generated XML, its embedded feed signature, and the archive
signature and length before any upload. `sign_update --verify` performs
verification only; it still reads the corresponding key pair from Keychain.

```sh
APPCAST="$STAGING_DIR/appcast.xml"
xmllint --noout "$APPCAST"
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$APPCAST"

ARCHIVE_SIGNATURE="$(xmllint --xpath \
  "string((//*[local-name()='enclosure'])[1]/@*[local-name()='edSignature'])" \
  "$APPCAST")"
DECLARED_LENGTH="$(xmllint --xpath \
  "string((//*[local-name()='enclosure'])[1]/@length)" "$APPCAST")"
test -n "$ARCHIVE_SIGNATURE"
test "$DECLARED_LENGTH" = "$(stat -f %z "$ARCHIVE")"
"$SPARKLE_BIN/sign_update" \
  --account "$SPARKLE_ACCOUNT" \
  --verify "$ARCHIVE" \
  "$ARCHIVE_SIGNATURE"
```

Inspect the generated item before release: enclosure and release-note URLs must
use the approved public origins; version/build values must match the archive;
the minimum system version must remain 27; and hardware requirements must not
claim unsupported Intel runtime compatibility. Test an update from the prior
released version against an authorized staging origin before changing the live
feed. Uploading archives, appcast, deltas, or release notes—and modifying the
live feed—are separate external publication actions requiring explicit approval.
See Sparkle's official [publishing procedure](https://sparkle-project.org/documentation/publishing/)
for the 2.10 tool behavior used here.

## Release threat model

- **Credential theft:** certificate, PKCS#12 password, Notary Keychain profile,
  App Store Connect key, and
  Sparkle private key can authorize malicious releases. Keep them out of PR jobs,
  logs, source, artifacts, and prompts. The hosted signing path is additionally
  blocked because `security import` requires a temporary P12 file; cleanup is
  not a substitute for approval to create it. Hosted notarization remains blocked
  because no approved fileless profile-provisioning path exists.
- **Untrusted workflow changes:** pull requests receive no signing secrets. The
  credentialed workflow is manual, main-only, explicitly enabled, confirmation
  gated, and artifact-only. Review workflow changes before enabling it.
- **Feed or transport compromise:** HTTPS protects transport; Sparkle's Ed25519
  signature protects artifact authenticity if its private key is kept separate.
  Missing or malformed feed/key metadata disables the updater.
- **Supply-chain substitution:** Sparkle is exact-version pinned in
  `Package.resolved`; the bundled framework is re-signed with the host identity
  and verified as nested code. Dependency upgrades require review.
- **Unintended publication:** CI has no artifact upload step and has
  `contents: read`. It does not create a release, tag, feed, or deployment.
  Before changing repository visibility, confirm no retained artifacts exist,
  including those produced by older workflow revisions.
- **Privacy drift:** update telemetry/system profiling is disabled. Any future
  authenticated update service needs a separate privacy and credential review.
