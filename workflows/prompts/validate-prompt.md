# Validation Prompt Template

You are validating a proposed fix for a CI/CD build failure.

## Context

**Original failure:**
{{BUILD_LOG}}

**Diagnosis:**
{{DIAGNOSIS}}

**Proposed patch:**
{{PATCH}}

**Retry attempt:** {{RETRY_COUNT}} of 3

## Validation Instructions

1. Review the patch against the diagnosis. Does it address the root cause?

2. Check for common issues:
   - Missing imports that the new code might need
   - Type mismatches introduced by the change
   - Null safety considerations
   - Thread safety if applicable
   - API compatibility with other consumers

3. If validation build output is available:
   {{VALIDATION_OUTPUT}}
   
   Parse this output to determine:
   - Did the build succeed?
   - Did all tests pass?
   - Are there any new warnings?

4. If the validation FAILED:
   - Identify what went wrong with the fix
   - Determine if it is a new issue or a continuation of the original
   - Suggest a revised approach
   - Include both the original error AND this validation error in the next analysis

5. If the validation PASSED:
   - Confirm the fix is complete
   - Note any follow-up items (e.g., "consider adding a test for this case")
   - Proceed to PR creation

## Output Format

```
validation_status: PASS | FAIL
build_result: SUCCESS | FAILURE | PENDING
test_results: {passed: N, failed: N, skipped: N}
new_issues: [list any new problems]
recommendation: proceed | retry | escalate
notes: [any additional observations]
```
