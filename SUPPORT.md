# Getting help

First check [setup and troubleshooting](README.md). Use headphones for monitoring;
do not reproduce feedback by increasing volume. BlackHole remains separately
installed. MicLine never changes system defaults or reloads CoreAudio for you.

Use the app's diagnostic report to review a local snapshot, export it if useful,
and open the GitHub issue form. **Nothing is submitted automatically.** The private
repository requires authorized GitHub access; export remains usable without it.
The browser form asks for reproduction steps, expected/actual behavior and the
affected component. Attaching an export is optional and manual.

## Exactly what diagnostics contain

- App/build and macOS numeric versions.
- Selected input/output channel counts, nominal sample rates, buffer sizes and
  whether each endpoint is virtual. Device names, UIDs and transient HAL IDs are omitted.
- Selected Audio Unit type/subtype/manufacturer codes and per-effect bypass state.
  These public component codes help identify the relevant effect without exporting
  its name, filesystem location, UUID or opaque state. Unselected plug-ins are omitted.
- Processing/monitoring state, gain and low-cut settings.
- Up to 64 in-memory control events from this launch: fixed event names, elapsed
  whole seconds and optional numeric error codes. No free-text error descriptions,
  Console collection or audio-callback logging. Clearing logs or quitting removes them.

The report uses an **allowlist**, not a best-effort regex over raw logs. Raw
`AudioDevice`, `PluginRecord` and `SessionSettings` are never serialized into it.
Untrusted version strings are accepted only in bounded numeric form. Microphone
samples, presets, tokens, home paths, user names and device identifiers have no
fields in this format. A failed third-party component can still place private
text in its own editor; review screenshots and anything you type manually.

Only app/build/macOS versions and selected-effect count enter the short GitHub
prefill URL. Logs and device details do not enter browser history through that
URL. Clicking the issue button contacts GitHub using your browser and its normal
cookies/network identity. Exporting the report itself makes no network request.

Do not attach raw crash/Console archives or AU state unless separately requested
through an agreed private channel and reviewed. Reports about a security issue
should go privately to the repository owner, not a broadly shared issue.

Form syntax and URL field IDs follow [GitHub's issue-form schema](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema).
