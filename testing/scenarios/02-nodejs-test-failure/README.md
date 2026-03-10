# Scenario 02: Node.js Jest Test Failure

## Overview

A Node.js Express API project (`user-service`) has failing Jest tests after a
routine refactor. A developer standardised the API response envelope from
`{ user: {...} }` to `{ data: {...} }` across all endpoints in
`userController.js`, but forgot to update the corresponding test file.

## Failure Summary

| Metric | Value |
|--------|-------|
| **CI System** | Jenkins |
| **Job** | `user-service-ci` |
| **Build** | #1034 |
| **Test Runner** | Jest 29.7 |
| **Total Tests** | 50 (5 in affected file) |
| **Passing** | 47 |
| **Failing** | 3 |
| **Root Cause** | Test assertions reference old response key `.body.user` instead of `.body.data` |

## Failing Tests

1. **`GET /api/users/:id should return user data`**
   Asserts `response.body.user` is defined - now `undefined` because the
   controller returns `{ data: user }`.

2. **`GET /api/users/:id should return 404 for missing user`**
   Expects the error payload under `response.body.user` but the controller
   now nests it under `response.body.data`.

3. **`PUT /api/users/:id should update user`**
   Checks `response.body.user.name` equals the updated name - fails because
   `response.body.user` is `undefined`.

## What the AI Auto-Fix Pipeline Should Do

1. **Detect** - Parse the Jenkins console log and identify that this is a Jest
   test failure (exit code 1, `npm test` stage).
2. **Analyse** - Correlate the failing test expectations (`response.body.user`)
   with the actual controller output (`response.body.data`). Recognise that the
   *tests* are stale, not the production code.
3. **Generate Fix** - Produce a patch for `userController.test.js` that updates
   the three failing assertions from `.body.user` to `.body.data` while leaving
   passing tests untouched.
4. **Validate** - Re-run `npm test` and confirm all 50 tests pass.

## Files

| File | Description |
|------|-------------|
| `jenkins-console.log` | Full Jenkins build output including Jest diffs |
| `source-files/userController.js` | The refactored Express controller (correct code) |
| `source-files/userController.test.js` | The stale test file (contains the bug) |
| `expected-fix.diff` | Reference unified diff that resolves all 3 failures |
| `expected-diagnosis.json` | Structured diagnosis the AI should approximate |

## Difficulty

**Easy-Medium** - The mapping between old key and new key is consistent and
mechanical. The main challenge is correctly identifying that the *tests* need
fixing (not the controller) and scoping the change to only the broken
assertions.
