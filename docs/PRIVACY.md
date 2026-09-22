# Privacy and diagnostic reports

MicLine processes microphone audio locally and does not save microphone recordings.
It stores route choices, processing settings and Audio Unit state locally. Third-party
Audio Units execute their own code; MicLine does not certify their privacy behavior.

Use **Settings → Advanced → Review Diagnostic Report** to inspect the exact JSON
before exporting it. The report excludes device names and UIDs, personal paths,
microphone audio, plugin state and free-text logs. It includes app/macOS versions,
selected device capabilities, public Audio Unit codes, processing settings and
bounded control events. Those fields can still identify a setup: it is not anonymous.
Clear Logs removes events, not the other report fields. Export is local; attaching
the file and submitting a GitHub issue are separate manual actions.

Website links open in your browser. The issue link includes app/build/macOS versions
and the selected effect count, not the diagnostic report. When a signed update feed
is configured, Sparkle checks and downloads use the network; automatic checks and
downloads default to off, and system profiling is disabled. Update controls remain
unavailable in builds without valid update configuration. Report vulnerabilities
through [SECURITY.md](../SECURITY.md), not a public issue.
