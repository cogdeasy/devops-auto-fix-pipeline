# Validation Retry Prompt

You are re-analysing a build failure after a previous fix attempt did not resolve the issue.

## Original Failure

{{ORIGINAL_BUILD_LOG}}

## Previous Fix Attempt (Attempt {{RETRY_COUNT}} of 3)

### Diagnosis
{{PREVIOUS_DIAGNOSIS}}

### Patch Applied
{{PREVIOUS_PATCH}}

### Validation Result
{{VALIDATION_BUILD_LOG}}

## Instructions

1. Compare the original error with the validation error:
   - Is this the SAME error? The previous fix may have been insufficient.
   - Is this a NEW error? The fix may have introduced a regression.
   - Is this a DIFFERENT manifestation of the same root cause?

2. Determine the revised approach:
   - If same error: the fix was wrong or incomplete — try an alternative approach
   - If new error caused by the fix: revert the problematic part and take a different path
   - If progress was made (fewer errors): refine the existing fix

3. Consider what was already tried and avoid repeating the same approach.

## Output Format

```
relationship_to_original: same_error | new_error | partial_progress
what_went_wrong: <explanation of why the previous fix failed>
revised_diagnosis: <updated root cause analysis>
revised_approach: <new fix strategy, different from previous attempt>
files_to_modify: <list of files>
confidence: high | medium | low
should_escalate: true | false
escalation_reason: <if should_escalate is true>
```
