# Release setup status

Updated 24 September 2026. Routine releases require a version tag.

Completed:

- Repository made public after a redacted scan of all 62 existing commits.
- GitHub Pages configured for Actions; release-signing permits version tags without a reviewer gate.
- Dedicated Developer ID identity created, imported and verified locally. Exact certificate pins updated in scripts and workflow.
- Dedicated MicLine Notarization Team API key created with Developer access. Named `MicLine` asc profile authenticated successfully against Apple Notary. Team keys apply across the Apple team.
- Dedicated Sparkle signing key created in Keychain account `com.sammy.micline`.
- All four release secrets uploaded through `gh secret set`; secret names and public variables read back successfully. No private credentials entered source or logs.
- Tag workflow implements signing, app/DMG notarization, GitHub Releases, signed Sparkle full/delta updates and Pages deployment.

The Developer ID app passed strict signature checks, Apple notarization (no issues), stapling and Gatekeeper acceptance. Clear AU loaded in the hardened build.

Remaining validation: commit/push and run the first hosted version tag. No public app release or tag has been published yet. No existing Apple certificate or key was revoked.

See [release procedure](RELEASING.md) for secret names and retry behavior.
