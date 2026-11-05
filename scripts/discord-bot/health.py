#!/usr/bin/env python3
"""Health check for the Discord Proxmox bot, run by claude-discord-health.timer.

systemd can't tell when the bot is broken: Claude stays up inside tmux even if
its MCP servers died or its login lapsed. So this looks at what the bot needs:

- the Claude login is valid (a restart can't fix this one, so it only alerts)
- the Discord and Proxmox MCP servers are running under the Claude process
- the Discord server holds an open connection

Missing processes on two runs in a row trigger a restart, at most one per
RESTART_COOLDOWN. Problems are logged to the journal and sent as a Discord DM
to the allowlisted user, once per REALERT, with a second DM when they clear.
"""
import json
import os
import re
import subprocess
import time
import urllib.request
from datetime import datetime
from pathlib import Path

SERVICE = "claude-discord.service"
TMUX_SOCKET = "claude-discord"
DISCORD_DIR = Path.home() / ".claude/channels/discord"
STATE_FILE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    / "claude-discord-health.json"
)
FAILS_BEFORE_RESTART = 2
RESTART_COOLDOWN = 30 * 60
REALERT = 6 * 3600
LOGIN_WARN_DAYS = 3
API = "https://discord.com/api/v10"


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return None


def stdout(*cmd):
    result = run(*cmd)
    return result.stdout.strip() if result else ""


def discord_api(path, body, token):
    request = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
            # Discord's CDN rejects the default Python user agent.
            "User-Agent": "DiscordBot (https://github.com/J-DeMarzo/enterprise-homelab, 1)",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        return json.load(response)


def send_dm(text):
    """Returns True if the DM was delivered."""
    try:
        env = (DISCORD_DIR / ".env").read_text()
        token = re.search(r"^DISCORD_BOT_TOKEN=(.+)$", env, re.M).group(1).strip()
        user = json.loads((DISCORD_DIR / "access.json").read_text())["allowFrom"][0]
        channel = discord_api("/users/@me/channels", {"recipient_id": user}, token)
        discord_api(f"/channels/{channel['id']}/messages", {"content": text}, token)
        return True
    except Exception as error:  # A failed alert must not stop the check.
        print(f"could not send DM: {type(error).__name__}")
        return False


def login_problem():
    """Returns (key, message) if the login needs attention, otherwise None."""
    output = stdout("claude", "auth", "status", "--json")
    try:
        status = json.loads(output)
    except ValueError:
        return "login-unknown", "can't read the Claude login state (`claude auth status` failed)."
    if not status.get("loggedIn"):
        return "login-expired", (
            "Claude is logged out, so the bot can't answer. On ops, run: "
            "`ssh -t bots '~/.npm-global/bin/claude auth login'`, "
            "then `systemctl --user restart claude-discord` on bots."
        )
    expires = status.get("loginExpiresAt")
    if expires:
        left = datetime.fromisoformat(expires.replace("Z", "+00:00")).timestamp() - time.time()
        if left < LOGIN_WARN_DAYS * 86400:
            return "login-expiring", (
                f"the Claude login expires in {left / 3600:.0f} hours. On ops, run: "
                "`ssh -t bots '~/.npm-global/bin/claude auth login'`."
            )
    return None


def descendants(root):
    """Maps each process under root to its command line."""
    children, commands = {}, {}
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            # The command name in stat can contain spaces, so split after it.
            ppid = int((entry / "stat").read_text().rsplit(")", 1)[1].split()[1])
            command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except (OSError, IndexError, ValueError):
            continue  # The process exited while being read.
        children.setdefault(ppid, []).append(int(entry.name))
        commands[int(entry.name)] = command
    found, stack = {}, [root]
    while stack:
        for pid in children.get(stack.pop(), []):
            found[pid] = commands[pid]
            stack.append(pid)
    return found


def missing_parts():
    """Returns what's missing from the bot's process tree."""
    pane = stdout("tmux", "-L", TMUX_SOCKET, "list-panes", "-F", "#{pane_pid}").split("\n")[0]
    if not pane.isdigit():
        return ["the tmux session"]
    processes = descendants(int(pane))
    discord = [pid for pid, command in processes.items() if "server.ts" in command]
    missing = []
    if not discord:
        missing.append("the Discord MCP server")
    else:
        sockets = stdout("ss", "-tnpH", "state", "established", "( dport = :443 )")
        pids = {int(pid) for pid in re.findall(r"pid=(\d+)", sockets)}
        if not pids.intersection(discord):
            missing.append("the Discord connection")
    if not any("proxmox-mcp" in command for command in processes.values()):
        missing.append("the Proxmox MCP server")
    return missing


def main():
    now = time.time()
    try:
        state = json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        state = {}
    fails = state.get("fails", 0)
    last_restart = state.get("last_restart", 0)
    alerted = state.get("alerted", {})
    problems = {}

    service = stdout("systemctl", "--user", "is-active", SERVICE)
    if service == "inactive":
        print("service is stopped on purpose, nothing to check")
        return
    if service == "active":
        login = login_problem()
        if login:
            problems[login[0]] = login[1]
        missing = missing_parts()
        fails = fails + 1 if missing else 0
        if missing:
            print(f"missing {', '.join(missing)} ({fails} run(s) in a row)")
        logged_out = login and login[0] == "login-expired"
        if fails >= FAILS_BEFORE_RESTART and not logged_out:
            detail = f"{', '.join(missing)} not running."
            if now - last_restart >= RESTART_COOLDOWN:
                run("systemctl", "--user", "--no-block", "restart", SERVICE)
                last_restart = now
                detail += " Restarted the bot."
            else:
                detail += " The last restart didn't fix it."
            problems["processes"] = detail
    else:
        problems["service"] = f"{SERVICE} is {service or 'unknown'}."

    for key, message in problems.items():
        print(f"PROBLEM {key}: {message}")
        if now - alerted.get(key, 0) >= REALERT and send_dm(f"⚠️ Proxmox bot: {message}"):
            alerted[key] = now
    for key in [key for key in alerted if key not in problems]:
        print(f"RESOLVED {key}")
        if send_dm(f"✅ Proxmox bot: cleared `{key}`, the check is passing again."):
            del alerted[key]
    if not problems and not fails:
        print("healthy")

    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(
        {"fails": fails, "last_restart": last_restart, "alerted": alerted}
    ))


if __name__ == "__main__":
    main()
