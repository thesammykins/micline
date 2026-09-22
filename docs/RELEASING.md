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

GitHub's public-preview `xcode-27` hosted runner is ARM64 macOS 27 with Xcode 27
and the macOS 27 SDK. Both ordinary CI and the signed workflow assert that runtime
contract rather than using `macos-latest`, which currently means macOS 26. This
repository does not require or authorize a self-hosted runner.

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
./scripts/build.sh
```

Developer ID mode always enables the hardened runtime and a trusted timestamp.
The script never falls back to ad-hoc signing.

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

For notarization, place an App Store Connect API key in a temporary file and add
`--notarize` with these environment variables:

- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_KEY_PATH`

The package script submits with `notarytool --wait`, staples the accepted ticket,
and validates the staple. Delete the temporary key file after use.

## GitHub Actions configuration

Create a protected `release-signing` environment with required reviewers. Add
these environment secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | Base64-encoded Developer ID certificate and private key in PKCS#12 format |
| `MACOS_CERTIFICATE_PASSWORD` | PKCS#12 export password |
| `APPLE_DEVELOPER_ID_APPLICATION` | Exact `Developer ID Application: … (TEAMID)` identity |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `APPLE_NOTARY_KEY_P8_BASE64` | Base64-encoded App Store Connect private key |

Set repository variable `MICLINE_ENABLE_SIGNED_RELEASE` to `true` only after the
protected environment has been reviewed. Leaving it unset prevents the signing
job from starting. `scripts/build.sh` rejects a runner below macOS 27 or without
the macOS 27 SDK before the job loads credentials.

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
