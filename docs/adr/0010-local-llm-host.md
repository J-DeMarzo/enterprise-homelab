# 0010. Local LLM host: CPU-only Ollama in Servers, reachable only from ops

- **Status:** Accepted
- **Date:** 2026-10-01

## Context
The agents on `ops` ([runbook](../runbooks/agent-clis.md)) all run on cloud models with free or student quotas. Grok's free allowance ran out after about five minutes of real work. A local model gives an agent that never hits a quota, keeps prompts inside the lab, and can later serve backend work (an app calling an LLM API) without a per-call bill.

Constraints:
- **No usable GPU.** Every node has a Ryzen PRO APU. The iGPUs are not passed through, and ROCm support for them is poor.
- **RAM is the limit.** darrow has the most free (about 18 GB of 31). Agent-sized models (30B MoE) need about 18 GB at Q4, so they don't fit next to Splunk.
- **`ops` is too small** (4 vCPU, 6 GiB) and is the highest-value host in the lab ([ADR 0008](0008-agent-workstation-in-management-bots-scoped.md)). It shouldn't also run a model server.

## Decision
1. **A dedicated LXC, 100 `llm`, on darrow** (6 cores, 12 GiB, 40 GB on `fast-local`), in **Servers** at 10.12.30.40 (`llm.demarzo.lab`). It's a workload, not an admin host, so it doesn't belong in Management.
2. **Ollama, installed CPU-only by hand.** The official installer sees the APU through `lspci` and adds the ROCm bundle, which the container can't use. The manual install is the same steps minus that branch ([runbook](../runbooks/deploy-llm.md)).
3. **One small model that makes real tool calls: `qwen3.5:4b`** (Q4_K_M, 3.4 GB, served with a 16K window). An agent is only as good as its model's structured tool calls, so each candidate was tested with a `tools` request before it was wired in:
   - `rnj-1:8b-instruct` (built for code and agentic work) crashes in Ollama 0.35.0's runner (`GGML_ASSERT(hparams.is_swa_any())`).
   - `qwen2.5-coder:7b` writes its tool calls as JSON text instead of `tool_calls`, so OpenCode never runs the tool.
   - `qwen3.5:4b` returns proper `tool_calls`, and is faster at about half the size.
4. **Ollama has no authentication, so the host firewall is the access control.** ufw allows 11434 from `ops` (10.12.5.10) only, and SSH from Management and the admin desktop. The gateway ACLs only see traffic between zones. Hosts in Servers talk to each other directly, so ufw is what keeps `fantasy`, `homepage`, and `bots` out.
5. **App access is a separate decision.** If an app on `fantasy` needs the model, open 11434 to that one host and record it here.

## Consequences
- ✅ An agent that works with no quota and no data leaving the lab: OpenCode's `ollama` provider on `ops`.
- ✅ Tested isolation: 11434 and 22 time out from `fantasy`, and the API answers from `ops`.
- ❌ **Slow.** About 10 tokens/s output and 60 tokens/s prompt processing. OpenCode's first turn sends about 9.9K tokens of system prompt and tools, close to three minutes of reading before the first word; later turns reuse the cached prefix. Two OpenCode settings made the difference: a lean `local` agent (a short system prompt and six tools, about 3.4K tokens instead of 11.1K) and `reasoningEffort: none` (thinking cost about 40 s per step). A file-reading task went from more than 3.5 minutes with no answer to 105 s cold and 44 s warm. The model stays loaded (`OLLAMA_KEEP_ALIVE=-1`) so the prompt cache survives idle time. Fine for batch and background backend work, sluggish for interactive agent loops.
- ❌ **A 4B model is a weak agent.** With an explicit instruction ("read X with the read tool") it uses tools correctly. Worded loosely, it sometimes answers without them or invents a path. It suits small, well-defined jobs; planning across files stays with the cloud agents.
- ❌ Shares darrow with Splunk. A long generation takes all 6 cores of the container. If Splunk searches slow down, lower `cores` or set CPU limits.
- ⚠️ Ollama reports the host's 31 GiB, not the container's 12 GiB, when it plans memory. `OLLAMA_MAX_LOADED_MODELS=1` keeps it to one model so that doesn't matter.
