#!/usr/bin/env bash
# Run an SPL search on the lab Splunk from ops and print CSV.
#   Usage:  splunk-search.sh '<spl>' [earliest] [latest]
#   e.g.    splunk-search.sh '| tstats count where index=linux by host' -24h now
# splunkd's management port (8089) is closed to the network by design, so the
# search runs on the splunk VM itself over SSH, against 127.0.0.1:8089. While on
# the Enterprise trial, credentials come from the root-only /root/splunk-admin.pass;
# they're fed to curl on stdin (-K -), so they never appear in a process list.
# On Splunk Free (no authentication) the file can be gone and this still works.
set -euo pipefail

SPL=${1:?usage: $0 '<spl>' [earliest] [latest]}
EARLIEST=${2:--24h}
LATEST=${3:-now}
# Searches that don't start with a generating command need the "search" keyword
[[ $SPL =~ ^[[:space:]]*\| ]] || SPL="search $SPL"

# Arguments are passed as base64 so quoting survives the SSH hop untouched
b64(){ printf '%s' "$1" | base64 -w0; }
ssh -o BatchMode=yes splunk "sudo bash -s -- $(b64 "$SPL") $(b64 "$EARLIEST") $(b64 "$LATEST")" <<'REMOTE'
set -euo pipefail
spl=$(base64 -d <<<"$1"); earliest=$(base64 -d <<<"$2"); latest=$(base64 -d <<<"$3")
{
  [[ -f /root/splunk-admin.pass ]] && printf 'user = "admin:%s"\n' "$(cat /root/splunk-admin.pass)"
  true
} | curl -sS -k -K - https://127.0.0.1:8089/services/search/v2/jobs/export \
      --data-urlencode "search=$spl" \
      --data-urlencode "earliest_time=$earliest" \
      --data-urlencode "latest_time=$latest" \
      -d output_mode=csv
REMOTE
