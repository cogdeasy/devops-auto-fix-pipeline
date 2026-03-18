# Stage 2: Log Analysis

> **Prompt template**: [`workflows/prompts/analyse-prompt.md`](../../../workflows/prompts/analyse-prompt.md) — used by `pipeline.yaml` for AI-driven root cause analysis at this stage.

## Input
- `build_log`: full console output from Stage 1
- Optional: Confluence known issues content

## Process

### 2.1 Error Classification

Parse the build log to classify the error:

| Pattern | Classification |
|---------|---------------|
| `[ERROR] COMPILATION ERROR` | `compilation` |
| `Tests run: X, Failures: Y` | `test_failure` |
| `Could not resolve dependencies` | `dependency` |
| `Connection refused`, `timeout` | `infrastructure` |
| `kubectl`, `docker` errors | `deployment` |
| Missing env var, invalid config | `configuration` |

### 2.2 Root Cause Identification

1. Find the FIRST error in the log (not cascading errors)
2. Extract the error message, file path, and line number
3. For test failures, extract the test name and assertion details
4. For dependency errors, extract the missing artifact coordinates

### 2.3 Known Issue Search

**MCP mode** (confluence-mcp available):
- Call `search_known_issues` with the error message
- Call `search_pages` with keywords from the error

**Paste mode**:
- Ask user: "Do you have any Confluence documentation or known-issue pages for this error? Paste here or type 'skip'."

### 2.4 Dependency Check (optional)

**MCP mode** (nexus-mcp available):
- If dependency error: call `search_artifacts` to verify artifact availability
- Call `check_dependency_vulnerabilities` for flagged dependencies

**Paste mode**:
- Ask user to confirm dependency versions if relevant

## Output

```
error_type: "compilation" | "test_failure" | "dependency" | "deployment" | "infrastructure" | "configuration" | "unknown"
root_cause: string (description)
affected_files: Array<{ path: string, line?: number }>
severity: "critical" | "major" | "minor"
known_issue: { found: boolean, link?: string, resolution?: string }
suggested_approach: string
```
