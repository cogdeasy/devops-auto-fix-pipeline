# Failure Classification Prompt

You are classifying a CI/CD build failure to determine the appropriate fix strategy.

## Build Log

{{BUILD_LOG}}

## Instructions

Analyse the build log and classify the failure into exactly one category:

| Category | Indicators |
|----------|-----------|
| `compilation` | Compiler errors, syntax errors, missing symbols, type mismatches |
| `test_failure` | Test assertions failed, test timeout, test setup errors |
| `dependency` | Could not resolve artifact, version conflict, checksum mismatch |
| `deployment` | Docker build failed, K8s apply failed, deployment timeout |
| `infrastructure` | Network timeout, disk full, OOM, agent offline |
| `configuration` | Missing env var, invalid config file, wrong profile |

## Output Format

```
category: compilation | test_failure | dependency | deployment | infrastructure | configuration
confidence: high | medium | low
primary_error: <the first/root error message>
error_location: <file:line if available, otherwise "unknown">
cascading_errors: <count of subsequent errors likely caused by the primary>
summary: <one-sentence description of what went wrong>
```
