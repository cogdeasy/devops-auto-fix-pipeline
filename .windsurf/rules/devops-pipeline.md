# DevOps Auto-Fix Pipeline - Rules

## Project Overview

This project implements an AI-driven DevOps auto-fix pipeline. The pipeline automatically detects CI/CD build failures, analyses root causes, generates patches, validates fixes, and creates pull requests -- all with minimal human intervention when MCP integrations are available, or with guided human collaboration when they are not.

## Modes of Operation

### MCP Mode

When MCP tool servers are available and connected, operate in MCP mode:

- **Always** use `jenkins-mcp` to fetch build statuses, console logs, and trigger validation builds.
- **Always** use `confluence-mcp` to search for known issues, runbooks, and historical fix patterns.
- **Always** use `github-mcp` to read source files, create branches, push commits, and open pull requests.
- **Always** use `nexus-mcp` to check artifact repositories for dependency resolution issues, version conflicts, and artifact availability.
- Do not prompt the user for data that can be retrieved via MCP. Only fall back to manual input if an MCP call fails after retry.

### Paste Mode

When MCP integrations are not available, operate in Paste mode:

- At each stage where an MCP tool would normally be used, prompt the user to paste the equivalent data.
- Provide clear instructions on what data is needed and in what format.
- Validate pasted input before proceeding to ensure it contains the required information.
- Guide the user through each step with explicit prompts and confirmations.

## Branching and Commit Policy

- **Never** commit directly to `main`, `master`, or any protected branch.
- **Always** create a feature branch for every fix. Use the naming convention: `auto-fix/<job-name>-<build-number>-<short-description>`.
- Each commit message must reference the original failed build (e.g., `fix: resolve compilation error in AuthService (Jenkins #1234)`).
- If a branch with the same name already exists, append a numeric suffix (e.g., `auto-fix/api-build-1234-nullpointer-2`).

## Validation Requirements

- All generated fixes **must** be validated before a pull request is created.
- Validation means: the patched code compiles successfully and passes the relevant test suite.
- In MCP mode, trigger a Jenkins build on the feature branch and wait for the result.
- In Paste mode, ask the user to run the build locally or trigger it and paste the result.
- Do not create a PR for a fix that has not passed validation.

## Retry Mechanism

- If a generated fix fails validation (does not compile or tests fail), re-analyse the failure output and generate a revised fix.
- Maximum retry attempts: **3**.
- On each retry:
  1. Fetch or request the new failure output.
  2. Identify what the previous fix got wrong.
  3. Generate an improved patch that addresses both the original issue and the regression.
  4. Re-validate.
- If all 3 retries are exhausted, stop and report the situation to the user with a full summary of all attempts, including diffs and failure outputs.

## Audit and Logging

- Log every significant action taken during the pipeline run. This includes:
  - Timestamp of each stage start and completion.
  - MCP calls made (tool name, parameters, success/failure).
  - Diagnosis produced at the analysis stage.
  - Patches generated (full diff content).
  - Validation build results (build number, status, duration).
  - PR creation details (URL, branch, title).
  - Retry attempts and their outcomes.
- Present the full audit log to the user at the end of each pipeline run.
- The audit log must be structured and machine-readable (use consistent formatting).

## Security

- **Never** expose credentials, API tokens, secrets, or sensitive configuration values in:
  - Generated code or patches.
  - PR descriptions or commit messages.
  - Log output shown to the user.
  - Any file written to the repository.
- If a build log contains secrets or tokens, redact them before including in any output or PR description.
- If a fix requires changes to configuration files that contain secrets, use placeholder values and add a comment instructing the operator to fill in the actual value.
- Do not store or cache any credentials between pipeline runs.

## Error Handling

- If an MCP call fails, retry once after a brief pause. If it fails again, inform the user and offer to switch to Paste mode for that specific step.
- If the build log is empty or unparseable, ask the user for clarification rather than guessing.
- If the diagnosis is ambiguous (multiple possible root causes), present all candidates to the user ranked by likelihood and ask for confirmation before proceeding.

## Output Standards

- All generated diffs must be in unified diff format.
- PR descriptions must include: root cause analysis, changes made, risk assessment, and a link to the original failed build.
- All PRs must be labelled with `ai-auto-fix`.
- Keep generated patches minimal -- change only what is necessary to fix the identified issue. Do not refactor unrelated code.

## Build Log Triage Flow

When the user invokes the `build-log-triage` workflow (or asks to triage/summarise build logs):

- This is a **read-only, diagnostic flow**. It does not generate patches, create branches, or open PRs.
- The flow runs two stages: **01-ingest** (raw log pull) and **02-summarise** (hierarchical summarisation).
- Write all output files to a `logs/` directory in the workspace.
- Always generate a `logs/manifest.json` with metadata about all ingested builds.
- Per-log summaries must use the **summarise-per-log** prompt template and follow the standard failure taxonomy.
- The cross-log triage summary must group failures by type, rank by severity, and recommend next steps.
- Use adaptive context budgets: generous (1-3 failures), moderate (4-10), terse (10+).
- After summarisation, present the triage to the user and offer to run `auto-fix-mcp` or `auto-fix-paste` on specific failure groups.
- Log every action in the audit log, same as the auto-fix flow.
