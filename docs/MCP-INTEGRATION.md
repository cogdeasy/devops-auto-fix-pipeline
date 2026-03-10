# MCP Integration Guide

## Table of Contents

1. [Overview](#1-overview)
2. [MCP Servers](#2-mcp-servers)
3. [Pipeline Stage Integration](#3-pipeline-stage-integration)
4. [Pipeline Action to MCP Mapping Table](#4-pipeline-action-to-mcp-mapping-table)
5. [MCP Server Status Matrix](#5-mcp-server-status-matrix)
6. [Data Flow Diagrams](#6-data-flow-diagrams)
7. [Error Handling](#7-error-handling)
8. [Security Considerations](#8-security-considerations)

---

## 1. Overview

The AI-Driven DevOps Auto-Fix Pipeline uses the **Model Context Protocol (MCP)** to bridge the gap between AI-powered analysis (running inside Windsurf Cascade) and the enterprise DevOps toolchain. MCP provides a standardised interface through which the AI agent can query, trigger, and interact with Jenkins, Confluence, GitHub, and Nexus -- without bespoke integrations or brittle API scripts.

Each MCP server acts as a thin, authenticated proxy between the AI orchestrator and the underlying service. The servers expose a curated set of **tools** (actions the AI can invoke) and **resources** (data the AI can read), scoped to exactly what the pipeline requires. This keeps the attack surface narrow and the integration auditable.

The pipeline is designed for **graceful degradation**. If one or more MCP servers are unavailable -- due to network restrictions, credential expiry, or an air-gapped environment -- the pipeline falls back to **Paste mode** for that stage, prompting the user to paste the equivalent data. No stage has a hard dependency on full MCP connectivity; every stage can operate in either MCP or Paste mode independently.

This document details each MCP server, how it integrates with each pipeline stage, the exact tools and resources invoked, data flow between components, error handling strategies, and security considerations.

---

## 2. MCP Servers

### 2.1 jenkins-mcp

| Attribute | Detail |
|-----------|--------|
| **Directory** | `mcp-servers/jenkins-mcp/` |
| **Transport** | stdio |
| **Upstream API** | Jenkins REST API (JSON) |

**Purpose.** Provides read and write access to Jenkins CI/CD jobs. The pipeline uses this server primarily in Stage 1 (Failure Detection) to retrieve failed build information and console logs, and in Stage 4 (Validation) to trigger rebuild jobs and poll for completion.

**Key Tools Exposed:**

| Tool | Description |
|------|-------------|
| `get_failed_builds` | Returns a list of recent failed builds for a given job, including build number, timestamp, and failure summary. |
| `get_build_log` | Retrieves the full or tail-end console output for a specific build number. |
| `trigger_build` | Triggers a new build of a specified job, optionally with parameters (branch, environment, etc.). |
| `get_build_status` | Polls a running or completed build and returns its current status (queued, building, success, failure, unstable). |
| `get_job_config` | Returns the job configuration XML, useful for understanding build steps and environment variables. |

**Key Resources:**

| Resource | Description |
|----------|-------------|
| `jenkins://jobs/{job_name}/builds` | List of recent builds with metadata (number, result, duration). |
| `jenkins://jobs/{job_name}/builds/{build_number}/log` | Raw console log for a specific build. |
| `jenkins://jobs/{job_name}/config` | Job configuration (pipeline definition, parameters, triggers). |

**Configuration Requirements:**

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `JENKINS_URL` | Base URL of the Jenkins instance (e.g., `https://jenkins.internal.example.com`) | Yes |
| `JENKINS_USER` | Jenkins service account username | Yes |
| `JENKINS_API_TOKEN` | Jenkins API token (not password) for the service account | Yes |
| `JENKINS_CRUMB_ISSUER` | Set to `true` if CSRF protection is enabled (default in modern Jenkins) | No |

---

### 2.2 confluence-mcp

| Attribute | Detail |
|-----------|--------|
| **Directory** | `mcp-servers/confluence-mcp/` |
| **Transport** | stdio |
| **Upstream API** | Confluence REST API v2 (Atlassian Cloud or Data Center) |

**Purpose.** Provides read access to Confluence documentation, runbooks, and known-issue pages. The pipeline uses this server in Stage 2 (Log Analysis) to cross-reference error signatures against documented known issues, prior incident resolutions, and team runbooks.

**Key Tools Exposed:**

| Tool | Description |
|------|-------------|
| `search_known_issues` | Searches Confluence spaces for pages matching an error signature or keyword, using CQL (Confluence Query Language). |
| `get_page_content` | Retrieves the body content (in storage format or plain text) of a specific Confluence page by ID or title. |
| `get_page_children` | Lists child pages under a given parent, useful for navigating structured runbook hierarchies. |
| `search_by_label` | Finds pages tagged with specific labels (e.g., `known-issue`, `build-failure`, `hotfix`). |

**Key Resources:**

| Resource | Description |
|----------|-------------|
| `confluence://spaces/{space_key}/pages` | Paginated list of pages in a space. |
| `confluence://pages/{page_id}` | Full page content with metadata (author, last modified, labels). |
| `confluence://search?cql={query}` | CQL search results across configured spaces. |

**Configuration Requirements:**

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `CONFLUENCE_URL` | Base URL (e.g., `https://wiki.internal.example.com` or `https://yourorg.atlassian.net/wiki`) | Yes |
| `CONFLUENCE_USER` | Service account email or username | Yes |
| `CONFLUENCE_API_TOKEN` | API token (Atlassian Cloud) or password (Data Center with basic auth) | Yes |
| `CONFLUENCE_SPACE_KEYS` | Comma-separated list of space keys to search (e.g., `DEVOPS,RUNBOOKS,KB`) | No (defaults to all accessible spaces) |

---

### 2.3 github-mcp

| Attribute | Detail |
|-----------|--------|
| **Directory** | External: `@modelcontextprotocol/server-github` |
| **Transport** | stdio |
| **Upstream API** | GitHub REST and GraphQL APIs |

**Purpose.** Provides read and write access to GitHub repositories. The pipeline uses this server in Stage 3 (Patch Generation) to fetch source files and search for similar prior fixes, and in Stage 5 (PR Creation) to create branches and open pull requests.

**Key Tools Exposed:**

| Tool | Description |
|------|-------------|
| `get_file_contents` | Fetches the contents of a file or directory at a given ref (branch, tag, commit SHA). |
| `search_code` | Searches repository code by keyword, filename, or language. |
| `search_issues` | Searches issues and pull requests by keyword, label, state, or author. Used to find similar prior fixes. |
| `create_or_update_file` | Creates or updates a file on a given branch. Used to commit patches. |
| `create_branch` | Creates a new branch from a specified base ref. |
| `create_pull_request` | Opens a pull request with a title, body, base branch, and head branch. |
| `create_repository` | Creates a new repository (rarely used in this pipeline). |
| `push_files` | Pushes multiple file changes in a single commit to a branch. |
| `list_branches` | Lists branches in the repository. |
| `list_commits` | Lists recent commits on a branch. |

**Key Resources:**

| Resource | Description |
|----------|-------------|
| `github://repos/{owner}/{repo}/contents/{path}?ref={branch}` | File or directory contents at a specific ref. |
| `github://repos/{owner}/{repo}/pulls?state=closed&q={keyword}` | Closed PRs matching a keyword (for prior-fix lookup). |
| `github://repos/{owner}/{repo}/branches` | List of branches in the repository. |

**Configuration Requirements:**

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `GITHUB_PERSONAL_ACCESS_TOKEN` | Personal access token (classic) or fine-grained token with `repo`, `workflow`, and `pull_request` scopes | Yes |

Note: The repository owner and name are typically provided as parameters to individual tool calls rather than as server-level configuration.

---

### 2.4 nexus-mcp

| Attribute | Detail |
|-----------|--------|
| **Directory** | `mcp-servers/nexus-mcp/` |
| **Transport** | stdio |
| **Upstream API** | Sonatype Nexus Repository Manager REST API |

**Purpose.** Provides read access to the Nexus artifact repository. The pipeline uses this server in Stage 2 (Log Analysis) to verify dependency availability, check artifact versions, and diagnose dependency-resolution failures that surface in build logs.

**Key Tools Exposed:**

| Tool | Description |
|------|-------------|
| `search_artifacts` | Searches for artifacts by group, name, version, or classifier. Returns available versions and repository membership. |
| `get_artifact_info` | Returns metadata for a specific artifact (GAV coordinates, checksums, upload date, repository). |
| `list_repositories` | Lists all repositories (hosted, proxy, group) configured in Nexus. |
| `check_artifact_exists` | Boolean check for whether a specific artifact version exists in a given repository. |

**Key Resources:**

| Resource | Description |
|----------|-------------|
| `nexus://repositories` | List of configured repositories with type and format. |
| `nexus://search?group={g}&name={a}&version={v}` | Search results for a specific artifact coordinate. |
| `nexus://components/{id}` | Full component metadata by internal ID. |

**Configuration Requirements:**

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `NEXUS_URL` | Base URL of the Nexus instance (e.g., `https://nexus.internal.example.com`) | Yes |
| `NEXUS_USER` | Service account username with read access | Yes |
| `NEXUS_PASSWORD` | Password or token for the service account | Yes |
| `NEXUS_REPOSITORY` | Default repository to search (e.g., `maven-central`, `npm-hosted`) | No |

---

## 3. Pipeline Stage Integration

### Stage 1: Failure Detection

**MCP Servers Used:** `jenkins-mcp`

**Objective.** Identify that a build has failed, retrieve the relevant build metadata, and capture the console log for analysis.

**Tool and Resource Calls:**

1. **`jenkins-mcp: get_failed_builds`** -- Called with the target job name (e.g., `my-service/main`). Returns a list of failed builds sorted by recency. The pipeline selects the most recent failure (or a specific build number if provided by the user).

2. **`jenkins-mcp: get_build_log`** -- Called with the job name and build number from step 1. Returns the full console output. The pipeline extracts the final 500 lines by default, as failure context is typically concentrated at the end.

**Data Flow:**

| Direction | Data |
|-----------|------|
| **In** | Job name (from user or webhook trigger) |
| **Out** | Build number, build timestamp, failure status, console log (raw text) |

**Breakpoints (MCP-to-Paste Handoff):**

- If `jenkins-mcp` is not connected, the pipeline prompts: *"Paste the Jenkins console log for the failed build."*
- If the job name is ambiguous or not found, the pipeline asks the user to confirm the exact job path.
- If the build log exceeds 50,000 characters, the pipeline asks the user to confirm whether to proceed with truncated output or provide a filtered excerpt.

**Paste Mode Equivalent:** The user pastes the Jenkins failure notification email or the console log directly into the Windsurf prompt.

---

### Stage 2: Log Analysis

**MCP Servers Used:** `confluence-mcp` (optional), `nexus-mcp` (optional)

**Objective.** Analyse the console log from Stage 1 to classify the failure type, identify root cause, and gather supporting context from documentation and artifact repositories.

The AI performs the primary analysis locally (pattern matching on error messages, stack traces, and build tool output). MCP servers augment this analysis with external context.

**Tool and Resource Calls:**

1. **`confluence-mcp: search_known_issues`** -- Called with extracted error signatures (e.g., `"OutOfMemoryError in gradle daemon"`, `"SNAPSHOT not found"`). Returns matching Confluence pages with known resolutions.

2. **`confluence-mcp: get_page_content`** -- Called for each relevant search result to retrieve the full resolution steps from the runbook or known-issue page.

3. **`nexus-mcp: search_artifacts`** -- Called when the failure involves dependency resolution (e.g., `"Could not resolve artifact com.example:library:2.3.1"`). Verifies whether the artifact exists in Nexus, and if so, which versions are available.

4. **`nexus-mcp: check_artifact_exists`** -- Called for targeted version verification when the build log references a specific dependency version.

**Data Flow:**

| Direction | Data |
|-----------|------|
| **In** | Console log text, extracted error signatures, dependency coordinates (from Stage 1 output) |
| **Out** | Failure classification (compilation error, test failure, dependency issue, infrastructure issue), root cause hypothesis, relevant Confluence page links, dependency availability status |

**Breakpoints (MCP-to-Paste Handoff):**

- If `confluence-mcp` is not connected, the pipeline skips known-issue lookup and asks: *"Do you have any Confluence pages or runbooks related to this error? Paste the content or URL."*
- If `nexus-mcp` is not connected and the failure is dependency-related, the pipeline asks: *"Can you confirm whether artifact X version Y is available in Nexus?"*
- If the AI's confidence in root cause classification is below a configured threshold (default: 70%), the pipeline pauses and presents its analysis for human review before proceeding.

**Paste Mode Equivalent:** The user pastes Confluence page content and confirms dependency versions when prompted.

---

### Stage 3: Patch Generation

**MCP Servers Used:** `github-mcp`

**Objective.** Fetch the relevant source files, review similar prior fixes, and generate a patch that addresses the root cause identified in Stage 2.

**Tool and Resource Calls:**

1. **`github-mcp: get_file_contents`** -- Called for each source file implicated in the failure (paths extracted from stack traces, compilation errors, or build configuration references). Retrieves the current file content from the target branch.

2. **`github-mcp: search_issues`** -- Called with keywords from the error signature to find previously merged PRs that addressed similar failures. Provides the AI with patterns and precedents for the fix.

3. **`github-mcp: search_code`** -- Called when the AI needs to locate related files (e.g., finding all files that import a changed class, locating test files for the affected module).

**Data Flow:**

| Direction | Data |
|-----------|------|
| **In** | Root cause analysis, file paths from stack traces, error classification, Confluence resolution steps (from Stage 2 output) |
| **Out** | Proposed patch (unified diff format), list of modified files, explanation of changes, confidence score |

**Breakpoints (MCP-to-Paste Handoff):**

- If `github-mcp` is not connected, the pipeline asks: *"Paste the contents of [file path] from the [branch] branch."* This is repeated for each required file.
- If the AI finds multiple plausible fixes, it presents all options with trade-off analysis and asks the user to select one.
- If the patch modifies more than 5 files or exceeds 200 lines of changes, the pipeline pauses for human review before proceeding to validation.
- If the patch touches security-sensitive files (authentication, encryption, access control), the pipeline always pauses for human review regardless of confidence.

**Paste Mode Equivalent:** The user pastes file contents or provides file paths for local reads. The user describes any known related fixes they are aware of.

---

### Stage 4: Validation

**MCP Servers Used:** `jenkins-mcp`

**Objective.** Apply the generated patch to a feature branch, trigger a validation build, and verify that the fix resolves the original failure without introducing regressions.

**Tool and Resource Calls:**

1. **`jenkins-mcp: trigger_build`** -- Called with the job name and the feature branch (created in Stage 5 preparation or via local git) as a parameter. Triggers a full build-and-test cycle against the patched code.

2. **`jenkins-mcp: get_build_status`** -- Polled at intervals (default: 30 seconds) until the build completes. Returns the final status (success, failure, unstable).

3. **`jenkins-mcp: get_build_log`** -- If the validation build fails, retrieves the console log for comparison against the original failure. The AI determines whether this is the same failure (patch did not work), a new failure (patch introduced a regression), or a transient infrastructure issue.

**Data Flow:**

| Direction | Data |
|-----------|------|
| **In** | Patch (from Stage 3), feature branch name, job name |
| **Out** | Build result (pass/fail), console log (if failed), regression analysis |

**Retry Logic:**

The pipeline supports up to 3 validation attempts. On each failure:

1. The AI analyses the new console log.
2. If the failure is different from the original, the AI generates a revised patch.
3. If the failure is the same, the AI escalates to manual review.
4. If the failure is an infrastructure issue (e.g., agent offline, timeout), the pipeline retries without modifying the patch.

**Breakpoints (MCP-to-Paste Handoff):**

- If `jenkins-mcp` is not connected, the pipeline asks: *"Please trigger a build of [job name] on branch [branch name] and paste the result when complete."*
- After 3 failed validation attempts, the pipeline stops and presents a summary of all attempts for human review.
- If the validation build takes longer than a configured timeout (default: 30 minutes), the pipeline alerts the user and asks whether to continue waiting or abort.

**Paste Mode Equivalent:** The user triggers the build manually in Jenkins and pastes the console output back into the prompt.

---

### Stage 5: PR Creation

**MCP Servers Used:** `github-mcp`

**Objective.** Create a feature branch (if not already created during validation), commit the validated patch, and open a pull request with a structured description for human review.

**Tool and Resource Calls:**

1. **`github-mcp: create_branch`** -- Creates a feature branch from the target base branch (e.g., `main` or `develop`). Branch naming convention: `auto-fix/{job-name}/{build-number}` (e.g., `auto-fix/my-service/1234`).

2. **`github-mcp: push_files`** -- Commits the patched files to the feature branch in a single commit. Commit message follows the convention: `fix: [auto] resolve {failure_type} in {module}`.

3. **`github-mcp: create_pull_request`** -- Opens a PR against the base branch with:
   - **Title:** Structured summary of the fix.
   - **Body:** Includes the original failure summary, root cause analysis, patch explanation, validation results, Confluence links (if any), and a note that this PR was AI-generated.
   - **Labels:** `auto-fix`, `ai-generated` (if supported by repository configuration).
   - **Reviewers:** Assigned based on CODEOWNERS or a configured default reviewer list.

**Data Flow:**

| Direction | Data |
|-----------|------|
| **In** | Validated patch, failure analysis, build results, Confluence links (from Stages 1-4) |
| **Out** | PR URL, branch name, commit SHA |

**Breakpoints (MCP-to-Paste Handoff):**

- If `github-mcp` is not connected, the pipeline outputs the patch as a unified diff and a pre-formatted PR body in Markdown. The user can then: (a) apply the diff locally with `git apply`, (b) push to a branch, and (c) create the PR manually using the provided body text.
- If the repository requires signed commits or has branch protection rules that prevent direct pushes from the service account, the pipeline falls back to local git commands and prompts the user accordingly.
- The PR is always created in **draft** state (where supported) to enforce human review before merge.

**Paste Mode Equivalent:** The user runs `git checkout -b`, `git apply`, `git push`, and `gh pr create` locally, using the diff and PR body provided by the pipeline.

---

## 4. Pipeline Action to MCP Mapping Table

The following table provides a complete mapping of every pipeline action to its MCP mode and Paste mode implementations:

| Stage | Action | MCP Mode | Paste Mode |
|-------|--------|----------|------------|
| 1. Detect | Get failed builds | jenkins-mcp: get_failed_builds | User pastes Jenkins failure notification |
| 1. Detect | Get build details | jenkins-mcp: get_build_log | User pastes console log |
| 2. Analyse | Search known issues | confluence-mcp: search_known_issues | User pastes Confluence page content |
| 2. Analyse | Check dependencies | nexus-mcp: search_artifacts | User confirms dependency versions |
| 3. Patch | Fetch source files | github-mcp (or gh CLI) | User pastes file content or provides path |
| 3. Patch | Check similar PRs | github-mcp: search PRs | User describes any known related fixes |
| 4. Validate | Trigger build | jenkins-mcp: trigger_build | User triggers manually and pastes result |
| 4. Validate | Check build result | jenkins-mcp: get_build_status | User pastes build output |
| 5. PR | Create branch | github-mcp (or git CLI) | git commands executed locally |
| 5. PR | Create PR | github-mcp (or gh CLI) | User copies PR body and creates manually |

---

## 5. MCP Server Status Matrix

This matrix shows which MCP servers are required or optional at each pipeline stage, enabling teams to assess which stages they can automate given their current MCP availability:

| MCP Server | Stage 1 (Detect) | Stage 2 (Analyse) | Stage 3 (Patch) | Stage 4 (Validate) | Stage 5 (PR) |
|------------|:-:|:-:|:-:|:-:|:-:|
| jenkins-mcp | Required | -- | -- | Required | -- |
| confluence-mcp | -- | Optional | -- | -- | -- |
| nexus-mcp | -- | Optional | -- | -- | -- |
| github-mcp | -- | -- | Required | -- | Required |

### Partial Automation Scenarios

**Scenario A: Jenkins MCP only.** If only `jenkins-mcp` is configured, Stages 1 and 4 run in full MCP mode. Stages 2 and 3 require manual input (user pastes Confluence content, file contents). Stage 5 requires the user to create the PR manually using the AI-generated diff and PR body. This is a common configuration for teams that have Jenkins API access but operate in a restricted GitHub environment.

**Scenario B: GitHub MCP only.** If only `github-mcp` is configured, Stages 3 and 5 run in full MCP mode. Stage 1 requires the user to paste the Jenkins failure log. Stage 2 requires manual Confluence and Nexus lookups. Stage 4 requires the user to trigger and report on the validation build manually. This is useful when teams want AI-assisted patch generation and PR creation but trigger the pipeline manually from a build failure.

**Scenario C: All MCPs except Confluence and Nexus.** Stages 1, 3, 4, and 5 run in full MCP mode. Stage 2 operates in partial MCP mode: the AI performs its own log analysis (pattern matching, error classification) without external context augmentation. The quality of analysis may be lower for obscure or organisation-specific errors that would otherwise be resolved by consulting runbooks. This is the most common configuration, as Confluence and Nexus integrations are optional enhancements.

**Scenario D: No MCPs (Paste mode).** All stages operate in Paste mode. The user pastes data at each stage, and the AI performs analysis, patch generation, and PR body formatting. This mode requires no infrastructure access and works in air-gapped environments. It is the fallback for all stages.

**Scenario E: Selective stage automation.** Teams can configure MCP availability on a per-stage basis through the pipeline configuration. For example, a team might allow MCP-connected detection (Stage 1) and analysis (Stage 2) but require review gates at patch generation (Stage 3) and PR creation (Stage 5) for compliance reasons. The breakpoints described in Section 3 support this pattern.

---

## 6. Data Flow Diagrams

### 6.1 End-to-End Pipeline Data Flow

```
                          AI Orchestrator (Windsurf Cascade)
                          ==================================

  Stage 1               Stage 2              Stage 3              Stage 4              Stage 5
  Detect                Analyse              Patch                Validate             PR Create
  --------              --------             --------             --------             ---------
  |                     |                    |                    |                    |
  | job_name            | console_log        | root_cause         | patch_diff         | validated_patch
  | build_number        | error_signatures   | file_paths         | branch_name        | pr_body
  v                     v                    v                    v                    v
+-----------+     +------------+      +------------+      +-----------+      +------------+
| jenkins   |     | confluence |      | github     |      | jenkins   |      | github     |
| -mcp      |     | -mcp       |      | -mcp       |      | -mcp      |      | -mcp       |
|           |     | nexus-mcp  |      |            |      |           |      |            |
+-----------+     +------------+      +------------+      +-----------+      +------------+
      |                 |                    |                    |                    |
      v                 v                    v                    v                    v
  build_log         known_issues         source_files         build_result         pr_url
  build_metadata    dependency_info      similar_prs          new_build_log        branch_name
                                         patch_diff                                commit_sha
```

### 6.2 Single Stage Detail: Stage 1 (Failure Detection)

```
  User / Webhook
       |
       | job_name (e.g., "my-service/main")
       v
+-------------------+
| Pipeline Entry    |
| Point             |
+-------------------+
       |
       v
+-------------------+       +---------------------+
| get_failed_builds |------>| Jenkins REST API     |
| (jenkins-mcp)    |<------| /job/{name}/api/json |
+-------------------+       +---------------------+
       |
       | build_number, status, timestamp
       v
+-------------------+       +---------------------+
| get_build_log     |------>| Jenkins REST API     |
| (jenkins-mcp)    |<------| /job/{name}/{id}/    |
+-------------------+       |   consoleText        |
       |                    +---------------------+
       | console_log (raw text, up to 50K chars)
       v
+-------------------+
| Stage 1 Output    |
| - build_number    |
| - console_log     |
| - failure_summary |
+-------------------+
       |
       v
   [Stage 2: Analyse]
```

### 6.3 MCP Fallback Flow

```
  Pipeline requests data via MCP tool call
       |
       v
  +-------------------+
  | MCP Server        |
  | Available?        |
  +---+----------+----+
      |          |
     YES         NO
      |          |
      v          v
  +---------+  +---------------------+
  | Execute |  | Prompt user for     |
  | tool    |  | manual equivalent   |
  | call    |  | (paste/confirm)     |
  +---------+  +---------------------+
      |          |
      v          v
  +-------------------+
  | Normalise output  |
  | to common format  |
  +-------------------+
      |
      v
  [Continue pipeline]
```

### 6.4 Validation Retry Loop (Stage 4)

```
  Patch from Stage 3
       |
       v
  +---------------------+
  | Apply patch to      |
  | feature branch      |
  +---------------------+
       |
       v
  +---------------------+       attempt = 1
  | trigger_build       |<-----------+
  | (jenkins-mcp)       |            |
  +---------------------+            |
       |                             |
       v                             |
  +---------------------+            |
  | get_build_status    |            |
  | (poll until done)   |            |
  +---------------------+            |
       |                             |
       +------+------+               |
       |             |               |
    SUCCESS       FAILURE            |
       |             |               |
       v             v               |
  +---------+  +------------------+  |
  | Stage 5 |  | Same failure as  |  |
  |         |  | original?        |  |
  +---------+  +---+----------+---+  |
                   |          |      |
                  YES         NO     |
                   |          |      |
                   v          v      |
             +---------+  +------+   |
             | Escalate|  | New  |   |
             | to human|  | error|   |
             +---------+  +------+   |
                             |       |
                             v       |
                       +----------+  |
                       | Revise   |  |
                       | patch    |--+
                       | attempt  |
                       | <= 3?    |----> NO ----> Escalate to human
                       +----------+
```

---

## 7. Error Handling

### 7.1 MCP Server Unavailability

When an MCP server becomes unavailable mid-pipeline, the system follows a structured degradation protocol:

**Connection Failure at Stage Entry.**
If the MCP server cannot be reached when a stage begins, the pipeline immediately switches that stage to Paste mode. The user is informed which MCP server is unavailable and what data they need to provide. Previously completed stages are not affected.

**Connection Failure Mid-Tool-Call.**
If the connection drops during an active tool call (e.g., `get_build_log` times out), the pipeline:

1. Retries the tool call up to 3 times with exponential backoff (2s, 4s, 8s).
2. If all retries fail, falls back to Paste mode for that specific action.
3. Logs the failure with timestamp, tool name, error details, and retry count for audit purposes.

**Partial Data Retrieval.**
If a tool call returns partial data (e.g., truncated log, incomplete search results), the pipeline:

1. Proceeds with the available data if it meets a minimum viability threshold.
2. Warns the user that the data may be incomplete.
3. Offers the user the option to supplement with manually provided data.

### 7.2 Upstream Service Errors

| Error Type | Response |
|------------|----------|
| **401 Unauthorized** | Pipeline halts. Prompts user to verify credentials. Does not retry (credentials will not self-heal). |
| **403 Forbidden** | Pipeline halts. Reports the specific permission that is missing (e.g., "Service account lacks Job/Build permission on Jenkins"). |
| **404 Not Found** | Pipeline asks the user to verify the resource identifier (job name, page ID, artifact coordinates). May suggest alternatives. |
| **429 Rate Limited** | Pipeline waits for the duration specified in the `Retry-After` header (or 60 seconds if absent), then retries. |
| **500+ Server Error** | Pipeline retries up to 3 times with exponential backoff. On persistent failure, falls back to Paste mode. |
| **Timeout (>30s)** | Pipeline retries once. On second timeout, falls back to Paste mode with a note about potential service degradation. |

### 7.3 Data Validation Errors

The pipeline validates data at stage boundaries:

- **Stage 1 output:** Console log must be non-empty and contain recognisable build output markers. If the log appears to be HTML (common with misconfigured Jenkins API responses), the pipeline strips HTML tags and re-validates.
- **Stage 2 output:** Failure classification must be one of the defined categories (compilation, test, dependency, infrastructure, configuration, unknown). If classification is "unknown", the pipeline requests human input.
- **Stage 3 output:** Patch must be valid unified diff format. The pipeline runs a dry-apply check (`git apply --check`) before proceeding. If the patch does not apply cleanly, the pipeline asks the AI to regenerate based on a fresh fetch of the source files.
- **Stage 4 output:** Build status must be a terminal state (success, failure, unstable, aborted). If the status is still "building" after the timeout, the pipeline reports accordingly rather than assuming failure.

### 7.4 Pipeline State Recovery

If the pipeline is interrupted (e.g., Windsurf session ends, network outage), the state of completed stages is preserved in the session context. On resumption:

1. The pipeline presents a summary of completed stages.
2. The user can choose to resume from the last incomplete stage or restart from a specific stage.
3. Data from completed stages (build logs, analysis results, patches) is retained and does not need to be re-fetched.

---

## 8. Security Considerations

### 8.1 Token and Credential Management

**Storage.** All credentials are stored as environment variables on the machine running the MCP servers. Credentials must never be:

- Committed to version control (enforced by `.gitignore` patterns for `.env` files, `mcp-config.json`, and similar).
- Embedded in workflow definition files or prompt templates.
- Logged in pipeline output or diagnostic dumps.

**Scope.** Each MCP server's service account should be provisioned with the minimum permissions required:

| MCP Server | Required Permissions |
|------------|---------------------|
| jenkins-mcp | Job/Read, Job/Build (for trigger), Run/Replay (optional) |
| confluence-mcp | Space/Read on configured spaces only (no write access required) |
| github-mcp | `repo` scope (read/write for code and PRs), `workflow` scope (optional, for triggering Actions) |
| nexus-mcp | Read-only access to relevant repositories (nx-repository-view-*-*-read) |

**Token Types.** Prefer short-lived or rotatable tokens over long-lived credentials:

| Service | Recommended Token Type |
|---------|----------------------|
| Jenkins | API token (rotatable, revocable per-user) |
| Confluence (Cloud) | Atlassian API token (90-day expiry recommended) |
| Confluence (DC) | Personal access token or basic auth (enforce rotation policy) |
| GitHub | Fine-grained personal access token with repository-scoped permissions and expiration date |
| Nexus | Service account with role-based access; password managed by secrets vault |

### 8.2 Credential Rotation

Establish a rotation schedule for all MCP server credentials:

| Cadence | Action |
|---------|--------|
| Every 90 days | Rotate Jenkins API tokens, Confluence API tokens, and GitHub personal access tokens. |
| On personnel change | Immediately rotate any tokens associated with the departing team member. |
| On suspected compromise | Immediately revoke and regenerate all tokens. Audit recent pipeline activity for anomalies. |

The pipeline should be tested after every credential rotation to verify connectivity. Consider adding a `--verify-mcp` flag to the setup script that performs a lightweight health check (e.g., listing one build, reading one page, listing one branch) against all configured MCP servers.

### 8.3 Network Security

**Transport Security.** All MCP server communication with upstream services must use TLS 1.2 or later. Certificate validation must not be disabled, even in development environments. If the upstream service uses an internal CA, the CA certificate must be added to the MCP server's trust store rather than bypassing validation.

**Network Segmentation.** In enterprise environments:

- MCP servers should run on the same network segment as the upstream services they connect to, or access them through an approved API gateway.
- MCP servers should not be exposed to the public internet.
- If the AI orchestrator (Windsurf) runs on a developer workstation, the MCP servers run locally on that workstation and communicate via stdio (standard input/output), meaning no network ports are opened.

**Firewall Rules.** When MCP servers communicate with upstream services over the network, the following outbound connections must be allowed:

| MCP Server | Destination | Port |
|------------|-------------|------|
| jenkins-mcp | Jenkins instance | 443 (HTTPS) or 8443 |
| confluence-mcp | Confluence instance | 443 (HTTPS) |
| github-mcp | api.github.com (or GitHub Enterprise hostname) | 443 (HTTPS) |
| nexus-mcp | Nexus instance | 443 (HTTPS) or 8443 |

### 8.4 Audit and Logging

Every MCP tool invocation should be logged with:

- Timestamp (UTC).
- MCP server name and tool name.
- Input parameters (redacting sensitive values such as tokens, passwords, and full file contents above a size threshold).
- Response status (success, error, timeout).
- Pipeline stage and run identifier.

These logs support post-incident review, compliance auditing, and pipeline performance analysis. Logs should be retained according to the organisation's data retention policy (recommended minimum: 90 days).

### 8.5 AI-Generated Code Review

All patches generated by the AI are treated as untrusted code. Safeguards include:

- **Mandatory human review.** PRs are created in draft state and require at least one human approval before merge.
- **Scope limitation.** The pipeline refuses to generate patches that modify CI/CD configuration files (Jenkinsfile, Dockerfile, Kubernetes manifests) without explicit user approval.
- **Diff size limits.** Patches exceeding a configurable threshold (default: 200 lines changed, 5 files modified) trigger mandatory human review even in full MCP mode.
- **Security-sensitive file detection.** Files matching patterns such as `**/auth/**`, `**/security/**`, `**/*secret*`, `**/*credential*` are flagged and require explicit human approval.

---

*This document is maintained alongside the pipeline source code. For the Paste mode workflow guide, see [PASTE-MODE.md](PASTE-MODE.md). For project setup, see the [README](../README.md).*
