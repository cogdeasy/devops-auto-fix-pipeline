# Stage 1: Failure Detection

## Automated Mode (jenkins-mcp available)

1. Call `get_failed_builds` with parameters:
   - `jobName`: the target Jenkins job (or iterate all jobs if not specified)
   - `maxResults`: 5
2. Parse the response to get failed build details
3. For the most recent failure, call `get_build_log`:
   - `jobName`: from the failed build
   - `buildNumber`: from the failed build
4. Return the build log and metadata

## Manual Mode (no jenkins-mcp)

1. Prompt the user:
   > "Please paste the Jenkins build failure output. This can be the console log, a failure notification, or a description of the error."
2. Parse the pasted content to extract:
   - Job name (look for patterns like "Building project-name")
   - Build number (look for "#123" patterns)
   - Error messages
   - Timestamps
3. If the job name or build number cannot be determined, ask the user to provide them

## Output

```
job_name: string
build_number: number
build_log: string (full console output)
failure_timestamp: string
failure_type: "build" | "test" | "deploy" | "unknown"
```
