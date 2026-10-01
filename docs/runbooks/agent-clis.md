# Runbook: Agent CLIs on ops (herdr)

**What:** the coding agents that run in herdr on `ops`, how each is installed and signed in, and what each account allows.
**When:** rebuilding `ops`, adding an agent, or an agent stops answering.

All of them install per user into `~/.local/bin` (no Node.js, no sudo). herdr's integration for each one adds hooks so herdr can see the agent's state (working, idle, blocked); OpenCode's also restores sessions. Check with `herdr integration status`.

| Agent | Install | Sign in | Account | herdr integration |
|---|---|---|---|---|
| Claude Code | `claude` installer | `claude` | Claude plan | `claude` |
| Codex | Release tarballs `codex-x86_64-unknown-linux-musl` **and** `codex-code-mode-host-…` from `openai/codex`, both into `~/.local/bin` | `codex login --device-auth` | ChatGPT Free | `codex` |
| Copilot CLI | `curl -fsSL https://gh.io/copilot-install \| bash` (checksummed) | `copilot login`, **in a real terminal** (see below) | Copilot Student | `copilot` |
| Grok Build | `curl -fsSL https://x.ai/cli/install.sh \| bash` (adds a PATH block to `.bashrc`, links `grok` and `agent` into `~/.local/bin`) | `grok login --device-auth` | Grok free | `grok` |
| OpenCode | `curl -fsSL https://opencode.ai/install \| bash -s -- --no-modify-path`, then link `~/.opencode/bin/opencode` into `~/.local/bin` | `opencode auth login` | Free OpenCode models, plus the local model on `llm` ([runbook](deploy-llm.md#6-opencode-on-ops)) | `opencode` (state + session restore) |

Credentials live in each tool's home directory with mode `600`: `~/.codex/auth.json`, `~/.copilot/config.json`, `~/.grok/auth.json`, `~/.local/share/opencode/auth.json`.

## Gotchas

- **Copilot needs `~/.copilot` before its herdr integration installs.** The directory normally appears on first launch: `mkdir -p ~/.copilot && herdr integration install copilot`.
- **Copilot can't save its token through `!` or a script.** ops has no system keychain, so `copilot login` asks whether to store the token in plain text. Without a TTY the question goes unanswered, the login "succeeds" and nothing is saved. Run it in a herdr pane and answer yes.
- **Codex device sign-in is off by default in ChatGPT.** The error says to enable it: ChatGPT → Settings → Security → device code sign-in. Then rerun `codex login --device-auth`.
- **Codex without `codex-code-mode-host`** warns that code mode is unavailable. It ships as a separate release asset next to `codex`.
- **Codex warns about bubblewrap** unless the `bubblewrap` package is installed. It falls back to its bundled copy, so this is cosmetic.
- **Copilot Student is Auto-only.** `copilot_internal/user` reports plan `individual`, SKU `free_educational_quota`, 200 premium credits a month, and no model is picker-enabled. So `copilot --model <id>` fails with "not available", and OpenCode's GitHub Copilot provider can't use the account (it needs a named model; the API answers "The requested model is not supported"). Default (Auto) mode works.

## Verify

```bash
herdr integration status | grep -v 'not installed'
codex login status
for c in "copilot -p" "grok -p" "opencode run"; do $c "Reply with exactly: ok"; done
codex exec --skip-git-repo-check "Reply with exactly: ok"
```

Last verified 2026-10-01: all five answer. Codex 0.160.0, Copilot 1.0.91, Grok 1.0.46, OpenCode 1.18.34.
