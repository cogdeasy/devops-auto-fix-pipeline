# Scenario 01: Java Compilation Failure

## Overview

A Java Maven project (`payment-service`) fails to compile after a transitive dependency
upgrade. The `payment-commons` library was bumped from **2.2.1** to **2.3.0** as part of a
routine dependency refresh. This minor version bump introduced a **breaking API change**:
the `PaymentCommons.getAmount(String txnId)` method now returns `java.math.BigDecimal`
instead of `java.lang.String`.

Two source files reference the old return type and fail at compile time.

## Pipeline Under Test

```
Detect Build Failure --> Analyse Root Cause --> Generate Patch --> Validate Fix --> Create PR
```

| Stage | What the AI Should Do |
|---|---|
| **Detect** | Parse the Jenkins console log, identify 2 compilation errors across 2 files. |
| **Analyse** | Correlate errors with the `payment-commons` 2.3.0 changelog / Confluence known-issue page. Determine that the root cause is a return-type change from `String` to `BigDecimal`. |
| **Generate Patch** | Produce a unified diff that (a) updates variable types from `String` to `BigDecimal`, (b) adds the necessary `import java.math.BigDecimal`, and (c) converts to `String` where downstream APIs still expect it (e.g., `PaymentHelper.processAmount`). |
| **Validate** | Re-run `mvn clean install` on the patched source and confirm zero compilation errors and all existing unit tests pass. |
| **Create PR** | Open a pull request with a clear description referencing KI-2026-089. |

## Artefacts Included

| File | Purpose |
|---|---|
| `jenkins-console.log` | Raw Jenkins build output (job `payment-service-build #247`) |
| `confluence-known-issue.md` | Confluence-style known-issue page KI-2026-089 |
| `source-files/TransactionService.java` | Broken source -- error on line 45 |
| `source-files/PaymentProcessor.java` | Broken source -- error on line 112 |
| `expected-fix.diff` | Reference unified diff the AI should approximate |
| `expected-diagnosis.json` | Reference structured diagnosis output |

## Error Summary

```
[ERROR] /var/jenkins/workspace/payment-service/src/main/java/com/acme/payment/TransactionService.java:[45,24]
    incompatible types: java.math.BigDecimal cannot be converted to java.lang.String

[ERROR] /var/jenkins/workspace/payment-service/src/main/java/com/acme/payment/PaymentProcessor.java:[112,42]
    method processAmount(java.lang.String) in class com.acme.payment.util.PaymentHelper
    cannot be applied to given types;
      required: java.lang.String
      found:    java.math.BigDecimal
      reason: argument mismatch; java.math.BigDecimal cannot be converted to java.lang.String
```

## Expected Behaviour After Fix

- `TransactionService.java` stores the amount in a `BigDecimal` variable and converts
  via `.toPlainString()` only where a `String` representation is needed downstream.
- `PaymentProcessor.java` likewise uses `BigDecimal` for the amount and passes
  `amt.toPlainString()` to `PaymentHelper.processAmount()`.
- All existing unit tests continue to pass with no modification.

## Difficulty

**Easy-Medium** -- straightforward type mismatch, but requires recognising downstream
call-site implications rather than blindly changing one line.
