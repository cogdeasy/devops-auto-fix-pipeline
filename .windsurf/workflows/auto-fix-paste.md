# Auto-Fix Pipeline - Paste Workflow

This workflow executes the complete auto-fix pipeline where the user pastes data at each stage. Instead of using MCP integrations, the user provides data by pasting build logs, source files, and other relevant information when prompted.

Use this workflow when MCP servers are not available or when the user prefers hands-on control over the process.

> **Orchestrator:** This workflow is invoked by `stages/00-orchestrator.md` when mode detection resolves to **Paste mode**. The orchestrator manages state, retry loops, and breakpoints. Each step below corresponds to a stage in the orchestrator flow.

---

## Prerequisites

- The user has access to the failed build log (from Jenkins, GitHub Actions, or another CI system).
- The user has access to the source repository (locally or via a web interface).
- The user can run builds locally or trigger them manually in the CI system.
- Git CLI is available if the user wants automated branch/PR creation.

---

## Step 1 - Failure Detection

**Objective:** Obtain and parse the build failure information.

1. Prompt the user:

   > "Please paste the Jenkins build log, build failure notification, or CI output that you want me to analyse. Include as much of the log as possible -- the full console output is ideal."

2. Wait for the user to paste the content.

3. Validate the pasted input:
   - Confirm it contains build output (look for common CI markers such as build timestamps, step names, exit codes, or error keywords).
   - If the input appears incomplete or is not a build log, ask: "This does not appear to be a complete build log. Could you paste the full console output? I need to see the error messages and stack traces to proceed."

4. Extract from the pasted log:
   - Job name (if identifiable from the log header)
   - Build number (if present)
   - Failure indicators (non-zero exit codes, "BUILD FAILURE", "FAILED", assertion errors, exceptions)

5. Confirm with the user:

   > "I have identified a build failure in [job name / context]. The failure appears to be [brief description]. Is this correct, and should I proceed with analysis?"

6. Log the detection details for the audit trail.

**Output of this step:** Parsed failure context from the user-provided log.

---

## Step 2 - Log Analysis

**Objective:** Analyse the pasted log and produce a structured diagnosis.

1. Analyse the build log provided in Step 1:
   - Classify the **error type**: `compilation`, `test_failure`, `dependency`, `deployment`, `infrastructure`, `timeout`, `configuration`, or `unknown`.
   - Extract **error messages**: specific compiler errors, test assertion failures, stack traces, dependency resolution errors.
   - Identify **affected files**: source files, test files, or configuration files mentioned in the errors.
   - Formulate a **root cause hypothesis**.

2. Prompt the user for additional context:

   > "Do you have any Confluence runbook, known issues documentation, or previous incident notes related to this type of failure? If yes, please paste the relevant content. If not, type 'skip' to continue without it."

3. If the user provides documentation:
   - Parse it for known fix patterns, workarounds, or resolution steps.
   - Incorporate the documented approach into the diagnosis.

4. If the error involves dependency issues, ask:

   > "Can you confirm the expected version of [dependency name]? If you have access to Nexus or your artifact repository, please check whether version [X.Y.Z] is available and paste the result."

5. Present the structured diagnosis to the user:

   ```
   DIAGNOSIS
   ---------
   Error Type:       [classification]
   Root Cause:       [description]
   Affected Files:   [list of file paths]
   Severity:         [critical/high/medium/low]
   Suggested Fix:    [approach description]
   Confidence:       [percentage]
   Reference:        [Confluence link or "none"]
   ```

6. Ask for confirmation:

   > "Does this diagnosis look correct? Should I proceed with generating a fix, or would you like to adjust anything?"

**Output of this step:** A confirmed structured diagnosis.

---

## Step 3 - Patch Generation

**Objective:** Generate a code fix based on the confirmed diagnosis.

1. Prompt the user for the source files:

   > "Please paste the content of the following file(s) that need fixing, or provide the local file paths so I can read them directly:
   > - [list of affected files from diagnosis]
   >
   > For each file, please include the complete content (or at minimum the surrounding context of the error location, ~50 lines above and below)."

2. Wait for the user to paste the file contents or provide paths.

3. If the user provides file paths:
   - Read the files from the local filesystem.
   - Confirm the files were read successfully.

4. If the user pastes file contents:
   - Validate that the content matches the expected file structure.
   - Confirm the file names/paths with the user.

5. Analyse the source files in context of the diagnosis:
   - Identify the specific lines to change.
   - Determine the minimal fix required.
   - If a known fix pattern was found in Step 2, apply that pattern.

6. Generate the patch and present it to the user as a unified diff:

   ```diff
   --- a/path/to/file.java
   +++ b/path/to/file.java
   @@ -XX,Y +XX,Z @@
    context line
   -old line
   +new line
    context line
   ```

7. For each change, explain:
   - What was changed and why.
   - Any assumptions made.
   - Potential risks or side effects.

8. Ask for approval:

   > "Here is the proposed fix. Please review the diff above. Do you approve this change, or would you like me to adjust anything?"

9. If the user requests adjustments, modify the patch and re-present. Repeat until approved.

**Output of this step:** An approved set of diffs.

---

## Step 4 - Validation

**Objective:** Verify the fix resolves the issue.

**Retry counter starts at 0. Maximum retries: 3.**

1. Prompt the user to validate the fix:

   > "Please apply the patch above to your local working copy and run the build/tests. You can:
   > - Run the full build locally (e.g., `mvn clean install`, `npm test`, `gradle build`)
   > - Trigger a CI build on a feature branch
   > - Run just the affected test suite if you want a quick check
   >
   > Once done, paste the build output here."

2. Wait for the user to paste the build result.

3. Analyse the pasted build output:
   - **If the build succeeded** (look for "BUILD SUCCESS", exit code 0, all tests passed):
     - Confirm with the user: "Build validation passed. Proceeding to PR creation."
     - Proceed to Step 5.
   - **If the build failed**:
     a. Increment the retry counter.
     b. If retry counter exceeds 3:
        - Report to the user: "The fix has failed validation after 3 attempts. Here is a summary of all attempts and their results. Manual investigation is recommended."
        - Present a summary of all patches attempted and their failure outputs.
        - **Exit the workflow.**
     c. If retries remain:
        - Analyse the new failure output.
        - Identify what the previous fix got wrong or what new issue it introduced.
        - Inform the user: "The fix did not pass validation. Attempt [N/3]. I am analysing the new failure to generate a revised fix."
        - Return to Step 3 to generate a revised patch.

**Output of this step:** Confirmation that the fix passes validation.

---

## Step 5 - PR Creation

**Objective:** Create a pull request or provide PR content for manual creation.

1. Ask the user their preference:

   > "The fix has been validated. How would you like to proceed with creating the pull request?
   >
   > Option A: I will create the branch, commit, push, and open the PR using git commands (requires git CLI access to the repo).
   >
   > Option B: I will generate the complete PR title, description, and instructions for you to create it manually."

2. **If Option A (Git automation):**
   a. Determine the repository root and default branch:
      - Ask: "What is the default branch name? (e.g., main, master, develop)"
   b. Create a feature branch:
      ```
      git checkout -b auto-fix/<job-name>-<build-number>-<short-description>
      ```
   c. Apply the changes to the working directory.
   d. Stage and commit:
      ```
      git add <affected files>
      git commit -m "fix: <short description> (Jenkins #<build-number>)"
      ```
   e. Push the branch:
      ```
      git push origin auto-fix/<job-name>-<build-number>-<short-description>
      ```
   f. Report the push result and provide instructions for opening the PR via the GitHub web interface, or use `gh` CLI if available:
      ```
      gh pr create --title "<title>" --body "<body>" --label "ai-auto-fix"
      ```
   g. Report the PR URL to the user.

3. **If Option B (Manual creation):**
   Present the complete PR content for copy-paste:

   ```
   PR TITLE:
   [Auto-Fix] <error_type>: <short description> (Jenkins #<build-number>)

   PR BODY:
   ## Root Cause Analysis
   <Detailed explanation of what caused the build failure>

   ## Changes Made
   <Summary of each file changed and what was modified>

   ## Risk Assessment
   <Evaluation of the risk level>
   <Potential side effects or areas for reviewer attention>

   ## Validation
   - Build validation: Passed locally / via CI
   - Retry attempts: <count>

   ## References
   - Original failed build: <build URL or identifier>
   - Known issue reference: <Confluence link or "N/A">

   LABELS: ai-auto-fix

   DIFF TO APPLY:
   <full unified diff>
   ```

4. Present the complete audit log of the pipeline run.

**Output of this step:** A created PR (Option A) or complete PR content for manual creation (Option B).

---

## Completion

Present a final summary to the user:

- **Status**: Success / Partial (with retry details) / Failed (if retries exhausted)
- **Root cause**: Brief description of what was found
- **Fix applied**: Summary of changes made
- **PR**: URL (if created) or "manual creation pending"
- **Retries**: Number of retry attempts (if any)
- **Audit log**: Full log of all actions taken during this run
