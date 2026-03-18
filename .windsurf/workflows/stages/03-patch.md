# Stage 3: Patch Generation

> **Prompt template**: [`workflows/prompts/patch-prompt.md`](../../../workflows/prompts/patch-prompt.md) — used by `pipeline.yaml` for AI-driven patch generation at this stage.

## Input
- `diagnosis`: structured diagnosis from Stage 2
- Source files (fetched via MCP or provided by user)

## Process

### 3.1 Fetch Source Files

**MCP mode** (github-mcp or gh CLI available):
- For each file in `diagnosis.affected_files`, fetch the current content from the default branch
- Use `gh api repos/{owner}/{repo}/contents/{path}` or `github-mcp`

**Paste mode**:
- Ask user: "Please paste the contents of the following files, or confirm they are accessible locally:"
- List each affected file path

### 3.2 Generate Fix

Based on the error type:

**Compilation errors**:
- Missing import: add the correct import statement
- Type mismatch: correct the type or add a cast
- Undefined variable/method: check for typos, add the missing definition
- Syntax error: fix the syntax

**Test failures**:
- Assertion mismatch: investigate whether the source or the test expectation is wrong
- Prefer fixing the source code unless the test expectation is clearly outdated
- If a new feature changed behaviour, update the test

**Dependency errors**:
- Version conflict: align versions in the build file
- Missing artifact: add the repository or correct the coordinates
- Vulnerability: upgrade to the patched version

**Deployment errors**:
- Docker: fix Dockerfile syntax, base image references, or build args
- Kubernetes: fix manifest YAML, resource limits, image tags
- Configuration: fix environment variables, secrets references

### 3.3 Self-Review

Before presenting the patch:
1. Does the fix address the root cause from the diagnosis?
2. Is this the minimal change necessary?
3. Are there any obvious side effects?
4. Does it follow the project's existing code style?

### 3.4 Present the Patch

Output the fix as a unified diff:
```
--- a/path/to/file.java
+++ b/path/to/file.java
@@ -line,count +line,count @@
 context
-removed line
+added line
 context
```

## Output

```
patch: string (unified diff)
files_changed: string[]
fix_description: string
confidence: "high" | "medium" | "low"
```
