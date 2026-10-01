#!/usr/bin/env bash
# Deploy splunk/apps/homelab_base from this repo to the indexer, from ops.
#   Usage:  splunk/server/deploy-app.sh [--no-restart]
# Copies the repo's files over the installed app (tar over SSH). Files that exist
# only on the server are kept: the baseline lookups written by scheduled searches
# (outputlookup) and anything under local/ (UI edits). Index-time settings
# (props/transforms) need the restart: Splunk is down for ~30 s, forwarders buffer
# and rsyslog keeps writing to disk. btool runs as splunk, because a root run of
# the splunk binary leaves root-owned files behind.
set -euo pipefail
cd "$(dirname "$0")/../apps"

RESTART=1; [[ ${1:-} == --no-restart ]] && RESTART=0
tar -C . -czf - homelab_base | ssh -o BatchMode=yes splunk "sudo bash -c '
  set -e
  tar -C /opt/splunk/etc/apps -xzf - --no-same-owner
  chown -R splunk:splunk /opt/splunk/etc/apps/homelab_base
  sudo -u splunk /opt/splunk/bin/splunk btool check --app=homelab_base 2>&1 | grep -v \"^$\" || true
  if [ $RESTART = 1 ]; then systemctl restart Splunkd; sleep 2; systemctl is-active Splunkd; fi
'"
