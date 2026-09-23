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

Development builds also require the explicit SHA-1 fingerprint of an approved
Apple Development identity. Select the same approved certificate for repeated
local rebuilds if you need to retain the app's designated requirement and
microphone permission. There is no implicit identity fallback:

```sh
MICLINE_SIGNING_CERTIFICATE_SHA1='40_HEX_CHARACTERS_FOR_APPROVED_DEVELOPMENT_CERTIFICATE' ./scripts/build.sh
```

To make a Developer ID build, select the dedicated MicLine certificate by its
exact SHA-1 fingerprint, not the common name shared by a developer's certificates:

```sh
MICLINE_SIGNING_MODE=developer-id \
MICLINE_SIGNING_CERTIFICATE_SHA1=86FC6A8884A697D9D1D55BBF5B4E0FAF159AAA3E \
MICLINE_VERSION=0.1.0 \
MICLINE_BUILD_NUMBER=1 \
MICLINE_REQUIRE_APP_ICON=1 \
MICLINE_SPARKLE_FEED_URL='https://thesammykins.github.io/micline/updates/appcast.xml' \
MICLINE_SPARKLE_PUBLIC_ED_KEY='FOJmOcZaeXTrpsrD+4J6ZG7vWQJyHs55aWrqALlRLcY=' \
./scripts/build.sh
```

Developer ID mode first verifies that the fingerprint uniquely identifies an
available Developer ID Application identity, then signs with that fingerprint.
Both the build and signed DMG scripts reject any fingerprint other than the
reviewed MicLine identity. Its provenance is an operator-established fact;
matching the common name or team alone cannot establish it. Never supply a
Trellis fingerprint.
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
MICLINE_SIGNING_CERTIFICATE_SHA1='40_HEX_CHARACTERS_FOR_MICLINE_CERTIFICATE' \
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
already exists, first submit the signed app as a ZIP, inspect the Apple log,
then staple the app before constructing the DMG. Use a private temporary
directory and preserve symlinks:

```sh
STAGING_DIR='PRIVATE_TEMP_DIRECTORY_OUTSIDE_REPOSITORY'
ditto -c -k --keepParent build/MicLine.app "$STAGING_DIR/MicLine.zip"
xcrun notarytool submit "$STAGING_DIR/MicLine.zip" \
  --keychain-profile micline-notary --wait --output-format json
xcrun notarytool log 'SUBMISSION_UUID_FROM_ACCEPTED_RESULT' \
  --keychain-profile micline-notary "$STAGING_DIR/app-notary-log.json"
xcrun stapler staple build/MicLine.app
xcrun stapler validate build/MicLine.app
```

Require `status: Accepted` and inspect `issues` in the log before stapling.
Do not run the later steps on a rejected, pending, or timed-out submission.
Then package the stapled app, notarize the signed DMG, and validate it:

```sh
APPLE_NOTARY_KEYCHAIN_PROFILE=micline-notary \
MICLINE_SIGNING_CERTIFICATE_SHA1=86FC6A8884A697D9D1D55BBF5B4E0FAF159AAA3E \
./scripts/package-dmg.sh --app build/MicLine.app \
  --output build/MicLine-0.1.0.dmg --volume-name 'MicLine 0.1.0' \
  --sign-dmg --notarize
xcrun stapler validate build/MicLine-0.1.0.dmg
spctl --assess --type open --verbose=4 build/MicLine-0.1.0.dmg
```

The script passes `--keychain-profile` to `notarytool --wait`, staples the
accepted ticket, and validates the staple. It requires `jq`, checks the JSON
status is `Accepted`, and writes the Apple log next to the output DMG as
`MicLine-0.1.0.dmg.notary.json` (local ignored evidence; do not upload it to an
Actions artifact). It rejects file-based notary
credentials. A profile's presence is not proof that Apple will accept a future
submission; validate it only during an explicitly authorized notarization.
Inspect the logged issues even on an accepted result. Mount the final DMG,
verify the nested app's signature, staple, Gatekeeper result, and Finder layout,
then copy to a disposable test install location and launch only when the
functional app owner has approved the test (microphone permissions may prompt).

## GitHub Actions configuration

GitHub Actions supports [repository secrets, environment secrets, and organization
secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions).
It does not have personal-account-global Actions secrets; account-specific secrets
are a separate [Codespaces feature](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces).
For this repository under a personal account, release credentials must use the
`release-signing` environment rather than repository secrets. Organization
secrets become available only if the repository is owned by an organization.

The `release-signing` environment currently has metadata for a custom exact-`main`
deployment-branch policy, but no required reviewers or self-review prevention.
The workflow independently checks the `main` ref before credential use. Do not
treat environment metadata as proof that the protection is enforced for this
private personal repository/plan. GitHub limits reviewer gates on private Free,
Pro, and Team repositories; public visibility might make them available, but
visibility changes require separate authorization. Before adding any certificate
or notary credential, obtain an enforceable independent reviewer gate and verify
its behavior with a credential-free deployment test. If that is impossible on the
current plan, stop; do not fall back to repository secrets or use the unreviewed
environment as a substitute. As of September 23, 2026, GitHub reports no
environment secrets or repository variables configured. No signed Actions run is
authorized. A private personal repository on Free/Pro cannot enforce required
reviewers; move to a plan/ownership arrangement that genuinely supports this
gate, or keep all signing and notarization local. Do not infer approval from a
manual dispatch confirmation or a writable enable variable. See GitHub's
[environment protection availability](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).

The dedicated MicLine Developer ID Application identity is installed in the
login Keychain. Its SHA-1 is `86FC6A8884A697D9D1D55BBF5B4E0FAF159AAA3E`,
SHA-256 is `11541614501843E409C0DCC355D6683202119BAB6649F5BEBDED7835AC0C5C4B`,
team is `7GF6N5U8ZH`, serial is `72949BB546E861B960B4A124A62AE1BF`, and
expiry is September 17, 2031. `security verify-cert -p codeSign` validated its
Developer ID → Apple Root chain, and `security find-identity` found its paired
signing identity. Another Developer ID identity has the same common name; never
select by name. Do not revoke, rotate, export, or reuse other products' identities.

The only visible `asc` profile is `RosterEase`; never use its default context
for MicLine. A new local `notarytool` Keychain profile named `micline-notary`
is needed. Prefer a new MicLine-labelled Apple app-specific password entered
in a secure local interactive terminal:

```sh
xcrun notarytool store-credentials micline-notary \
  --apple-id '<Apple ID>' --team-id 7GF6N5U8ZH
```

Omit `--password`
so the tool prompts securely and validates before saving. Apple explicitly says
individual ASC API keys cannot use notarytool. A dedicated Team API key is an
alternative for protected hosted automation, but even a role-restricted team key
can access every app on that team. Test the minimum permitted role with a new
key; do not assume `Developer` is sufficient, nor reuse the RosterEase key.
Never paste either credential into chat, source, logs, or command arguments. See
Apple's [API key limitations](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
and [notarytool workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Repository privacy is not a release security boundary. Pull-request jobs must
remain credential-free, and signed jobs must remain manual, `main`-only,
environment-scoped, fail-closed, and artifact-only if the source becomes public.

Add these environment secrets using secure credential tooling, never plaintext
chat or source:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID certificate and private key in PKCS#12 format |
| `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64 of a NEW MicLine-labelled Team API private key; hosted notarization only |

Set environment variable `MICLINE_SIGNING_CERTIFICATE_SHA1` to the nonsecret
40-character fingerprint of the dedicated MicLine certificate. A common name
is not a safe selector: multiple Developer ID certificates can share it. Verify
that the imported release Keychain contains exactly this identity before signing.

Add public environment variables `MICLINE_SPARKLE_FEED_URL` and
`MICLINE_SPARKLE_PUBLIC_ED_KEY`. Set repository variable
`MICLINE_ENABLE_SIGNED_RELEASE` to `true` only after the protected environment,
public update metadata, and distribution origin have been reviewed. Leaving it
unset makes the manually dispatched job fail explicitly before loading signing
credentials. The workflow validates the host, SDK, version, architecture, and
public Sparkle metadata before the certificate is loaded. The environment
variables `APPLE_NOTARY_KEY_ID` and `APPLE_NOTARY_ISSUER_ID` identify the
dedicated Team key; `MICLINE_ENABLE_HOSTED_NOTARIZATION=true` is a separate
environment gate. `MICLINE_ALLOW_EPHEMERAL_CREDENTIAL_FILES=true` allows the
temporary import path. All three enable flags remain unset for now. No Sparkle
private key is placed in Actions: appcast signing remains a local Keychain step
after the signed and stapled DMG has been retrieved through separately approved
access-controlled storage.

The prepared hosted workflow decodes a PKCS#12 identity into a temporary file
because `security import` consumes a path. Sammy authorized secure masked/file-
secret handling for the new MicLine identity, not reuse or export of an existing
product's identity. Keep the PKCS#12 payload and password out of source, logs,
prompts, and artifacts. The temporary file must be created only on the ephemeral
hosted runner after environment protection is independently verified, restricted
to the job, and deleted by unconditional cleanup. The random ephemeral-Keychain
password remains only in step memory. `MICLINE_ALLOW_EPHEMERAL_CREDENTIAL_FILES`
and `MICLINE_ENABLE_SIGNED_RELEASE` must remain unset until the dedicated certificate's
PKCS#12 import, independent approval gate, and credential handling have been verified; neither
variable by itself is authorization to sign or publish.

Hosted notarization remains disabled. A future protected runner provisions a
`micline-ci` profile in its temporary signing Keychain from a dedicated Team
key, validates it with Apple, deletes the temporary `.p8`, notarizes a ZIP of
the app, staples the app before packaging, then notarizes and staples the DMG.
It mounts the final DMG read-only and checks the embedded app's signature,
staple, Applications alias, and Gatekeeper assessment. This is not an
interactive install/launch test. Both submission logs remain local to the
ephemeral runner. This path has not been exercised; do not enable it until the
reviewer gate, dedicated key, certificate import, and local notarization path
have been verified. The temporary Team key is not the local app-specific-password
profile.

After the independent gate is enforceable and explicitly approved, dispatch
**Build signed release artifact** on `main`, enter the accepted exact 40-character
`source_sha`, version, integer build number, and `SIGN_ARTIFACT_ONLY`. The job
rejects a SHA that differs from `github.sha` at dispatch and verifies checkout
before credential access. Leave notarization disabled until its separate gate
has been validated. A DMG produced without notarization is a signing smoke test,
not a distributable release. The job:

1. verifies macOS and SDK 27 before loading credentials;
2. tests the exact checked-out source and pinned Sparkle fixture without credentials;
3. imports the certificate into an ephemeral keychain;
4. builds the hardened, timestamped app and branded DMG;
5. computes the DMG SHA-256 without uploading or retaining either file; and
6. removes the certificate file and ephemeral keychain in an unconditional
   cleanup step.

The workflow has only `contents: read` permission. Creating tags, GitHub Releases,
or public downloads remains a separate human-authorized action.

The signed workflow is intentionally untested until required secrets and an
enforceably protected environment exist. A local Developer ID identity being
present does not prove CI import or timestamping. No DMG is uploaded as an
Actions artifact, including on private repository runs: past artifacts can be
exposed after a later visibility change. A checksum printed in ephemeral CI is
not a retrievable release artifact. Arrange approved access-controlled storage
and verify the final bytes before treating hosted output as distributable.

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

A private GitHub repository is not a usable public Sparkle feed. Reserve
`https://thesammykins.github.io/micline/updates/appcast.xml` for the eventual
public project Pages site of this repository, and use public, versioned GitHub
Release asset URLs from the same repository for enclosure downloads only after
publication is separately approved. Release assets can be replaced at their URL;
Sparkle's EdDSA signature must still authenticate the downloaded bytes. A Pages
site is public even when its source repository is private, so Pages deployment
must remain disabled now. Do not use
`raw.githubusercontent.com` on a private branch as a feed or embed a GitHub
token in the app. Until the feed and downloads exist, the production updater
cannot deliver an update; its signed-feed and archive verification still fail
closed. An alternate public feed repository requires a deliberate feed URL
decision before building the first public artifact. Follow
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
  App Store Connect key, and Sparkle private key can authorize malicious releases.
  Keep them out of PR jobs, logs, source, artifacts, and chat. The dedicated
  identity exists locally, but the hosted signing path remains blocked by the
  missing independent reviewer gate and credential import validation. Hosted
  notarization additionally requires a separate dedicated Team API key and
  validation. Neither the RosterEase profile nor any Trellis material is a fallback.
- **Untrusted workflow changes:** pull requests receive no signing secrets. The
  credentialed workflow is manual, main-only, exact-SHA pinned, explicitly
  enabled, confirmation gated, and does not upload artifacts. These checks do
  not substitute for enforceable independent environment approval. Review
  workflow changes and verify the approval gate before enabling any secrets.
- **Residuals on runners:** PKCS#12 and Team API key are ephemeral files with
  restricted permissions; the temporary Keychain and file paths are removed on
  `always()`. Secret environment variables remain in step memory while used.
  Logs are not uploaded, and hosted runner disposal is still necessary. On a
  failed or cancelled job, verify no credential artifact was uploaded.
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
