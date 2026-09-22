# Contributing to MicLine

Read [AGENTS.md](AGENTS.md) for architecture, audio invariants and build commands.
Keep changes focused on microphone processing. App routing, custom drivers and
VST hosting are not incidental extensions of this project.

For a bug, use the component-specific prompts in the issue form and follow
[SUPPORT.md](SUPPORT.md). State exact app/macOS/driver/effect versions, steps and
what changed the result. Do not upload recordings, secrets, presets or raw logs.

Before a pull request:

1. Add a regression that fails the plausible wrong behavior, then run `swift test`.
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
as a workaround. Follow the protected process in [RELEASING.md](docs/RELEASING.md).
