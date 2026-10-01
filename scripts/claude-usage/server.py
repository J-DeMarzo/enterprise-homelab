#!/usr/bin/env python3
"""Serve Claude plan usage as flat JSON for the Homepage customapi widget.

Reads the OAuth token from Claude Code's credentials file on each upstream
fetch (Claude Code keeps it refreshed), caches results for CACHE_SECS.
"""
import json
import os
import time
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CREDS = os.path.expanduser("~/.claude/.credentials.json")
URL = "https://api.anthropic.com/api/oauth/usage"
PORT = int(os.environ.get("PORT", "8787"))
CACHE_SECS = 60

_cache = {"at": 0, "data": None}


def until(iso):
    if not iso:
        return "—"
    secs = (datetime.fromisoformat(iso) - datetime.now(timezone.utc)).total_seconds()
    if secs <= 0:
        return "now"
    d, rem = divmod(int(secs), 86400)
    h, m = divmod(rem // 60, 60)
    return f"{d}d {h}h" if d else f"{h}h {m}m"


def fetch():
    token = json.load(open(CREDS))["claudeAiOauth"]["accessToken"]
    req = urllib.request.Request(URL, headers={
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "homepage-claude-usage",
    })
    raw = json.load(urllib.request.urlopen(req, timeout=10))
    five, week = raw.get("five_hour") or {}, raw.get("seven_day") or {}
    extra = raw.get("extra_usage") or {}
    return {
        "session_pct": five.get("utilization"),
        "session_reset": until(five.get("resets_at")),
        "weekly_pct": week.get("utilization"),
        "weekly_reset": until(week.get("resets_at")),
        "extra_used": extra.get("used_credits"),
        "ok": True,
    }


def get():
    now = time.time()
    if _cache["data"] is None or now - _cache["at"] > CACHE_SECS:
        try:
            _cache["data"] = fetch()
        except Exception as e:  # keep last good data, flag the error
            stale = dict(_cache["data"] or {})
            stale.update(ok=False, error=str(e))
            _cache["data"] = stale
        _cache["at"] = now
    return _cache["data"]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(get()).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
