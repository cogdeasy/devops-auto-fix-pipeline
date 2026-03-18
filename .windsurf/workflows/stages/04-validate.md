# Stage 4: Validation

> **Prompt templates**:
> - [`workflows/prompts/validate-prompt.md`](../../../workflows/prompts/validate-prompt.md) — AI review of the patch against the build output.
> - [`workflows/prompts/validate-retry-prompt.md`](../../../workflows/prompts/validate-retry-prompt.md) — re-analysis after a failed fix attempt (used on retry).

## Input
- `patch`: unified diff from Stage 3
- `job_name`, `build_number` from Stage 1
- `retry_count`: current retry attempt (starts at 0)

## Process

### 4.1 Apply the Patch

**MCP mode** (github-mcp available):
1. Create branch `ai-fix/{job_name}-{build_number}` from the default branch
2. Apply the patch and commit:
   - Message: `fix: {fix_description} (auto-fix for #{build_number})`
3. Push the branch

**Paste mode**:
1. Provide git commands for the user to run:
   ```
   git checkout -b ai-fix/{job_name}-{build_number}
   git apply patch.diff
   git add .
   git commit -m "fix: {fix_description}"
   ```

### 4.2 Trigger Validation Build

**MCP mode** (jenkins-mcp available):
1. Call `trigger_build` with the feature branch
2. Poll `get_build_status` every 30 seconds (timeout: 15 minutes)
3. Retrieve the result

**Paste mode**:
1. Ask user: "Please trigger a build on the feature branch and paste the result when complete."
2. Alternatively: "Run the build locally: `mvn clean install` or `npm test` and paste the output."

### 4.3 Evaluate Result

**If build PASSED**:
- Proceed to Stage 5 (PR Creation)

**If build FAILED**:
- Increment retry_count
- If retry_count < 3:
  - Fetch the new build log
  - Return to Stage 2 with context:
    - Original error
    - Previous fix attempt
    - New error from validation
  - Generate a revised patch
- If retry_count >= 3:
  - Report: "Maximum retry attempts reached (3/3)"
  - Provide a summary of all attempts
  - Recommend manual investigation
  - Exit pipeline

## Output

```
validation_result: "pass" | "fail"
validation_build_number: number (if MCP mode)
retry_count: number
escalated: boolean
```
