# Auto-Fix Pipeline - MCP Workflow

This workflow executes the complete auto-fix pipeline end-to-end using MCP integrations. All data retrieval and actions are performed through connected MCP tool servers (Jenkins, Confluence, GitHub, Nexus).

> **Orchestrator:** This workflow is invoked by `stages/00-orchestrator.md` when mode detection resolves to **MCP mode**. The orchestrator manages state, retry loops, and breakpoints. Each step below corresponds to a stage in the orchestrator flow.

---

## Prerequisites

Before starting this workflow, verify the following MCP servers are connected and responsive:

- `jenkins-mcp` -- for build status, console logs, and triggering builds
- `confluence-mcp` -- for searching known issues and runbooks
- `github-mcp` -- for repository operations (read files, create branches, push, open PRs)
- `nexus-mcp` -- for artifact and dependency checks

If any MCP server is unavailable, fall back to the Paste workflow (`auto-fix-paste.md`) for the affected steps.

---

## Step 1 - Failure Detection

**Objective:** Identify failed builds that require attention.

1. Call `jenkins-mcp` to list recent builds across monitored jobs. Filter for builds with status `FAILURE` or `UNSTABLE`.
2. For each failed build, retrieve:
   - Job name
   - Build number
   - Timestamp of the failure
   - Build trigger (SCM change, scheduled, manual)
   - The commit SHA that triggered the build (if available)
3. If **no failures are found**, report to the user: "All monitored builds are green. No action required." Then **exit the workflow**.
4. If multiple failures are found, prioritise them by:
   - Recency (most recent first)
   - Job criticality (production pipelines before development)
   - Process the highest-priority failure first. Inform the user of any remaining failures that will be addressed subsequently.
5. Log the detected failure details for the audit trail.

**Output of this step:** A failure record containing `job_name`, `build_number`, `timestamp`, `trigger_commit`, and `failure_summary`.

---

## Step 2 - Log Analysis

**Objective:** Analyse the build failure to produce a structured diagnosis.

1. Call `jenkins-mcp` to fetch the **full console log** for the failed build identified in Step 1. Use the job name and build number.
2. Parse the console log to identify:
   - **Error type**: One of `compilation`, `test_failure`, `dependency`, `deployment`, `infrastructure`, `timeout`, `configuration`, or `unknown`.
   - **Error messages**: Extract the specific error messages, stack traces, or failure assertions.
   - **Affected files**: Identify source files, test files, or configuration files referenced in the errors.
   - **Root cause hypothesis**: Based on the error pattern, formulate a root cause.
3. Call `confluence-mcp` to search for known issues matching the error patterns:
   - Search using key error messages, exception names, and error codes.
   - If a matching known issue or runbook is found, extract the documented fix or workaround.
   - Note the Confluence page URL for reference in the PR.
4. If the error type is `dependency`, call `nexus-mcp` to:
   - Check whether the required artifact version exists in the repository.
   - Identify if there is a version mismatch or if the artifact was recently removed/deprecated.
5. Produce a **structured diagnosis** with the following fields:
   - `error_type`: The classified error type.
   - `root_cause`: A concise description of the root cause.
   - `affected_files`: List of file paths that need changes.
   - `severity`: One of `critical`, `high`, `medium`, `low`.
   - `suggested_approach`: The recommended fix strategy.
   - `confluence_reference`: URL to any matching known issue (or "none").
   - `confidence`: A percentage indicating confidence in the diagnosis (e.g., "85%").

**Output of this step:** A structured diagnosis object.

---

## Step 3 - Patch Generation

**Objective:** Generate a code fix based on the diagnosis.

1. Call `github-mcp` to fetch the current content of each file listed in `affected_files` from the diagnosis. Use the repository's default branch (typically `main` or `master`).
2. Analyse each file in the context of the diagnosis:
   - Identify the specific lines that need to change.
   - Determine the minimal set of changes required to address the root cause.
   - If the Confluence known issue provided a fix pattern, apply that pattern.
3. Generate the patch:
   - Produce a unified diff for each affected file.
   - Include sufficient context lines (at least 3) for clarity.
   - Ensure the patch does not introduce new issues (no syntax errors, no removed imports that are still used, etc.).
4. For each change, document:
   - What was changed and why.
   - Any assumptions made.
   - Potential side effects or risks.
5. If the fix requires changes to multiple files, ensure consistency across all changes (e.g., if renaming a method, update all call sites).
6. Verify that no secrets, credentials, or tokens are present in the generated patch.

**Output of this step:** A set of file-level diffs and a change summary.

---

## Step 4 - Validation

**Objective:** Verify that the generated fix resolves the original failure without introducing regressions.

**Retry counter starts at 0. Maximum retries: 3.**

1. Call `github-mcp` to create a new feature branch from the default branch. Branch name: `auto-fix/<job-name>-<build-number>-<short-description>`.
2. Call `github-mcp` to commit and push the patched files to the feature branch. Commit message: `fix: <short description of the fix> (Jenkins #<build-number>)`.
3. Call `jenkins-mcp` to trigger a build of the same job but targeting the feature branch.
4. Wait for the build to complete. Poll the build status at reasonable intervals (e.g., every 30 seconds).
5. Once the build completes, check the result:
   - **If SUCCESS**: Proceed to Step 5.
   - **If FAILURE or UNSTABLE**:
     a. Increment the retry counter.
     b. If retry counter exceeds 3, **stop**. Report to the user:
        - "Auto-fix failed after 3 attempts."
        - Include the diagnosis, all patches attempted, and all build failure outputs.
        - Suggest manual investigation.
     c. If retries remain:
        - Fetch the new console log from the validation build.
        - Re-analyse the failure (return to Step 2 logic but using the new log).
        - Identify what the previous fix got wrong or what new issue it introduced.
        - Generate a revised patch (return to Step 3 logic).
        - Push the revised patch to the same feature branch (amend or new commit).
        - Trigger another validation build.
        - Return to step 5 of this section (wait and check).

**Output of this step:** A validated feature branch with a passing build.

---

## Step 5 - PR Creation

**Objective:** Create a pull request with full context for human review.

1. Compose the PR title: `[Auto-Fix] <error_type>: <short description> (Jenkins #<build-number>)`
2. Compose the PR body with the following sections:

   ```
   ## Root Cause Analysis
   <Detailed explanation of what caused the build failure>

   ## Changes Made
   <Summary of each file changed and what was modified>

   ## Risk Assessment
   <Evaluation of the risk level of this change: low/medium/high>
   <Any potential side effects or areas that reviewers should pay close attention to>

   ## Validation
   - Validation build: <link to the passing Jenkins build on the feature branch>
   - Build status: SUCCESS
   - Retry attempts: <number of retries taken, if any>

   ## References
   - Original failed build: <link to the failed Jenkins build>
   - Confluence known issue: <link, if applicable>

   ## Audit Trail
   <Summary of all pipeline actions taken during this run>
   ```

3. Call `github-mcp` to create the pull request:
   - Base branch: the repository's default branch
   - Head branch: the feature branch created in Step 4
   - Title and body as composed above
   - Labels: `ai-auto-fix`
   - Reviewers: assign based on the code owners of the affected files (if CODEOWNERS is configured), otherwise leave unassigned.
4. Report the PR URL to the user.
5. Present the complete audit log of the pipeline run.

**Output of this step:** A pull request URL and a complete run summary.

---

## Completion

Once the PR is created, present a final summary to the user:

- **Status**: Success / Partial (with retry details) / Failed (if retries exhausted)
- **Failed build**: Job name and build number
- **Root cause**: Brief description
- **Fix applied**: Summary of changes
- **PR URL**: Direct link to the created PR
- **Total duration**: Time from detection to PR creation
- **Retries**: Number of retry attempts (if any)
