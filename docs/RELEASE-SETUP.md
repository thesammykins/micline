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

Released **1.0.1**, source `01058ab`, through [GitHub Actions](https://github.com/thesammykins/micline/actions/runs/35961609085).
The installed 1.0.0 displayed the release notes, downloaded and verified the update,
and installed/relaunched as 1.0.1 (1000001). Strict signature and Gatekeeper checks
passed on `/Applications/MicLine.app`. Its five-second input-only check completed.

The published feed includes the signed 102,710-byte delta and 4,219,043-byte full
DMG. The hosted feed matches the release asset; the downloaded DMG checksum
matches. The installed update succeeded, but the retained runtime logs do not
identify whether it used the delta or full download.

Routine publication runs entirely in Actions using GitHub environment secrets.
The publisher refuses local execution and explicitly passes the Sparkle secret
through stdin, without a Keychain fallback. Local development and installed
update checks require no private release credentials.

See [release procedure](RELEASING.md) for secret names and retry behavior.
