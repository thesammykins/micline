# Releasing MicLine

MicLine's release automation produces a signed disk image as a private GitHub
Actions artifact. It does not publish a GitHub Release, push a tag, deploy, or
upload the app anywhere except Apple's notarization service when explicitly
requested.

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
names, or unsupported `.DS_Store` edits. The production background remains a
design gate until its native labels are independently accepted in the mounted
image.

For notarization, place an App Store Connect API key in a temporary file and add
`--notarize` with these environment variables:

- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_KEY_PATH`

The package script submits with `notarytool --wait`, staples the accepted ticket,
and validates the staple. Delete the temporary key file after use.

## GitHub Actions configuration

GitHub Actions supports [repository secrets, environment secrets, and organization
secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions).
It does not have personal-account-global Actions secrets; account-specific secrets
are a separate [Codespaces feature](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces).
For this private repository under a personal account, use repository secrets or a
protected `release-signing` environment. Organization secrets become available
only if the repository is owned by an organization.

The preferred configuration is a protected `release-signing` environment with
required reviewers, self-review prevention, and a `main` deployment-branch rule.
The workflow also checks the `main` ref before credential use. Private-repository
environment protection depends on the repository plan; if those controls are not
available, leave signed builds disabled until the user explicitly accepts broader
repository-secret scope. No release credentials are currently configured.

Add these environment secrets using secure credential tooling, never plaintext
chat or source:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID certificate and private key in PKCS#12 format |
| `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_DEVELOPER_ID_APPLICATION` | Exact `Developer ID Application: … (TEAMID)` identity |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect private key |

Add public environment variables `MICLINE_SPARKLE_FEED_URL` and
`MICLINE_SPARKLE_PUBLIC_ED_KEY`. Set repository variable
`MICLINE_ENABLE_SIGNED_RELEASE` to `true` only after the protected environment,
public update metadata, and distribution origin have been reviewed. Leaving it
unset makes the manually dispatched job fail explicitly before loading signing
credentials. The workflow validates the host, SDK, version, architecture, and
public Sparkle metadata before the certificate or notary credentials are loaded.

The prepared hosted workflow currently must decode the PKCS#12 certificate and,
when notarization is requested, the App Store Connect key into temporary files
because `security import` and `notarytool --key` consume paths. Current authority
prohibits certificate, password, and private-key files, including temporary ones.
Therefore repository variable `MICLINE_ALLOW_EPHEMERAL_CREDENTIAL_FILES` must
remain unset: the job fails before loading secrets. Set it only after Sammy
separately approves this exact ephemeral-file mechanism, or replace the mechanism
with a verified supported approach that does not create those files. Choosing a
secret scope or enabling `MICLINE_ENABLE_SIGNED_RELEASE` is not that approval.
The random ephemeral-keychain password remains only in the step process memory.

To build an artifact, manually dispatch **Build signed release artifact**, enter
the version and integer build number, and type `SIGN_ARTIFACT_ONLY`. Notarization
is independently opt-in; enabling it requires all three notary secrets. The job:

1. verifies macOS and SDK 27 before loading credentials;
2. imports the certificate into an ephemeral keychain;
3. builds the hardened, timestamped app and branded DMG;
4. optionally notarizes and staples the DMG;
5. uploads only the DMG and SHA-256 file with 14-day retention; and
6. removes the key, certificate, password file, and keychain in an unconditional
   cleanup step.

The workflow has only `contents: read` permission. Creating tags, GitHub Releases,
or public downloads remains a separate human-authorized action.

The signed workflow is intentionally untested until the required secrets and
protected environment exist. A local Developer ID identity being present does not
prove CI import, timestamping, or notarization. Notarization remains independently
opt-in and fails closed when any required credential is absent.

## Sparkle update boundary

MicLine pins the official Sparkle Swift package to 2.10.0. The updater is not
started unless the bundle contains both validated public configuration values.
Automatic checks, automatic downloads, automatic installation, and system
profiling default off. The user must explicitly opt in or request a manual check.
Sparkle requires a signed feed and verifies the update signature before extraction.
The complete upstream Sparkle license and bundled-code notices are copied into
the app as `Contents/Resources/Sparkle-LICENSE.txt`.

The app embeds `Sparkle.framework` under `Contents/Frameworks` and signs Sparkle's
nested XPC services, helper, updater app, and framework inside-out with the same
identity before signing the host app. The script does not use `codesign --deep`
for signing. MicLine currently loads AUv2 plugins out of process, so the hardened
app does **not** receive `com.apple.security.cs.disable-library-validation` or
broader JIT/executable-page entitlements. Revisit that tradeoff only if actual
in-process third-party code loading is introduced and verified to fail under the
hardened runtime.

A private GitHub repository is not a usable public Sparkle feed. Choose a public
HTTPS signed feed/artifact origin or a dedicated authenticated distribution
service. Never embed a GitHub token or other feed credential in the app. Follow
Sparkle's official [security guidance](https://sparkle-project.org/documentation/security-and-reliability/),
[programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/),
and [sandboxing/XPC guidance](https://sparkle-project.org/documentation/sandboxing/).

## Release threat model

- **Credential theft:** certificate, PKCS#12 password, App Store Connect key, and
  Sparkle private key can authorize malicious releases. Keep them out of PR jobs,
  logs, source, artifacts, and prompts. The hosted signing path is additionally
  blocked because its tools require temporary P12/P8 files; cleanup is not a
  substitute for approval to create them.
- **Untrusted workflow changes:** pull requests receive no signing secrets. The
  credentialed workflow is manual, main-only, explicitly enabled, confirmation
  gated, and artifact-only. Review workflow changes before enabling it.
- **Feed or transport compromise:** HTTPS protects transport; Sparkle's Ed25519
  signature protects artifact authenticity if its private key is kept separate.
  Missing or malformed feed/key metadata disables the updater.
- **Supply-chain substitution:** Sparkle is exact-version pinned in
  `Package.resolved`; the bundled framework is re-signed with the host identity
  and verified as nested code. Dependency upgrades require review.
- **Unintended publication:** CI retains a private artifact for 14 days and has
  `contents: read`. It does not create a release, tag, feed, or deployment.
- **Privacy drift:** update telemetry/system profiling is disabled. Any future
  authenticated update service needs a separate privacy and credential review.
