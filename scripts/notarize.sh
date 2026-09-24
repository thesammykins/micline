#!/bin/bash
set -euo pipefail

[[ $# == 2 ]] || { echo "usage: $0 ARCHIVE EVIDENCE_PREFIX" >&2; exit 1; }
archive="$1"
evidence="$2"
[[ -f "$archive" ]] || { echo "archive does not exist" >&2; exit 1; }
# Never fall back to a developer's default profile or mixed credential sources.
if [[ -z "${ASC_PROFILE:-}" ]]; then
    : "${ASC_KEY_ID:?dedicated MicLine key ID is required}"
    : "${ASC_ISSUER_ID:?dedicated MicLine team issuer is required}"
    : "${ASC_PRIVATE_KEY_B64:?dedicated MicLine API key is required}"
    export ASC_BYPASS_KEYCHAIN=true
fi
export ASC_STRICT_AUTH=true
umask 077

submit_status=0
asc notarization submit --file "$archive" --wait --poll-interval 30s --timeout 45m \
    --output json > "$evidence.submission.json" || submit_status=$?
id="$(jq -er '.data.id | select(type == "string" and length > 0)' "$evidence.submission.json")"
# Fetch logs even for a rejection. Keep signed log URLs out of Actions output.
asc notarization log --id "$id" --output json > "$evidence.log-url.json"
log_url="$(jq -er '.data.attributes.developerLogUrl | select(type == "string" and startswith("https://"))' "$evidence.log-url.json")"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    "$log_url" -o "$evidence.log.json"
rm -f "$evidence.log-url.json"
if [[ "$submit_status" != 0 ]]; then
    echo "Notarization submission failed; inspect the saved Apple log" >&2
    exit "$submit_status"
fi
jq -e '.data.attributes.status == "Accepted"' "$evidence.submission.json" >/dev/null
jq -e '.status == "Accepted" and ((.issues // []) | length == 0)' "$evidence.log.json" >/dev/null
printf 'Apple accepted submission %s with no logged issues\n' "$id"
