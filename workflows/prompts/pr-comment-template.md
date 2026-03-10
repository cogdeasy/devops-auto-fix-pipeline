# PR Comment Template

Used when the pipeline needs to add a follow-up comment to an existing PR (e.g., after a retry or additional context).

---

## Pipeline Update: {{UPDATE_TYPE}}

**Reference**: {{PIPELINE_REF}}
**Timestamp**: {{TIMESTAMP}}

### {{UPDATE_TITLE}}

{{UPDATE_BODY}}

{{#if RETRY_INFO}}
### Retry Information

- Attempt: {{RETRY_COUNT}}/3
- Previous result: {{PREVIOUS_RESULT}}
- New approach: {{NEW_APPROACH}}
{{/if}}

{{#if VALIDATION_UPDATE}}
### Validation Update

- Build: #{{VALIDATION_BUILD_NUMBER}}
- Result: {{VALIDATION_RESULT}}
- Tests: {{TEST_PASSED}} passed, {{TEST_FAILED}} failed, {{TEST_SKIPPED}} skipped
{{/if}}

{{#if ESCALATION}}
### Escalation Notice

This fix could not be resolved automatically after {{RETRY_COUNT}} attempts.

**Summary of attempts:**
{{ATTEMPT_SUMMARY}}

**Recommended next steps:**
{{RECOMMENDED_ACTIONS}}

Please assign a human reviewer.
{{/if}}

---

*Auto-generated comment by AI Auto-Fix Pipeline*
