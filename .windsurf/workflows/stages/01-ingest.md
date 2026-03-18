# Stage 01-Ingest: Raw Build Log Pull

> **Part of the `build-log-triage` workflow.** This stage retrieves raw build logs from Jenkins and writes them to the workspace.

---

## Input

```
job_name: string | string[]   # one or more Jenkins job names (or "*" for all)
since: string                  # optional — ISO-8601 timestamp or "last N" (e.g. "last 10")
max_builds: number             # optional — cap on total builds to ingest (default: 20)
```

---

## Process

### 1.1 Identify Target Builds

**MCP mode** (jenkins-mcp available):

1. For each `job_name`, call `get_failed_builds`:
   ```
   jenkins-mcp → get_failed_builds
     jobName: {{job_name}}
     maxResults: {{max_builds}}
   ```
2. If `since` is provided, filter results to only builds after that timestamp
3. Collect the list of `(job_name, build_number, timestamp, status)` tuples

**Paste mode**:

1. Prompt the user:
   > "Please paste your Jenkins build logs. You can paste multiple logs — separate them with `---`. For each log, include the job name and build number if available."
2. Parse the input to extract individual logs with metadata
3. If job name or build number cannot be determined, ask the user

### 1.2 Retrieve Console Logs

**MCP mode**:

For each failed build identified in 1.1:

1. Call `get_build_log`:
   ```
   jenkins-mcp → get_build_log
     jobName: {{job_name}}
     buildNumber: {{build_number}}
   ```
2. Write the full console output to:
   ```
   logs/raw_build_{{job_name}}_{{build_number}}.md
   ```
3. Prepend a metadata header to each file:
   ```markdown
   <!-- build_metadata
   job: {{job_name}}
   build: {{build_number}}
   timestamp: {{failed_at}}
   status: FAILURE
   -->
   ```

**Paste mode**:

1. Split the pasted input on `---` delimiters
2. For each segment, write to `logs/raw_build_{{job_name}}_{{build_number}}.md`
3. If metadata is missing, use sequential numbering: `raw_build_unknown_001.md`

### 1.3 Build Manifest

After all logs are written, create a manifest file at `logs/manifest.json`:

```json
{
  "ingested_at": "ISO-8601 timestamp",
  "mode": "mcp | paste",
  "total_builds": 12,
  "failed_builds": 5,
  "builds": [
    {
      "job": "api-service",
      "build_number": 1039,
      "timestamp": "2025-03-18T10:30:00Z",
      "status": "FAILURE",
      "raw_log_path": "logs/raw_build_api-service_1039.md",
      "log_size_bytes": 245000
    }
  ]
}
```

This manifest allows downstream stages and the model to quickly understand what was ingested without reading every file.

---

## Output

```
manifest_path: string          # path to logs/manifest.json
raw_log_paths: string[]        # list of all raw log file paths
total_builds: number           # total builds examined
failed_builds: number          # builds with FAILURE status
```

---

## Workspace After This Stage

```
logs/
├── manifest.json
├── raw_build_api-service_1039.md
├── raw_build_api-service_1038.md
├── raw_build_auth-module_502.md
└── ...
```

---

## Audit Log Entry

```
Stage 01-ingest complete — ingested {failed_builds} failed build logs
  from {total_builds} total builds across {job_count} jobs.
  Mode: {mcp|paste}. Logs written to logs/.
```
