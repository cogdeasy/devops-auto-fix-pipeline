# Stage 5: PR Creation

> **Prompt templates**:
> - [`workflows/prompts/pr-body-template.md`](../../../workflows/prompts/pr-body-template.md) — structured PR body with audit trail.
> - [`workflows/prompts/pr-comment-template.md`](../../../workflows/prompts/pr-comment-template.md) — follow-up PR comments for retries/escalation.

## Input
- `patch`, `fix_description`, `files_changed` from Stage 3
- `diagnosis` from Stage 2
- `job_name`, `build_number` from Stage 1
- `validation_build_number` from Stage 4

## Process

### 5.1 Compose PR Content

**Title**: `fix: {fix_description} [auto-fix #{build_number}]`

**Body**: Use the template from [`workflows/prompts/pr-body-template.md`](../../../workflows/prompts/pr-body-template.md), populating the `{{VARIABLE}}` placeholders with values from the pipeline state. The template includes sections for root cause, changes, risk assessment, validation results, original failure details, known issues, and an audit trail table.

**Labels**: `ai-auto-fix`

### 5.2 Create the PR

**MCP mode** (github-mcp or gh CLI):
- Use `gh pr create` or github-mcp to create the PR
- Assign reviewers based on CODEOWNERS or default team
- Add the `ai-auto-fix` label

**Paste mode**:
- Output the complete title and body in a code block
- Ask: "Would you like me to run `gh pr create`, or will you create the PR manually?"
- If manual: user copies the content into their PR tool

### 5.3 Pipeline Summary

Output a final summary:
```
Pipeline Execution Summary
==========================
Reference:    AI-FIX-{timestamp}
Job:          {job_name}
Build:        #{build_number}
Error Type:   {diagnosis.error_type}
Fix:          {fix_description}
Files:        {files_changed}
Validation:   PASSED (build #{validation_build_number})
PR:           {pr_url}
Retries:      {retry_count}/3
Status:       COMPLETE
```

## Output

```
pr_url: string
pr_number: number
pipeline_summary: string
```
