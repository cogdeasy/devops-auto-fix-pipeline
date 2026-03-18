# Build Log Triage Workflow

> Invoke with: `@workflow build-log-triage`

This workflow ingests raw build logs from Jenkins and produces summarised, triaged output that Cascade can reason over efficiently. It is a **read-only, diagnostic workflow** — it does not generate patches, create branches, or open PRs.

Use this workflow when you want to understand what is failing across multiple builds before deciding whether to run the full `auto-fix-mcp` or `auto-fix-paste` pipeline.

---

## When to Use

| Scenario | Use this workflow |
|----------|------------------|
| Many builds failing, need a quick overview | Yes |
| Single build failure, want an auto-fix | No — use `auto-fix-mcp` or `auto-fix-paste` |
| Want to triage before committing to a fix | Yes |
| Build logs are very large (multi-MB) | Yes — summarisation reduces them to actionable context |

---

## Pipeline Flow

```
INGEST → SUMMARISE → present triage to user
```

| Stage | File | Purpose |
|-------|------|---------|
| **01 — Ingest** | [`stages/01-ingest.md`](stages/01-ingest.md) | Pull raw build logs from Jenkins into the workspace |
| **02 — Summarise** | [`stages/02-summarise.md`](stages/02-summarise.md) | Hierarchical summarisation: per-log extraction → cross-log triage |

The orchestrator (`stages/00-orchestrator.md`) routes to this flow when `pipeline_type` is set to `build_log_triage`.

---

## Step 1: Ingest Raw Logs

**MCP mode** (jenkins-mcp available):
1. Identify the target Jenkins job(s) — user provides the job name or a pattern
2. Call `get_failed_builds` to list recent failures (configurable: last N builds, or all failures since a date)
3. For each failed build, call `get_build_log` to retrieve the full console output
4. Write each log to `logs/raw_build_{job}_{build_number}.md` in the workspace

**Paste mode**:
1. Prompt: "Paste your Jenkins build logs. You can paste multiple logs — separate them with `---`."
2. Parse and split the input into individual build logs
3. Write each to a separate file in `logs/`

At the end of this step, the workspace contains:
```
logs/
├── raw_build_api-service_1039.md
├── raw_build_api-service_1038.md
├── raw_build_auth-module_502.md
└── ...
```

---

## Step 2: Hierarchical Summarisation

### Level 1 — Per-log structured extraction

For each raw log file, Cascade applies the [`summarise-per-log-prompt.md`](../../workflows/prompts/summarise-per-log-prompt.md) prompt to produce a structured summary:

- Extract only **failed steps**, exit codes, and capped stderr (first 5 lines per failed step)
- Strip stdout for successful steps
- Classify the failure type using the standard taxonomy
- Output: `logs/summary_{job}_{build_number}.md` alongside each raw log

### Level 2 — Cross-log triage summary

Once all per-log summaries exist, Cascade applies the [`cross-log-triage-prompt.md`](../../workflows/prompts/cross-log-triage-prompt.md) prompt:

- Aggregate all summaries into a single document
- Group by failure type (dependency, compilation, test failure, etc.)
- Include a Table of Contents: *N builds failed out of M total*
- Rank failure groups by severity and frequency
- Output: `logs/cross_log_triage_summary.md`

### Final workspace state

```
logs/
├── cross_log_triage_summary.md         ← Level 2 (start here)
│
├── summary_api-service_1039.md         ← Level 1
├── raw_build_api-service_1039.md       ← raw log
│
├── summary_api-service_1038.md
├── raw_build_api-service_1038.md
│
├── summary_auth-module_502.md
├── raw_build_auth-module_502.md
└── ...
```

---

## Step 3: Present Triage

Present the `cross_log_triage_summary.md` to the user with:

1. **Overview**: "X of Y builds failed. Here is the triage summary."
2. **Table of Contents** from the summary document
3. **Recommended next steps**:
   - For each failure group, suggest whether to run `auto-fix-mcp`/`auto-fix-paste` or escalate
   - If a known issue was matched, link to the Confluence page
4. **Drill-down offer**: "I can read the full raw log for any specific build. Which one would you like to investigate?"

---

## Context Budget

The summarisation step uses adaptive sizing based on how many builds failed:

| Failures | Detail per log | Approach |
|----------|---------------|----------|
| 1–3 | Full stderr, generous context | Everything fits in context |
| 4–10 | 3 stderr lines per failure, moderate detail | Summaries in context, raw logs on disk |
| 10+ | One-liner per failure | Terse triage in context, drill-down via Read tool |

---

## Output

```
triage_summary: string     # path to cross_log_triage_summary.md
per_log_summaries: string[] # paths to individual summary files
raw_logs: string[]          # paths to raw log files
total_builds: number
failed_builds: number
failure_groups: object      # { compilation: N, dependency: M, ... }
```
