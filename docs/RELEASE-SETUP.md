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

Released **1.0.0**, tag `v1.0.0`, source `374170eaa08125fdc401168521ef6fca4f6055bd`.
[Hosted release run](https://github.com/thesammykins/micline/actions/runs/35958476900) passed signing, app/DMG notarization, Gatekeeper, release publication and Pages deployment.
The downloaded public DMG matches its checksum and passes staple/Gatekeeper checks.
The public feed matches the release asset byte-for-byte; official Sparkle tools verify both the feed and archive signature.

Initial runs exposed OpenSSL PKCS#12 compatibility, missing DMG assessment context,
and Pages allowing only main. Those are corrected. The failed unpublished tag
was moved once; published assets have not been replaced. Both release-signing
and github-pages permit v* tags. No existing Apple credential was revoked.

Next acceptance exercise: install 1.0.0 and update to a genuine 1.0.1 patch through
Sparkle. The first release intentionally has no delta predecessor.

See [release procedure](RELEASING.md) for secret names and retry behavior.
