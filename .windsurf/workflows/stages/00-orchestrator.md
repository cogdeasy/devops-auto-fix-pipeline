# Stage 0: Pipeline Orchestrator

The orchestrator is the entry point for the AI Auto-Fix Pipeline. It determines the operating mode, initialises pipeline state, executes stages 01-05 in sequence, manages the retry loop, and produces the final audit trail.

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
  run_id: string          # unique identifier, e.g. "AF-{timestamp}"
  mode: "mcp" | "paste"
  started_at: timestamp
  current_stage: string   # "detect" | "analyse" | "patch" | "validate" | "pr_create"
  retry_count: number     # starts at 0, max 3
  config:
    max_retries: 3
    timeout_minutes: 30
    require_human_approval: true
    auto_merge: false
    labels: ["ai-auto-fix"]
  stages:
    detect: { status, output }
    analyse: { status, output }
    patch: { status, output }
    validate: { status, output }
    pr_create: { status, output }
  audit_log: []           # append-only log of all actions taken
```

---

## Execution Flow

```
┌──────────────────────────────────────────────────────────┐
│                  00 - ORCHESTRATOR                        │
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

### Step-by-step

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

On successful completion, present:

```
Pipeline Complete
=================
Run ID:       {run_id}
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
