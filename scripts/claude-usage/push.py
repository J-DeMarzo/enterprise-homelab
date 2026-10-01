#!/usr/bin/env python3
"""Push AI plan usage to the Homepage CT as a static JSON file.

Claude's fields stay at the top level; other tools (providers.py) are nested
under their own key, each falling back to its last good value on error.

Homepage (VLAN 30) can't open connections into mgmt (VLAN 5), so ops pushes
instead of being polled. Run every 60s by claude-usage-push.timer; the file is
served on the Homepage CT by claude-usage-web.service at 127.0.0.1:8787.
"""
import json
import os
import subprocess
from datetime import datetime, timezone

from providers import PROVIDERS
from server import fetch

LAST = os.path.expanduser("~/claude-usage/last.json")
# Dedicated key, forced on the Homepage side to only write usage.json
# (restrict,from="10.12.5.10",command="cat > ...usage.json.tmp && mv ...").
KEY = os.path.expanduser("~/.ssh/claude-usage-push")
DEST = "demarzo@10.12.30.100"

try:
    last = json.load(open(LAST))
except (OSError, ValueError):
    last = {}

now = datetime.now(timezone.utc).isoformat()

try:
    data = fetch()
    data["updated"] = now
except Exception as e:  # keep last good data, flag the error
    data = {k: v for k, v in last.items() if k not in PROVIDERS}
    data.update(ok=False, error=str(e))

for name, fn in PROVIDERS.items():
    try:
        data[name] = dict(fn(), updated=now)
    except Exception as e:
        data[name] = dict(last.get(name) or {}, ok=False, error=str(e))

with open(LAST, "w") as f:
    json.dump(data, f)

# -F none: skip ~/.ssh/config so the admin key is never offered for this job.
subprocess.run(
    ["ssh", "-F", "none", "-i", KEY, "-o", "IdentitiesOnly=yes",
     "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", DEST],
    input=json.dumps(data).encode(), check=True, timeout=30,
)
