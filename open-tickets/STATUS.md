# apfel — Ticket Review vs Golden Goal

**Golden Goal:** Usable powerful UNIX tool + OpenAI API-compatible server.
Bonus: debuggable GUI + working CLI chat. 100% on-device.

**Version:** 0.4.0 | **Tests:** 28/28 ✅ | **Build:** Clean ✅

---

## Golden Goal Scorecard

| Goal | Status | What's done | What's missing |
|------|--------|-------------|----------------|
| **UNIX tool** | ✅ 95% | Pipe, stdin, `--json`, `--quiet`, exit codes, `NO_COLOR`, `--stream`, `--temperature`, `--seed`, `--max-tokens`, `--permissive`, `--model-info` | Env vars (TICKET-009) |
| **OpenAI server** | ✅ 90% | `/v1/chat/completions` (stream+non-stream), `/v1/models`, `/health`, tools, `response_format`, CORS, 501 stubs, real token counts | `finish_reason:"length"` (TICKET-008), integration test proof (TICKET-005), streaming usage stats (TICKET-007) |
| **CLI chat** | ✅ 90% | Multi-turn, context rotation, typed errors, system prompt | Context summarization for quality (TICKET-006) |
| **Debug GUI** | ✅ 85% | Request/response JSON, curl commands, logs, TTS/STT, self-discussion | Token budget bar (TICKET-007) |
| **On-device** | ✅ 100% | SystemLanguageModel only. Zero network. Zero cloud. | — |
| **Honest** | ✅ 100% | 501 for unsupported, real token counts, typed errors | — |

---

## Open Tickets — Alignment Review

### TICKET-005: Integration Tests (P1) ← GOLDEN GOAL: OpenAI server
**VERDICT: KEEP — P1 — This is how we PROVE the OpenAI server goal works.**
Without these tests, "OpenAI-compatible" is a claim, not a fact. The Python
`openai` library is the reference client. If it works with apfel, we're done.
This is the single most important remaining ticket.

### ~~TICKET-006: Context Summarization~~ ← REMOVED
**VERDICT: KILLED.** Not part of OpenAI API. Context management is the CLIENT's
job, not the server's. The server should return `context_length_exceeded` if
messages are too long. CLI chat already has context rotation (drop oldest) which
is a UX feature, not API behavior. Summarization is over-engineering.

### TICKET-007: GUI Token Budget Display (P2) ← GOLDEN GOAL: Debug GUI
**VERDICT: KEEP — P2 — Core debug feature.**
The GUI is a debug inspector. Showing token budget consumption is exactly
what a debug inspector should do. This also requires adding streaming usage
stats to the server (which benefits the OpenAI server goal too — OpenAI's
`stream_options: {"include_usage": true}` pattern).

### TICKET-008: finish_reason "length" (P2) ← GOLDEN GOAL: OpenAI server
**VERDICT: KEEP — P2 — API correctness.**
Any serious OpenAI client checks `finish_reason` to decide whether to
continue generating. Returning "stop" when the response was actually
truncated breaks client logic. Small fix, big impact on compatibility.

### TICKET-009: Env Vars (P3) ← GOLDEN GOAL: UNIX tool
**VERDICT: KEEP — P3 — Unix convention.**
Real Unix tools read env vars. `APFEL_SYSTEM_PROMPT` is the most useful one
(set it in `.zshrc`, every apfel call uses it). Quick win.

---

## Tickets NOT Written But Should Be

### TICKET-010: `--system-file` flag (P3) ← GOLDEN GOAL: UNIX tool
Read system prompt from a file: `apfel --system-file prompt.txt "question"`.
For complex system prompts that don't fit on one command line. Unix convention.

### TICKET-011: Exit code semantics (P3) ← GOLDEN GOAL: UNIX tool
Currently: 0=success, 1=runtime error, 2=usage error.
Should add: 3=guardrail blocked, 4=context overflow, 5=model unavailable.
This lets shell scripts react to specific failures: `apfel "prompt" || case $? in ...`

---

## Priority Order for Implementation

1. **TICKET-005** (P1) — Prove OpenAI compatibility with real tests
2. **TICKET-008** (P2) — `finish_reason:"length"` — small fix, big correctness
3. **TICKET-007** (P2) — GUI token budget + streaming usage
4. **TICKET-009** (P3) — Env vars — quick win
5. **TICKET-010** (P3) — `--system-file` — quick win
6. **TICKET-011** (P3) — Exit code semantics — quick win
