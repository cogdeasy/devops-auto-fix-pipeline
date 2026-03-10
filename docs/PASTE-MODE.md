# Paste Mode User Guide

This guide explains how to use the AI Auto-Fix Pipeline without MCP servers connected. In Paste mode, you manually paste data from Jenkins, Confluence, and other tools into Windsurf.

## When to Use Paste Mode

- MCP servers are not configured in your Windsurf installation
- You are in an air-gapped or restricted network environment
- You want human oversight at every step
- You are demonstrating the pipeline to stakeholders

## Walkthrough

### Step 1: Provide the Build Failure

Paste your Jenkins console log into Windsurf. Example input:

```
Started by user admin
Building in workspace /var/jenkins/workspace/payment-service
[payment-service] $ /usr/bin/mvn clean install
[INFO] Scanning for projects...
[INFO] --- maven-compiler-plugin:3.11.0:compile ---
[ERROR] COMPILATION ERROR :
[ERROR] /src/main/java/com/hsbc/payment/TransactionService.java:[45,32]
  error: incompatible types: String cannot be converted to BigDecimal
[ERROR] 1 error
[INFO] BUILD FAILURE
[INFO] Total time: 12.456 s
Build step 'Invoke top-level Maven targets' marked build as failure
Finished: FAILURE
```

**What happens next**: The AI extracts the job name, build number, error type, and affected files.

### Step 2: Provide Known Issues (Optional)

When prompted, paste any relevant Confluence content. Example:

```
Known Issue: KI-2024-089
Title: BigDecimal conversion errors after payment-commons 2.3.0 upgrade
Description: The payment-commons library changed the return type of
getAmount() from String to BigDecimal in version 2.3.0. Services that
consume this method need to update their type handling.
Resolution: Change the variable type from String to BigDecimal, or call
.toString() on the return value if String is required.
```

If you have no relevant documentation, type "skip".

### Step 3: Review the Diagnosis

The AI will present a structured diagnosis:

```
Error Type:        compilation
Root Cause:        Type mismatch — String variable receiving BigDecimal value
                   from payment-commons 2.3.0 getAmount() method
Affected Files:    src/main/java/com/hsbc/payment/TransactionService.java:45
Severity:          major
Known Issue:       Yes — KI-2024-089
Suggested Approach: Change variable type from String to BigDecimal
```

**Confirm** the diagnosis is correct before proceeding.

### Step 4: Provide Source Files

When prompted, paste the source file content or confirm the file is accessible locally:

```java
package com.hsbc.payment;

import com.hsbc.commons.PaymentCommons;
import java.math.BigDecimal;

public class TransactionService {
    public void processTransaction(String txnId) {
        PaymentCommons commons = new PaymentCommons();
        String amount = commons.getAmount(txnId);  // Line 45 — ERROR HERE
        // ... rest of method
    }
}
```

### Step 5: Review the Proposed Fix

The AI generates a diff:

```diff
--- a/src/main/java/com/hsbc/payment/TransactionService.java
+++ b/src/main/java/com/hsbc/payment/TransactionService.java
@@ -42,7 +42,7 @@
     public void processTransaction(String txnId) {
         PaymentCommons commons = new PaymentCommons();
-        String amount = commons.getAmount(txnId);
+        BigDecimal amount = commons.getAmount(txnId);
         // ... rest of method
     }
```

**Review** the fix and accept, modify, or reject.

### Step 6: Validate

Run the build locally or on Jenkins:

```bash
mvn clean install
```

Paste the output:

```
[INFO] BUILD SUCCESS
[INFO] Total time: 14.231 s
Tests run: 127, Failures: 0, Errors: 0, Skipped: 3
```

### Step 7: Create the PR

Choose how to create the PR:

1. **Git CLI** — The AI provides commands to run
2. **GitHub CLI** — The AI runs `gh pr create`
3. **Manual copy** — The AI generates the PR body for you to paste into your tool

## Tips

- Paste as much log output as possible — more context helps the AI
- Include timestamps and build numbers when available
- If the first fix attempt fails, the AI will retry with the new error context
- You can run individual stages by referencing `stages/01-detect.md` through `stages/05-pr-create.md`
