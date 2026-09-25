# Contributing to MicLine

Read the [MicLine development skill](.agents/skills/micline-development/SKILL.md)
for local setup, architecture, diagnostics and verification. [AGENTS.md](AGENTS.md)
records the audio invariants.
Keep changes focused on microphone processing. App routing, custom drivers and
VST hosting are not incidental extensions of this project.

## Linux orbs

Amp runs `.agents/setup` on fresh Linux x86_64 orbs and caches the installed
tools in project snapshots. Setup installs missing Debian prerequisites and
checksum-verified actionlint 1.7.7 and Gitleaks 8.30.1, matching CI. Warm runs
skip installed packages and matching tools. `.agents/resume` only checks tool
availability; no secrets, authentication, background services or profile edits
are needed. Keep the tool pins aligned with CI when updating them.

Available checks:

```sh
actionlint
shellcheck .agents/setup .agents/resume scripts/*.sh
python3 scripts/test-notarize.py
python3 scripts/test-release-tooling.py
git diff --check
```

For a full-history secret scan, unshallow the checkout first if needed, then run
`gitleaks detect --source . --config .github/gitleaks.toml --redact=100 --log-opts=--all --no-banner`.
Do not publish raw scan output.

Linux Swift cannot provide the Apple frameworks used by this package, so setup
does not install it or resolve Sparkle. App builds, Swift tests, Sparkle fixture
verification, signing, and UI/audio checks still require macOS 27 and Xcode 27.
Passing the Linux checks is not native runtime verification. Setup changes must
reach the Amp project's default branch before new orbs pick them up.

## License

MicLine is licensed under [Apache-2.0](LICENSE). By intentionally submitting a
contribution for inclusion, you provide it under the same license, as described
in section 5. Submit only work you have the right to contribute, and preserve
third-party notices. See [NOTICE](NOTICE) for the project copyright and exceptions.

For a bug, use the component-specific prompts in the issue form and follow
[SUPPORT.md](SUPPORT.md). State exact app/macOS/driver/effect versions, steps and
what changed the result. Do not upload recordings, secrets, presets or raw logs.

Before a pull request:

1. Reuse relevant checks; add a regression for a meaningful failure mode, then run `swift test`.
2. Build the app and run `git diff --check`; use actionlint and ShellCheck for workflows/scripts.
3. For UI changes, inspect every affected state at narrow/default sizes, including
   help/accessibility and active audio where safely testable. A design mockup is
   not runtime evidence. Record limits of performance instrumentation.
4. Preserve real-time safety and fail-closed route/channel validation. Never change
   shared audio defaults, sample rates or hardware volume for a test.
5. State what was verified, what was not, and how audio/visual behavior changed.

CI artifacts are not authorization to distribute. Apple signing, Sparkle update
signing and Git signatures serve different purposes. Never export or rotate keys,
publish releases, change App Store Connect records or weaken update verification
as a workaround. Follow the tag-based process in [RELEASING.md](docs/RELEASING.md).
