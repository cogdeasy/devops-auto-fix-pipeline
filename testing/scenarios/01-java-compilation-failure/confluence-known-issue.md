# Known Issue: KI-2026-089

| Field | Value |
|---|---|
| **ID** | KI-2026-089 |
| **Status** | Active |
| **Severity** | Major |
| **Created** | 2025-06-25 |
| **Author** | Priya Sharma (Platform Engineering) |
| **Last Updated** | 2025-06-26 16:42 UTC |
| **Affected Components** | payment-commons, payment-service, billing-service |

---

## Title

**BigDecimal conversion errors after `payment-commons` 2.3.0 upgrade**

---

## Summary

Version **2.3.0** of the `payment-commons` shared library introduced a **breaking change**
to the `PaymentCommons` public API. The `getAmount(String transactionId)` method return
type was changed from `java.lang.String` to `java.math.BigDecimal` to improve arithmetic
precision and eliminate rounding bugs reported in [FIN-4471] and [FIN-4523].

This is a **binary- and source-incompatible** change. Any service that calls
`PaymentCommons.getAmount()` and assigns the result to a `String` variable, or passes it
to a method expecting `String`, will fail to compile after upgrading.

---

## Root Cause

The `payment-commons` library maintainers changed the following method signature in
version 2.3.0:

```java
// Before (2.2.1 and earlier)
public String getAmount(String transactionId);

// After (2.3.0)
public BigDecimal getAmount(String transactionId);
```

The change was documented in the library's `CHANGELOG.md` under the **Breaking Changes**
section but was not flagged in the automated dependency-update PR description generated
by Renovate Bot.

---

## Affected Services

| Service | Version | Status |
|---|---|---|
| `payment-service` | 4.12.0-SNAPSHOT | **Broken** -- build fails on `main` branch |
| `billing-service` | 3.8.1-SNAPSHOT | **Broken** -- build fails on `main` branch |
| `refund-service` | 2.5.0-SNAPSHOT | Not affected (does not call `getAmount`) |
| `reporting-service` | 1.14.0-SNAPSHOT | Not affected (already uses `BigDecimal` variant via wrapper) |

---

## Symptoms

Services that depend on `payment-commons` >= 2.3.0 will see compilation errors similar to:

```
[ERROR] incompatible types: java.math.BigDecimal cannot be converted to java.lang.String

[ERROR] method processAmount(java.lang.String) in class PaymentHelper
       cannot be applied to given types;
         required: java.lang.String
         found:    java.math.BigDecimal
```

Builds will fail at the `maven-compiler-plugin:compile` phase. The test phase will never
be reached.

---

## Resolution Steps

### Option A: Update calling code (Recommended)

1. Change local variable types from `String` to `BigDecimal` where the return value of
   `getAmount()` is stored.
2. Add `import java.math.BigDecimal;` if not already present.
3. Where the value must be passed as a `String` to downstream methods (e.g.,
   `PaymentHelper.processAmount(String)`), convert explicitly using
   `amount.toPlainString()`. **Do not** use `amount.toString()` -- this can produce
   scientific notation for very large or very small values.
4. Run the full test suite to ensure no behavioural regressions.

```java
// Before
String amount = commons.getAmount(txnId);
PaymentHelper.processAmount(amount);

// After
BigDecimal amount = commons.getAmount(txnId);
PaymentHelper.processAmount(amount.toPlainString());
```

### Option B: Pin to previous version (Temporary workaround)

If an immediate fix is not feasible, pin `payment-commons` to **2.2.1** in the service's
`pom.xml`:

```xml
<dependency>
    <groupId>com.acme.commons</groupId>
    <artifactId>payment-commons</artifactId>
    <version>2.2.1</version>
</dependency>
```

> **Warning:** This is a temporary workaround only. Version 2.2.1 will be deprecated on
> 2025-08-01 and contains known rounding bugs (FIN-4471, FIN-4523).

---

## Related Issues

- **FIN-4471** -- Rounding error in payment amounts over $10,000
- **FIN-4523** -- Floating-point precision loss in currency conversion
- **PLAT-8812** -- Renovate Bot should flag breaking changes in PR descriptions
- **PLAT-8820** -- Add integration tests for payment-commons API compatibility

---

## Contact

For questions, reach out in **#platform-payments** on Slack or contact:

- **Library Owner:** Marcus Liu (`@marcus.liu`)
- **Platform Lead:** Priya Sharma (`@priya.sharma`)
