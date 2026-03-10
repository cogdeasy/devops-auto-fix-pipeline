# AI-Driven DevOps Auto-Fix Pipeline — Testing & Demo Walkthrough

## About This Document

This guide walks you through end-to-end testing of the AI Auto-Fix Pipeline using realistic scenarios. Each scenario simulates a real CI/CD failure that the pipeline detects, analyses, patches, validates, and resolves via a pull request.

There are **two modes** to test:

| Mode | How it works | Prerequisites |
|------|-------------|---------------|
| **Manual** | You paste Jenkins logs into Windsurf; the AI analyses and generates fixes | Windsurf only |
| **Automated** | MCP servers fetch data from Jenkins/Confluence/GitHub/Nexus directly | MCP servers configured |

**For demo purposes, use Manual mode** — it requires no infrastructure and lets you show the full conversation flow.

---

## Test Scenarios

| # | Scenario | Error Type | Complexity | Time |
|---|----------|-----------|------------|------|
| 1 | Java compilation failure (Maven) | `compilation` | Simple | ~5 min |
| 2 | Node.js test failure (Jest) | `test_failure` | Medium | ~5 min |
| 3 | Dependency vulnerability (Nexus/CVE) | `dependency` | Medium | ~5 min |
| 4 | Kubernetes deployment failure | `deployment` | Complex | ~10 min |

---

## Prerequisites

1. Open the project in Windsurf:
   ```
   Open folder: /Users/deasy/Code/work/devops-auto-fix-pipeline
   ```

2. Verify Windsurf recognises the rules file:
   - Check `.windsurf/rules/devops-pipeline.md` is loaded (look for the rules indicator)

3. For each scenario, you will need:
   - The Jenkins console log (provided in `testing/scenarios/XX/jenkins-console.log`)
   - Optionally, the Confluence known-issue page (provided in some scenarios)
   - The source files (provided in `testing/scenarios/XX/source-files/`)

---

## Walkthrough: Scenario 1 — Java Compilation Failure

This is the recommended first demo. It's straightforward and shows all 5 pipeline stages.

### Background

The `payment-service` team upgraded their `payment-commons` library from 2.2.x to 2.3.0. This changed the return type of `getAmount()` from `String` to `BigDecimal`. Two files now fail to compile.

### Step 1: Start the Manual Workflow

In Windsurf, type:
```
@workflow auto-fix-manual
```

Windsurf will ask: *"Please paste the Jenkins build failure output."*

### Step 2: Paste the Jenkins Log

Open `testing/scenarios/01-java-compilation-failure/jenkins-console.log` and paste the entire contents.

**What to expect**: The AI will extract:
- Job: `payment-service-build`
- Build: #247
- Error type: compilation
- 2 errors in `TransactionService.java` and `PaymentProcessor.java`

### Step 3: Provide Confluence Known Issues (Optional)

When prompted, paste the contents of `testing/scenarios/01-java-compilation-failure/confluence-known-issue.md`.

**What to expect**: The AI will cross-reference the error with known issue KI-2026-089 and use the documented resolution to inform its fix.

### Step 4: Provide Source Files

When prompted, paste the contents of:
- `testing/scenarios/01-java-compilation-failure/source-files/TransactionService.java`
- `testing/scenarios/01-java-compilation-failure/source-files/PaymentProcessor.java`

**What to expect**: The AI generates a unified diff fixing both files.

### Step 5: Compare the Fix

Compare the AI's generated diff with `testing/scenarios/01-java-compilation-failure/expected-fix.diff`.

The fix should:
- Change `String amount` to `BigDecimal amount` in TransactionService.java
- Update type handling in PaymentProcessor.java
- Add `.toString()` calls where String is still needed

### Step 6: Validate

When prompted for validation, respond:
```
Build validated locally — BUILD SUCCESS, all 127 tests pass.
```

### Step 7: Create PR

Choose option 3 (Manual copy-paste) and review the generated PR body.

Compare with `examples/sample-pr-body.md` for expected structure.

### Scoring

Check the AI's output against `testing/scenarios/01-java-compilation-failure/expected-diagnosis.json`:

| Criterion | Pass if... |
|-----------|-----------|
| Error type | Identified as `compilation` |
| Root cause | Mentions `BigDecimal`/`String` type mismatch |
| Affected files | Both `.java` files identified |
| Severity | `major` |
| Known issue | Referenced (if Confluence content was provided) |
| Fix correctness | Diff resolves both compilation errors |
| PR body | Contains root cause, risk assessment, validation |

---

## Walkthrough: Scenario 2 — Node.js Test Failure

### Background

The `user-service` API team refactored their response format from `{ user: {...} }` to `{ data: {...} }`. The source code was updated but 3 Jest tests still reference the old format.

### Steps

1. Start: `@workflow auto-fix-manual`
2. Paste: `testing/scenarios/02-nodejs-test-failure/jenkins-console.log`
3. Skip Confluence (type "skip")
4. Paste source files: `userController.js` and `userController.test.js`
5. Compare fix with `expected-fix.diff`
6. Validate: "All 50 tests pass after applying fix"
7. Review PR body

### Key Differences from Scenario 1

- The AI should identify this as a **test failure**, not compilation
- The fix targets the **test file**, not the source code (the refactor was intentional)
- This tests whether the AI correctly determines which side is "wrong"

---

## Walkthrough: Scenario 3 — Dependency Vulnerability

### Background

The `risk-engine` project can't build because Nexus IQ blocked `log4j-core:2.14.1` due to CVE-2021-44228 (Log4Shell). The fix is to override the transitive dependency version in `pom.xml`.

### Steps

1. Start: `@workflow auto-fix-manual`
2. Paste: `testing/scenarios/03-dependency-vulnerability/jenkins-console.log`
3. When prompted for Confluence/dependency info, paste `nexus-policy-report.json`
4. Paste source file: `pom.xml`
5. Compare fix with `expected-fix.diff`
6. Validate: "Build succeeds with log4j 2.24.3, no policy violations"
7. Review PR body

### Key Differences

- Tests the `dependency` error classification path
- The AI should recommend a `<dependencyManagement>` override, not removing the dependency
- Security context: the AI should mention CVE-2021-44228 in the PR body

---

## Walkthrough: Scenario 4 — Kubernetes Deployment Failure

### Background

The `notification-service` deployment to K8s staging fails with two issues: a wrong image tag (`v2.4.0-rc1` doesn't exist) and misconfigured resource limits (memory request > limit).

### Steps

1. Start: `@workflow auto-fix-manual`
2. Paste: `testing/scenarios/04-k8s-deployment-failure/jenkins-console.log`
3. Skip Confluence
4. Paste source files: `deployment.yaml` and `Dockerfile`
5. Compare fix with `expected-fix.diff`
6. Validate: "Deployment rolled out successfully, pod running"
7. Review PR body

### Key Differences

- Tests the `deployment` error classification
- TWO root causes to identify (image tag + resource limits)
- The AI should fix both issues in a single patch
- This is the most complex scenario — good for advanced demos

---

## Running the Demo Script

For a guided, interactive demo run:

```bash
cd /Users/deasy/Code/work/devops-auto-fix-pipeline
bash testing/demo-runner.sh
```

This script:
1. Lets you select a scenario
2. Displays the Jenkins log to paste
3. Shows expected diagnosis alongside the AI's output
4. Provides the source files to paste
5. Shows the expected fix for comparison

---

## Automated Mode Testing

If MCP servers are configured, test the automated flow:

1. Ensure `scripts/setup-mcp.sh` has been run
2. Verify MCP servers are responding in Windsurf
3. Type: `@workflow auto-fix-full`
4. The pipeline will automatically:
   - Query Jenkins for failed builds
   - Fetch logs and analyse
   - Search Confluence for known issues
   - Generate and apply a patch
   - Trigger a validation build
   - Create a PR

**Note**: Automated mode requires real Jenkins/GitHub/Confluence infrastructure. For demos without infrastructure, use Manual mode with the provided test data.

---

## Evaluation Checklist

Use this checklist after each scenario run:

- [ ] **Detection**: Correct job name, build number, error type extracted
- [ ] **Analysis**: Root cause accurately identified, severity correct
- [ ] **Known issues**: Confluence data used when provided
- [ ] **Patch**: Fix is correct, minimal, and addresses root cause
- [ ] **Validation**: Appropriate validation steps suggested
- [ ] **PR**: Body contains all required sections (root cause, changes, risk, validation)
- [ ] **Mode**: Pipeline correctly operated in manual/automated mode
- [ ] **Retry logic**: If first fix fails, AI retries with new context (test by saying "build failed" at validation step)
- [ ] **Security**: No credentials or secrets in output

---

## Troubleshooting

| Issue | Solution |
|-------|---------|
| Windsurf doesn't recognise `@workflow` | Check `.windsurf/workflows/` directory exists and files have `.md` extension |
| AI doesn't follow the 5-stage flow | Ensure `.windsurf/rules/devops-pipeline.md` is loaded |
| MCP server won't connect | Run `bash scripts/setup-mcp.sh` and check `.env` credentials |
| AI generates wrong fix type | Provide more context — paste the full log, not just the error line |

---

*Document version: 1.0 — March 2026*
*Project: AI-Driven DevOps Auto-Fix Pipeline*
