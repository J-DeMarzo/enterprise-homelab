# Runbook: Deploy the local LLM host (`llm`)

**Result:** LXC 100 `llm` (darrow, 10.12.30.40, `llm.demarzo.lab`) running Ollama CPU-only with `qwen3.5:4b`, reachable on 11434 from `ops` only, and wired into OpenCode on `ops`. Design: [ADR 0010](../adr/0010-local-llm-host.md). Last done: 2026-10-01 (Ollama 0.35.0).

## 1. Container (Proxmox API, from ops)
- Template `Templates:vztmpl/ubuntu-26.04-standard_26.04-1_amd64.tar.zst`, unprivileged, `nesting=1`, `onboot=1`.
- 6 cores, 12288 MiB RAM, 512 MiB swap, 40 GB on `fast-local`.
- The MCP's create call can't set a VLAN tag, DNS or tags, so set them before the first start:
  ```bash
  ssh darrow 'sudo pct set 100 --net0 name=eth0,bridge=vmbr0,firewall=1,gw=10.12.30.1,ip=10.12.30.40/24,tag=30,type=veth \
    --nameserver "10.12.5.53 10.12.5.54" --searchdomain demarzo.lab --tags "app;net-svc"'
  ```
- Start it through the API (see [Renumbering a guest](../architecture/compute.md#renumbering-a-guest) for why not `pct start` from a shell).

## 2. Admin access and DNS
```bash
# ~/.ssh/config on ops:  Host llm / HostName 10.12.30.40 / User demarzo
ssh darrow 'sudo pct exec 100 -- ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'   # compare, then pin
ssh-keyscan -t ed25519 10.12.30.40 >> ~/.ssh/known_hosts
ROOT_VIA="darrow pct exec 100 --" scripts/admin-access.sh llm
```
DNS: `llm` A 10.12.30.40 with PTR ([add-dns-record](add-dns-record.md)). Snapshot `base`.

## 3. Ollama, CPU-only
**Don't pipe `ollama.com/install.sh` into bash here.** It finds darrow's APU with `lspci -d 1002:` (the container sees the PCI device, not `/dev/dri` or `/dev/kfd`) and adds the ROCm bundle, which can't be used. Do the same steps by hand, as root on `llm`:
```bash
apt-get update && apt-get -y full-upgrade && apt-get -y install curl ca-certificates ufw zstd
install -o0 -g0 -m755 -d /usr/local/lib/ollama
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tar.zst | zstd -d | tar -xf - -C /usr/local
useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
usermod -a -G ollama demarzo
```
`/etc/systemd/system/ollama.service`: the installer's unit (`ExecStart=/usr/local/bin/ollama serve`, `User=ollama`, `Restart=always`), with `WantedBy=multi-user.target`. Settings go in a drop-in, `/etc/systemd/system/ollama.service.d/override.conf`:
```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_CONTEXT_LENGTH=16384"
Environment="OLLAMA_KEEP_ALIVE=-1"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_MAX_LOADED_MODELS=1"
```
`systemctl daemon-reload && systemctl enable --now ollama`. `KEEP_ALIVE=-1` keeps the model (3.6 GB) loaded for good: unloading after idle also throws away the prompt cache, so the next session would start cold. Upgrading later: stop the service, `rm -rf /usr/local/lib/ollama`, and repeat the `curl | tar` line.

## 4. Host firewall
Ollama has no authentication. ufw is the only thing between it and the rest of Servers.
```bash
ufw default deny incoming && ufw default allow outgoing
ufw allow from 10.12.5.0/24 to any port 22 proto tcp comment 'SSH from Management'
ufw allow from 10.12.10.10  to any port 22 proto tcp comment 'SSH from admin desktop'
ufw allow from 10.12.5.10   to any port 11434 proto tcp comment 'Ollama from ops'
ufw --force enable
```
ufw works in the unprivileged LXC. Check from another Servers host that both ports time out:
```bash
ssh fantasy 'timeout 5 bash -c "exec 3<>/dev/tcp/10.12.30.40/11434" && echo OPEN || echo BLOCKED'
```

## 5. Model
```bash
ollama pull qwen3.5:4b
```
Measured 2026-10-01 on 6 cores of a Ryzen 5 PRO 5650GE, through `/api/generate` with `think: false`:

| Model | Prompt | Output | Structured tool calls |
|---|---|---|---|
| `qwen3.5:4b` (3.4 GB) | ~60 t/s | ~10–11 t/s | ✅ |
| `qwen2.5-coder:7b` (5.9 GB loaded) | ~36 t/s | ~6.5–8 t/s | ❌ JSON in `content` |
| `rnj-1:8b-instruct-q4_K_M` | won't load in Ollama 0.35.0: `GGML_ASSERT(hparams.is_swa_any())` | | |

**Before wiring a model into an agent, check that it makes structured tool calls.** `ollama show <model>` listing `tools` isn't enough (qwen2.5-coder lists it). Send one request with a `tools` array to `/v1/chat/completions` and check that `choices[0].message.tool_calls` is set, not JSON text in `content`. Use `/api/generate` with `options.num_predict` for speed: its `prompt_eval_duration` and `eval_duration` are exact, and `ollama run --verbose` output is hard to parse over SSH.

## 6. OpenCode on ops
`~/.config/opencode/opencode.jsonc`:
```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  // Session titles are a second model request; on the CPU-only local model it
  // queues behind the main prompt and doubles the wait. Titles are cosmetic.
  "agent": {
    "title": { "disable": true },
    // Lean agent for the local model. The default build agent sends ~11K tokens
    // (5.5K system prompt + 10 tool schemas) before the first word: ~3.5 min of
    // prompt reading on CPU. This one sends ~3.3K.
    "local": {
      "mode": "primary",
      "description": "Small local model on llm (Ollama, CPU). Short, explicit tasks.",
      "model": "ollama/qwen3.5:4b",
      "prompt": "You are a concise coding assistant working in the user's project. Use the tools to read, search and edit files. Read a file before editing it. Use paths relative to the project root. Keep answers short.",
      "tools": { "task": false, "todowrite": false, "todoread": false, "webfetch": false, "skill": false },
      "permission": { "bash": "ask", "edit": "ask" }
    }
  },
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Ollama (llm)",
      "options": {
        "baseURL": "http://llm.demarzo.lab:11434/v1",
        // A cold agent prompt can take minutes to read on CPU before the first
        // byte; the 5 min defaults cut it off and retry from scratch.
        "headerTimeout": 900000,
        "chunkTimeout": 900000,
        "timeout": 1800000
      },
      "models": {
        // reasoning_effort none: thinking costs ~40 s per step at 10 tok/s.
        "qwen3.5:4b": { "name": "Qwen3.5 4B (local)", "tools": true, "limit": { "context": 16384, "output": 4096 }, "options": { "reasoningEffort": "none" } }
      }
    }
  }
}
```
Start it with **`opencode-local`** (`~/.local/bin`, runs `exec opencode --agent local "$@"`; `exec` keeps the process named `opencode` so herdr recognizes it), or from herdr: `herdr agent start <name> --kind opencode --pane <id> -- --agent local`.

**Why the lean agent.** A captured request from the default `build` agent was 21.8K chars of system prompt plus 21.1K chars of tool schemas (`bash` 5.3K, `task` 3.9K, `todowrite` 2.7K, …): about 11.1K tokens, or 3.5 minutes of prompt reading before the first word. An agent `prompt` replaces the default system prompt, and dropping `task`, `todowrite`, `webfetch` and `skill` leaves about 3.4K tokens. Capture method: point a throwaway provider at a local `http.server` that saves the POST body.

**Why `reasoningEffort: none`.** `qwen3.5` thinks before every answer by default: "What is 17*23?" took 39.7 s and 434 tokens with thinking, 0.6 s and 4 tokens without. An agent thinks at every step, so this matters more than anything else. (`think: false` in the OpenAI-compatible body is ignored; `reasoning_effort: "none"` works.)

Measured 2026-10-01 in this repo, "Read README.md with the read tool and reply with only its first heading line":

| | Default `build` agent, thinking on | `local` agent |
|---|---|---|
| Cold (Ollama just restarted) | canceled after 3.5 min, still reading the 11.1K-token prompt | **105 s** for the whole task |
| Warm | | **44 s**: 4 s for the first step, 35 s to read the README the tool returned |

Time now scales with what the model reads: about 55 tokens/s, so a 2K-token file adds about 35 s. Tool use with explicit instructions works; worded loosely, a 4B model sometimes skips the tools or invents paths.

> ⚠️ **Known issue:** twice, the first `opencode run` after a config change sat after `message=init` in `~/.local/share/opencode/log/opencode.log` and never contacted Ollama (no request in `journalctl -u ollama`). Stopping it and running again worked both times. If a run shows no Ollama request within a minute, restart it.

## 7. Splunk forwarder
```bash
ssh llm 'f=$(mktemp); cat >"$f"; sudo bash "$f" linux; rm -f "$f"' < splunk/forwarder/install-uf.sh
```
Check: `scripts/splunk-search.sh '| tstats count where index=linux host=llm'`.

## Verify
```bash
curl -s http://llm.demarzo.lab:11434/api/version
curl -s http://llm.demarzo.lab:11434/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.5:4b","messages":[{"role":"user","content":"Reply with exactly: ok"}]}'
ssh llm 'systemctl is-active ollama; sudo ufw status; ollama ps'
```

## Rollback
Snapshots: `base` (OS + admin access, before Ollama) and `ollama-ready`. To remove the host: stop and delete LXC 100, delete the DNS record in the Technitium console (the `ops` API user can't delete), drop `Host llm` from `~/.ssh/config` and its `known_hosts` line, and remove the `ollama` provider from OpenCode's config.
