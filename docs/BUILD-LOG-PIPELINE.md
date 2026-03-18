# Build Log Pipeline — Ingestion & Summarisation

This document describes how the pipeline ingests raw Jenkins build logs into the Windsurf workspace and summarises them for AI consumption. The two-phase approach ensures Cascade always has actionable context regardless of how many builds failed or how large the logs are.

---

## Phase 1 — Raw File Pull

A script pulls the raw build log files from Jenkins and writes them into the Windsurf workspace under a `logs/` directory.

![Phase 1 — Raw File Pull](../assets/diagrams/build-log-phase1.svg)

### What happens

1. The orchestrator (Stage 00) triggers the pull script
2. The script authenticates to Jenkins via the `jenkins-mcp` server (MCP mode) or expects the user to paste logs (Paste mode)
3. Each build log is saved as a separate markdown file: `raw_build_one.md`, `raw_build_two.md`, etc.
4. Files land in the workspace so Cascade can read them on demand

### File structure after Phase 1

```
logs/
├── raw_build_one.md
├── raw_build_two.md
└── ...
```

---

## Phase 2 — Hierarchical Summarisation

Raw logs can be very large (multi-MB). Rather than stuffing them all into context, we apply a two-level summarisation:

![Phase 2 — Hierarchical Summarisation](../assets/diagrams/build-log-phase2.svg)

### Level 1 — Per-log structured extraction

Parse each build log into a structured representation:

- Extract only **failed steps**, exit codes, and capped stderr (first 5 lines per failed step)
- Strip stdout entirely for successful steps — they are noise
- This typically reduces a multi-MB log to a few hundred bytes

The output is a `summary_build.md` file alongside each raw log.

### Level 2 — Cross-log triage summary

Aggregate all per-log summaries into a single document:

- Group by failure type (dependency errors, compilation errors, test failures, timeouts)
- Include a **Table of Contents** at the top: *N builds failed out of M total*
- Provide one-line triage per failure for quick scanning

The output is `cross_log_triage_summary.md` at the root of the `logs/` directory.

### File structure after Phase 2

```
logs/
├── cross_log_triage_summary.md      ← Level 2 output
│
├── summary_build.md                 ← Level 1 output
├── raw_build_one.md                 ← raw log (Phase 1)
│
├── summary_build_2.md               ← Level 1 output
├── raw_build_two.md                 ← raw log (Phase 1)
└── ...
```

---

## Strategies for Handling Large Numbers of Build Logs

### Strategy 1: Hierarchical Summarisation (Primary — described above)

Two-level pipeline: per-log extraction → cross-log triage. This is the core approach.

### Strategy 2: Overflow File Pattern

- **In-context:** Send the model only the truncated summary (~10 KB)
- **On-disk:** Write the full log to an overflow file the agent can read on demand
- **Truncation notice:** Append a `<truncation_notice>` tag with the file path so the model knows where to look

The model sees a compact summary in its context window and can selectively drill into specific logs only when needed.

### Strategy 3: Structured Log Representation

For raw logs on disk, use JSONL format:

```jsonl
{"ts": "...", "stream": "stderr", "msg": "error: ..."}
{"ts": "...", "stream": "stdout", "msg": "[INFO] BUILD SUCCESS"}
```

Each line is independently parseable and can be filtered by stream without reading the whole file.

For the summary sent to the model, use structured markdown:

```markdown
## Build Failures (3 of 47 builds failed)

### project-alpha (exit 1)
  - Step `npm install`: ERESOLVE dependency conflict
  - Step `npm build`: 2 TypeScript errors
    > src/index.ts(42): TS2345: Argument of type 'string' not assignable...

### project-beta (exit 128)
  - Step `git clone`: fatal: early EOF
```

### Strategy 4: Smart Context Budget Allocation

Allocate a fixed token budget for the build log summary and scale per-log detail inversely with the number of failures:

| Failures | Detail level | Stderr lines | Approach |
|----------|-------------|-------------|----------|
| 1–3 | Generous | ~500 tokens each, full stderr | Full detail in context |
| 4–10 | Moderate | ~200 tokens each, 3 stderr lines | Summarised in context |
| 10+ | Terse | One-liner per failure | Overflow files for drill-down |

### Strategy 5: Lazy Loading via Tool Calls

Rather than stuffing all logs into context upfront:

1. Inject a **manifest** into context: list of all builds with pass/fail status + one-line reason
2. Provide a tool (or use the existing Read tool) for the model to pull specific logs on demand
3. The model reasons about which logs to investigate based on the manifest

---

## Recommended Combination

For Windsurf specifically, combine:

- **Hierarchical summarisation** (Strategy 1) as the default representation
- **Overflow files** (Strategy 2) for drill-down access
- **JSONL format** (Strategy 3) for the raw logs on disk
- **Adaptive budget** (Strategy 4) to scale with failure count

The key insight: the model almost never needs the full log. It needs to know *what failed and why*, with the ability to get raw details on demand.
