# Privacy and diagnostic reports

MicLine processes microphone audio locally and does not save microphone recordings.
It stores route choices, processing settings and Audio Unit state locally. Third-party
Audio Units execute their own code; MicLine does not certify their privacy behavior.

## Reviewed support report

Use **Settings → Advanced → Review Diagnostic Report** to inspect the exact JSON
before exporting it. The report excludes device names and UIDs, personal paths,
microphone audio, plugin state and free-text logs. It includes app/macOS versions,
selected device capabilities, public Audio Unit codes, processing settings and
bounded control events. Those fields can still identify a setup: it is not anonymous.
Clear Logs removes events, not the other report fields. Export is local; attaching
the file and submitting a GitHub issue are separate manual actions.

This allowlist and exact-preview guarantee apply only to **Review Diagnostic Report**,
not to the measurement or developer reports below.

## Measurement reports are not sanitized

**Check Loopback Signal Alignment → Save measurement report** writes a different
JSON format directly, without an exact-JSON preview. It includes full selected
device records (names, stable UIDs and device IDs), processing settings, effect
identifiers and any saved serialized Audio Unit state, alongside measurement
results. Plugin state is opaque and may contain private information. No microphone
samples are written, but this is not a sanitized support report. Keep it private
unless you have inspected and removed sensitive fields before sharing.

## Developer reports and inventories

`MicLineMeasure --devices` prints full device records, including names, numeric
IDs and stable UIDs. `MicLineMeasure --plugins` prints plugin inventories;
VST candidates include filesystem paths in their identifiers and locations.
These inventory outputs are not sanitized. `MicLineMeasure --offline` instead
prints synthetic DSP timing metrics, not device or plugin inventories.

The launch-only `--probe --report` path writes device/plugin inventories, names,
UIDs, selected identifiers, timestamps, status and free-text errors without the
support-report allowlist or preview. Loopback probe reports also embed measurement
records, including any saved Audio Unit state. These local debugging files may
contain identifying information or paths; do not attach them as sanitized support
reports. Inspect and redact them separately before sharing. They contain metrics,
not microphone samples.

## Network use

Website links open in your browser. The issue link includes app/build/macOS versions
and the selected effect count, not the diagnostic report. When a signed update feed
is configured, Sparkle checks and downloads use the network; automatic checks and
downloads default to off, and system profiling is disabled. Update controls remain
unavailable in builds without valid update configuration. Report vulnerabilities
through [SECURITY.md](../SECURITY.md), not a public issue.
