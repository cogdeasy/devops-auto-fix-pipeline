# Stage 02-Summarise: Hierarchical Build Log Summarisation

> **Part of the `build-log-triage` workflow.** This stage takes the raw logs from Stage 01-Ingest and produces structured summaries at two levels.
>
> **Prompt templates**:
> - [`workflows/prompts/summarise-per-log-prompt.md`](../../../workflows/prompts/summarise-per-log-prompt.md) — Level 1 per-log extraction
> - [`workflows/prompts/cross-log-triage-prompt.md`](../../../workflows/prompts/cross-log-triage-prompt.md) — Level 2 cross-log triage

---

## Input

```
manifest_path: string          # path to logs/manifest.json (from Stage 01-Ingest)
raw_log_paths: string[]        # list of raw log file paths
context_budget: string         # "generous" | "moderate" | "terse" (auto-detected from failure count)
```

---

## Process

### 2.1 Determine Context Budget

Based on the number of failed builds from the manifest:

| Failed builds | Budget | Per-log detail |
|---------------|--------|----------------|
| 1–3 | `generous` | Full stderr, up to 500 tokens per log |
| 4–10 | `moderate` | 3 stderr lines per failed step, ~200 tokens per log |
| 10+ | `terse` | One-liner per failure, full detail in overflow files |

### 2.2 Level 1 — Per-Log Structured Extraction

For each raw log file in `raw_log_paths`:

1. Read the raw log file
2. Apply the **summarise-per-log** prompt template with:
   - `BUILD_LOG`: the full raw log content
   - `CONTEXT_BUDGET`: the determined budget level
   - `BUILD_METADATA`: job name, build number, timestamp from the metadata header
3. The AI produces a structured summary containing:
   - `failure_type`: one of the standard taxonomy categories
   - `exit_code`: the build exit code
   - `failed_steps`: list of step names that failed, with capped stderr
   - `root_error`: the first/primary error message
   - `cascading_errors`: count of downstream errors
   - `one_line_summary`: a single sentence describing the failure
4. Write the summary to `logs/summary_{{job}}_{{build_number}}.md`

**Format of each summary file:**

```markdown
# Build Summary: {{job_name}} #{{build_number}}

| Field | Value |
|-------|-------|
| Failure Type | {{failure_type}} |
| Exit Code | {{exit_code}} |
| Root Error | {{root_error}} |
| Cascading Errors | {{cascading_errors}} |
| Failed Steps | {{failed_steps_count}} |

## Failed Steps

### {{step_name}} (exit {{step_exit_code}})
```stderr (first 5 lines)
{{capped_stderr}}
```

## One-Line Summary

{{one_line_summary}}
```

### 2.3 Level 2 — Cross-Log Triage Summary

Once all per-log summaries are written:

1. Read all summary files
2. Read the manifest for build counts
3. Apply the **cross-log-triage** prompt template with:
   - `SUMMARIES`: all per-log summaries concatenated
   - `MANIFEST`: the manifest JSON
   - `TOTAL_BUILDS`: total builds examined
   - `FAILED_BUILDS`: number of failures
4. The AI produces a triage document containing:
   - Table of Contents with failure group counts
   - Failure groups clustered by type (dependency, compilation, test, etc.)
   - Within each group: list of affected builds with one-liner
   - Cross-cutting patterns (e.g. "3 builds fail on the same missing dependency")
   - Severity ranking of groups
   - Recommended next steps per group
5. Write to `logs/cross_log_triage_summary.md`

**Format of the triage summary:**

```markdown
# Cross-Log Triage Summary

> {{failed_builds}} of {{total_builds}} builds failed | Generated {{timestamp}}

## Table of Contents

| # | Failure Group | Count | Severity |
|---|--------------|-------|----------|
| 1 | Dependency errors | 3 | Critical |
| 2 | Compilation errors | 2 | Major |
| 3 | Test failures | 1 | Minor |

---

## 1. Dependency Errors (3 builds)

**Pattern**: ERESOLVE / Could not resolve artifact

| Build | Root Error | Suggested Action |
|-------|-----------|-----------------|
| api-service #1039 | ERESOLVE: peer dep conflict on react@18 | auto-fix |
| api-service #1038 | Missing artifact: commons-lang3:3.14 | auto-fix |
| auth-module #502 | Version conflict: jackson-databind | manual review |

**Recommended**: Run `auto-fix-mcp` targeting the dependency category.

---

## 2. Compilation Errors (2 builds)
...
```

---

## Output

```
triage_summary_path: string       # path to cross_log_triage_summary.md
per_log_summary_paths: string[]   # paths to individual summary files
failure_groups: object            # { dependency: 3, compilation: 2, ... }
context_budget: string            # the budget level used
```

---

## Workspace After This Stage

```
logs/
├── manifest.json                          ← from 01-ingest
├── cross_log_triage_summary.md            ← Level 2 (START HERE)
│
├── summary_api-service_1039.md            ← Level 1
├── raw_build_api-service_1039.md          ← raw
│
├── summary_api-service_1038.md
├── raw_build_api-service_1038.md
│
├── summary_auth-module_502.md
├── raw_build_auth-module_502.md
└── ...
```

---

## Audit Log Entry

```
Stage 02-summarise complete — produced {summary_count} per-log summaries
  and 1 cross-log triage document.
  Budget: {context_budget}. Failure groups: {failure_groups}.
```
