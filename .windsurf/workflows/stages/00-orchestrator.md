# Stage 0: Pipeline Orchestrator

The orchestrator is the entry point for the AI Auto-Fix Pipeline. It determines the operating mode and pipeline type, initialises pipeline state, and routes to the appropriate stage sequence.

There are two pipeline types:

| Type | Invoked via | Stages | Purpose |
|------|-------------|--------|---------|
| **`auto_fix`** | `auto-fix-mcp` / `auto-fix-paste` | 01-detect → 02-analyse → 03-patch → 04-validate → 05-pr-create | Full fix pipeline: detect, fix, validate, PR |
| **`build_log_triage`** | `build-log-triage` | 01-ingest → 02-summarise | Read-only: ingest logs, produce triage summary |

---

## Pipeline Type Detection

Before mode detection, determine which pipeline is being requested:

| Trigger | Pipeline Type |
|---------|--------------|
| User invokes `@workflow auto-fix-mcp` or `@workflow auto-fix-paste` | `auto_fix` |
| User invokes `@workflow build-log-triage` | `build_log_triage` |
| User asks to "triage", "summarise", or "ingest" build logs | `build_log_triage` |
| User asks to "fix", "patch", or "auto-fix" a build failure | `auto_fix` |

Set `pipeline_state.pipeline_type` accordingly.

---

## Mode Detection

Before executing any stage, determine the operating mode by checking MCP server availability:

| Check | Result |
|-------|--------|
| `jenkins-mcp` responds to a health/ping call | MCP candidate |
| `confluence-mcp` responds | MCP candidate |
| `github-mcp` or `gh` CLI available | MCP candidate |
| None of the above | Paste mode |

**Rules:**
- If **all required MCPs** (jenkins, github) are reachable &rarr; run in **MCP mode** using `auto-fix-mcp.md` conventions.
- If **any required MCP** is unreachable &rarr; run in **Paste mode** using `auto-fix-paste.md` conventions.
- Optional MCPs (confluence, nexus) degrade gracefully: skip their steps and note it in the audit log.

Announce the selected mode to the user:
> "Pipeline starting in **{MCP|Paste} mode**. Required integrations: {list}. Optional integrations available: {list}."

---

## Pipeline State

Initialise and carry the following state object through all stages:

```
pipeline_state:
  run_id: string          # unique identifier, e.g. "AF-{timestamp}" or "BLT-{timestamp}"
  pipeline_type: "auto_fix" | "build_log_triage"
  mode: "mcp" | "paste"
  started_at: timestamp
  current_stage: string   # depends on pipeline_type — see below
  retry_count: number     # starts at 0, max 3 (auto_fix only)
  config:
    max_retries: 3
    timeout_minutes: 30
    require_human_approval: true
    auto_merge: false
    labels: ["ai-auto-fix"]
  stages:
    # auto_fix stages
    detect: { status, output }
    analyse: { status, output }
    patch: { status, output }
    validate: { status, output }
    pr_create: { status, output }
    # build_log_triage stages
    ingest: { status, output }
    summarise: { status, output }
  audit_log: []           # append-only log of all actions taken
```

---

## Execution Flow

### Route by Pipeline Type

```
if pipeline_type == "auto_fix":
    execute Auto-Fix Flow (stages 01-detect through 05-pr-create)
elif pipeline_type == "build_log_triage":
    execute Build Log Triage Flow (stages 01-ingest through 02-summarise)
```

---

### Auto-Fix Flow (`auto_fix`)

```
┌──────────────────────────────────────────────────────────┐
│                  00 - ORCHESTRATOR                        │
│                  pipeline_type: auto_fix                  │
│                                                          │
│  1. Detect mode (MCP / Paste)                            │
│  2. Initialise pipeline_state                            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  01-detect  → failure record                       │  │
│  │  02-analyse → structured diagnosis                 │  │
│  │  03-patch   → unified diff                         │  │
│  │  04-validate → build result                        │  │
│  │      │                                             │  │
│  │      ├─ PASS → 05-pr-create → PR URL               │  │
│  │      └─ FAIL → retry_count < 3?                    │  │
│  │                 ├─ YES → loop to 02-analyse         │  │
│  │                 └─ NO  → escalate & exit            │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  3. Produce audit summary                                │
└──────────────────────────────────────────────────────────┘
```

### Build Log Triage Flow (`build_log_triage`)

```
┌──────────────────────────────────────────────────────────┐
│                  00 - ORCHESTRATOR                        │
│                  pipeline_type: build_log_triage          │
│                                                          │
│  1. Detect mode (MCP / Paste)                            │
│  2. Initialise pipeline_state                            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  01-ingest    → raw logs in workspace              │  │
│  │  02-summarise → per-log summaries + triage doc     │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  3. Present triage summary to user                       │
│  4. Offer next steps:                                    │
│     - Run auto-fix on specific failure group             │
│     - Drill into a specific build log                    │
│     - Export triage summary                              │
│  5. Produce audit summary                                │
└──────────────────────────────────────────────────────────┘
```

---

### Auto-Fix Step-by-step

1. **Run Stage 01 — Failure Detection** (`stages/01-detect.md`)
   - Pass: `pipeline_state.mode`
   - Receive: `job_name`, `build_number`, `build_log`, `failure_timestamp`, `failure_type`
   - Store in `pipeline_state.stages.detect.output`
   - Append to `audit_log`: `"Stage 01 complete — {failure_type} failure detected in {job_name} #{build_number}"`
   - If no failure found, report "All builds green" and **exit**.

2. **Run Stage 02 — Log Analysis** (`stages/02-analyse.md`)
   - Pass: `build_log`, `failure_type` from Stage 01, plus `mode`
   - Receive: `error_type`, `root_cause`, `affected_files`, `severity`, `known_issue`, `suggested_approach`
   - Store in `pipeline_state.stages.analyse.output`
   - Append to `audit_log`
   - **Breakpoint** — if `severity == "critical"` or confidence is low, pause for human approval before continuing.

3. **Run Stage 03 — Patch Generation** (`stages/03-patch.md`)
   - Pass: diagnosis from Stage 02, source files (fetched via MCP or pasted), `mode`
   - Receive: `patch`, `files_changed`, `fix_description`, `confidence`
   - Store in `pipeline_state.stages.patch.output`
   - Append to `audit_log`
   - **Breakpoint** — if `files_changed > 5` or `confidence == "low"`, pause for human review.

4. **Run Stage 04 — Validation** (`stages/04-validate.md`)
   - Pass: `patch`, `job_name`, `build_number`, `retry_count`, `mode`
   - Receive: `validation_result`, `validation_build_number`, `retry_count`, `escalated`
   - Store in `pipeline_state.stages.validate.output`
   - Append to `audit_log`

5. **Evaluate validation result:**
   - **If `validation_result == "pass"`** &rarr; proceed to Stage 05.
   - **If `validation_result == "fail"`**:
     - Increment `pipeline_state.retry_count`
     - If `retry_count > 3`:
       - Append to `audit_log`: `"Max retries exceeded. Escalating."`
       - Present full retry history to the user
       - Recommend manual investigation
       - **Exit pipeline**
     - If `retry_count <= 3`:
       - Append to `audit_log`: `"Retry {retry_count}/3 — re-analysing with new failure context"`
       - Feed the **new build log** from the failed validation back into Stage 02
       - Include context: original error, previous patch, new error
       - **Loop back to Step 2** (Stage 02 &rarr; 03 &rarr; 04)

6. **Run Stage 05 — PR Creation** (`stages/05-pr-create.md`)
   - Pass: all accumulated state — patch, diagnosis, validation result, `mode`
   - Receive: `pr_url`, `pr_number`, `pipeline_summary`
   - Store in `pipeline_state.stages.pr_create.output`
   - Append to `audit_log`

---

### Build Log Triage Step-by-step

1. **Run Stage 01-Ingest** (`stages/01-ingest.md`)
   - Pass: `pipeline_state.mode`, job name(s), optional `since` filter
   - Receive: `manifest_path`, `raw_log_paths`, `total_builds`, `failed_builds`
   - Store in `pipeline_state.stages.ingest.output`
   - Append to `audit_log`: `"Stage 01-ingest complete — ingested {failed_builds} logs"`

2. **Run Stage 02-Summarise** (`stages/02-summarise.md`)
   - Pass: `manifest_path`, `raw_log_paths`, auto-detected `context_budget`
   - Receive: `triage_summary_path`, `per_log_summary_paths`, `failure_groups`
   - Store in `pipeline_state.stages.summarise.output`
   - Append to `audit_log`

3. **Present triage to user:**
   - Display the `cross_log_triage_summary.md` content
   - Show the Table of Contents with failure group counts
   - Offer next steps:
     - "Run auto-fix on [failure group]" &rarr; switches to `auto_fix` pipeline type, pre-populating detect stage with the relevant build
     - "Show me the full log for [build]" &rarr; reads the raw log file
     - "Export this triage summary" &rarr; outputs the file path

---

## Breakpoints and Human Approval

The orchestrator pauses execution at these points when `require_human_approval: true`:

| Breakpoint | Condition | What the user sees |
|------------|-----------|-------------------|
| Post-detect | `failure_type == "unknown"` | "Cannot classify this failure. Please review before I proceed." |
| Post-analyse | `severity == "critical"` or low confidence | Structured diagnosis for review. "Approve to continue?" |
| Post-patch | `files_changed > 5` or `confidence == "low"` | Full diff for review. "Approve this patch?" |
| Post-validate (fail) | Always on failure | Failure details + retry plan. "Continue with retry {N}/3?" |
| Post-PR | Always | PR link + full audit summary |

At any breakpoint the user may:
- **Approve** &rarr; continue to next stage
- **Reject / Edit** &rarr; provide guidance, orchestrator re-runs the current stage with new context
- **Abort** &rarr; pipeline exits with partial audit log

---

## Error Handling

| Error | Action |
|-------|--------|
| Required MCP becomes unreachable mid-pipeline | Fall back to Paste mode for remaining stages. Log the switch. |
| AI model returns unusable output | Retry the AI call once. If still unusable, pause for human input. |
| Pipeline exceeds `timeout_minutes` | Abort, log all completed stages, notify user. |
| Unhandled exception | Abort, dump full state and audit log, notify user. |

---

## Audit Log Format

Every entry in the audit log follows this structure:

```
{
  timestamp: ISO-8601,
  stage: string,
  action: string,
  detail: string,
  mode: "mcp" | "paste",
  retry_attempt: number
}
```

At pipeline completion (or abort), present the full audit log as a summary table.

---

## Completion

### Auto-Fix Completion

On successful completion, present:

```
Pipeline Complete
=================
Run ID:       {run_id}
Pipeline:     auto_fix
Mode:         {mode}
Job:          {job_name} #{build_number}
Error Type:   {error_type}
Root Cause:   {root_cause}
Fix:          {fix_description}
Files:        {files_changed}
Validation:   PASSED (build #{validation_build_number})
PR:           {pr_url}
Retries:      {retry_count}/3
Duration:     {elapsed time}
Status:       COMPLETE
```

On failure (retries exhausted), present the same format with `Status: FAILED — escalated to manual review` and include all retry attempt summaries.

### Build Log Triage Completion

On successful completion, present:

```
Triage Complete
===============
Run ID:       {run_id}
Pipeline:     build_log_triage
Mode:         {mode}
Total Builds: {total_builds}
Failed:       {failed_builds}
Groups:       {failure_groups}
Triage:       {triage_summary_path}
Duration:     {elapsed time}
Status:       COMPLETE

Next: run `auto-fix-mcp` or `auto-fix-paste` to fix specific failures.
```
