# Scenario 04: Kubernetes Deployment Failure

## Overview

A microservice deployment to the Kubernetes staging cluster fails because the
deployment manifest references a container image tag that does not exist in the
internal Nexus Docker registry, and the resource limits are misconfigured
(memory request exceeds memory limit). The pod enters `ImagePullBackOff` and
the admission controller rejects the resource specification, causing the
rollout to stall until the progress deadline is exceeded.

## Failure Chain

1. **CI pipeline** builds the Docker image and tags it `v2.4.0` (the tag that
   actually exists in the registry).
2. The `deployment.yaml` manifest, however, references `v2.4.0-rc1` -- a
   release-candidate tag that was never pushed to the registry.
3. Additionally, the manifest sets `resources.requests.memory: 512Mi` while
   `resources.limits.memory` is only `256Mi`. Kubernetes requires that the
   request must not exceed the limit.
4. `kubectl apply` succeeds (the API server accepts the manifest), but the
   kubelet cannot schedule the pod:
   - The image pull fails with `ImagePullBackOff`.
   - The resource validation fails with an `Invalid value` admission error.
5. `kubectl rollout status` times out after 300 seconds and Jenkins marks the
   build as **FAILURE**.

## Error Symptoms

| Signal | Value |
|--------|-------|
| Jenkins job | `notification-service-deploy` #56 |
| kubectl error | `deployment "notification-service" exceeded its progress deadline` |
| Pod event | `Failed to pull image "nexus-docker.internal.hsbc/notification-service:v2.4.0-rc1"` |
| Pod event | `Invalid value for "memory": request 512Mi is greater than limit 256Mi` |
| Pod status | `ImagePullBackOff` / `CrashLoopBackOff` |

## Root Cause

Two independent misconfigurations in `k8s/deployment.yaml`:

1. **Wrong image tag** -- `v2.4.0-rc1` should be `v2.4.0`.
2. **Memory request > limit** -- `requests.memory` (512Mi) exceeds
   `limits.memory` (256Mi). The limit should be raised to at least 512Mi.

## Expected Fix

See `expected-fix.diff` for the unified diff and `expected-diagnosis.json` for
the structured diagnosis output.

## Files

| File | Description |
|------|-------------|
| `jenkins-console.log` | Full Jenkins console output for build #56 |
| `source-files/deployment.yaml` | The broken Kubernetes deployment manifest |
| `source-files/Dockerfile` | Multi-stage Dockerfile for the Java service |
| `expected-fix.diff` | Unified diff that corrects both issues |
| `expected-diagnosis.json` | Structured diagnosis JSON for pipeline validation |
