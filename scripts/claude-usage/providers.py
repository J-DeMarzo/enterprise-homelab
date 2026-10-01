"""Usage fetchers for the other AI tools logged in on ops.

Each fetch_* returns a flat dict for one Homepage customapi card. Tokens are
read from each CLI's own auth file on every call (the CLIs keep them fresh)
and never leave ops; only the derived numbers are pushed.
"""
import json
import os
import sqlite3
import time
import urllib.request
from datetime import datetime, timezone

from server import until

CODEX_AUTH = os.path.expanduser("~/.codex/auth.json")
COPILOT_CFG = os.path.expanduser("~/.copilot/config.json")
OPENCODE_DB = os.path.expanduser("~/.local/share/opencode/opencode.db")


def _get(url, headers):
    req = urllib.request.Request(url, headers=headers)
    return json.load(urllib.request.urlopen(req, timeout=10))


def _iso(ts):
    return datetime.fromtimestamp(ts, timezone.utc).isoformat() if ts else None


def _window(secs):
    if not secs:
        return None
    h = secs // 3600
    return f"{h}h" if h < 24 else f"{h // 24}d"


def fetch_codex():
    """ChatGPT plan limits, from the endpoint Codex's /status uses."""
    tok = json.load(open(CODEX_AUTH))["tokens"]
    raw = _get("https://chatgpt.com/backend-api/wham/usage", {
        "Authorization": f"Bearer {tok['access_token']}",
        "ChatGPT-Account-Id": tok["account_id"],
        "User-Agent": "homepage-ai-usage",
    })
    rl = raw.get("rate_limit") or {}
    pri, sec = rl.get("primary_window") or {}, rl.get("secondary_window") or {}
    return {
        "plan": raw.get("plan_type"),
        "used_pct": pri.get("used_percent"),
        "window": _window(pri.get("limit_window_seconds")),
        "reset": until(_iso(pri.get("reset_at"))),
        # Paid plans have a 5h primary + weekly secondary; free has one 30d window.
        "weekly_pct": sec.get("used_percent"),
        "weekly_reset": until(_iso(sec.get("reset_at"))) if sec else None,
        "limited": rl.get("limit_reached"),
        "ok": True,
    }


def fetch_copilot():
    """Copilot premium-request quota for the account Copilot CLI is logged in as."""
    lines = open(COPILOT_CFG).read().splitlines()
    cfg = json.loads("\n".join(l for l in lines if not l.lstrip().startswith("//")))
    user = cfg["lastLoggedInUser"]
    tok = cfg["authTokens"][f"{user['host']}:{user['login']}"]["token"]
    raw = _get("https://api.github.com/copilot_internal/user", {
        "Authorization": f"token {tok}",
        "Accept": "application/json",
        "User-Agent": "homepage-ai-usage",
    })
    prem = (raw.get("quota_snapshots") or {}).get("premium_interactions") or {}
    total, left = prem.get("entitlement"), prem.get("quota_remaining")
    return {
        "plan": (raw.get("access_type_sku") or raw.get("copilot_plan") or "").replace("_", " "),
        "premium_pct": None if prem.get("unlimited") else round(100 - prem.get("percent_remaining", 100), 1),
        "premium": f"{total - left:g} / {total}" if total else "unlimited",
        "reset": until(raw.get("quota_reset_date_utc")),
        "ok": True,
    }


def fetch_opencode(days=7):
    """OpenCode's own activity. Its quota is the Copilot one above, so show local totals."""
    since = int((time.time() - days * 86400) * 1000)
    db = sqlite3.connect(f"file:{OPENCODE_DB}?mode=ro", uri=True, timeout=5)
    try:
        sessions, messages, tokens, cost = db.execute(
            """SELECT count(DISTINCT session_id), count(*),
                      coalesce(sum(json_extract(data, '$.tokens.input')
                                 + json_extract(data, '$.tokens.output')
                                 + json_extract(data, '$.tokens.reasoning')), 0),
                      coalesce(sum(json_extract(data, '$.cost')), 0)
               FROM message
               WHERE json_extract(data, '$.role') = 'assistant' AND time_created >= ?""",
            (since,),
        ).fetchone()
    finally:
        db.close()
    return {
        "sessions": sessions,
        "messages": messages,
        "tokens": tokens,
        "cost": round(cost, 2),
        "ok": True,
    }


PROVIDERS = {"codex": fetch_codex, "copilot": fetch_copilot, "opencode": fetch_opencode}
