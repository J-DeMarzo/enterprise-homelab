# 0012. The Discord bot runs as an unprivileged user with no built-in tools

- **Status:** Accepted
- **Date:** 2026-11-05

## Context
[ADR 0008](0008-agent-workstation-in-management-bots-scoped.md) scoped the bot's Proxmox token and concluded that a compromised or prompt-injected bot could at worst power-cycle or snapshot guests. That was true of Proxmox, but an audit on 2026-11-05 found the rest of the bot's reach was much wider:

- It ran as `demarzo`, the admin login, with passwordless sudo. A settings deny-list was the only thing between the model and a root shell.
- Its claude.ai login brought the owner's Gmail, Drive, Calendar, Indeed and Docs connectors into the session. Using them took an approval, and approvals can be given from Discord.
- An SSH private key from the old agent workstation was still on the host, though no host authorized it.

The bot takes instructions from chat, so it should hold nothing beyond its job.

## Decision
1. **A dedicated user, `discord-bot`.** No sudo, password locked, no `authorized_keys`, home mode 750. It can't read `demarzo`'s files. The admin login holds no bot credentials.
2. **No built-in tools.** `--tools ''` removes shell, file and web tools from the model, instead of relying on a deny-list alone. The bot works through its Discord and Proxmox MCP tools.
3. **`NoNewPrivileges=yes`** on the unit, so setuid programs can't elevate anywhere in the process tree.
4. **claude.ai connectors off** with `disableClaudeAiConnectors`.
5. **Keep the claude.ai login,** renewed about every 4 weeks, with a DM from the [health check](../runbooks/discord-bot.md#health-check) before it expires.

Alternatives for the login:

- **`claude setup-token` (one year):** tested and rejected. Channels refuse it (`Channels are not currently available`).
- **Console API key:** channels are documented to accept it and it doesn't expire, but it bills per use, on top of a plan that's already paid for.
- **The [local LLM](0010-local-llm-host.md):** channels don't support it, so it would need a custom bot. At about 11 tokens/s on a 4B model that ADR 0010 found sometimes skips tools or invents details, it's a poor fit for a status bot. It also runs on the cluster the bot reports on.

## Consequences
- ✅ A prompt-injected bot has no shell, no file access, no sudo, and no route to the owner's mail or documents. *Evidence:* as `discord-bot`, `sudo` is refused and `demarzo`'s files give `Permission denied`; `NoNewPrivs: 1` on the bot's processes; connector logs stop; a Discord message still gets a reply and Proxmox tools still work.
- ✅ A compromised MCP server or plugin is contained to the bot's own user.
- ❌ The login still needs a browser about every 4 weeks.
- ❌ The login itself can still reach connectors if it's stolen from the bot's home. The setting keeps them out of the session, not out of the account.
- ⚠️ A `Read` deny rule stops `CLAUDE.md` from loading, so the bot would lose its safety rules. `--tools ''` removes the tool without that side effect.
