# Feature Specification: Fix static-site ArgoCD Progressing State

**Feature Branch**: `010-fix-argocd-static-site`
**Created**: 2026-04-01
**Status**: Draft
**Input**: User description: "investigate and fix static-site ArgoCD application stuck in Progressing state"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Static-site reaches Healthy/Synced in ArgoCD (Priority: P1)

The static-site application has been stuck in `Progressing` status in ArgoCD, meaning one or more Kubernetes resources are not reaching their desired state. The operator needs to diagnose the root cause and apply a fix so ArgoCD shows the application as `Healthy` and `Synced`.

**Why this priority**: A stuck `Progressing` state means ArgoCD cannot confirm the application is healthy, blocking confidence in the GitOps delivery pipeline and masking real failures.

**Independent Test**: Open ArgoCD UI → static-site application → status shows `Synced` and `Healthy` with no resources stuck in `Progressing`.

**Acceptance Scenarios**:

1. **Given** the static-site application is stuck in `Progressing`, **When** the root cause is identified and the fix is applied, **Then** ArgoCD shows `Healthy` and `Synced` within 5 minutes.
2. **Given** the fix is applied, **When** the services-deploy playbook is re-run, **Then** the application remains `Healthy` and `Synced` (idempotent).
3. **Given** the application is healthy, **When** `https://fleet1.cloud` is opened in a browser, **Then** the static site loads correctly.

---

### Edge Cases

- What if the `Progressing` state is caused by a resource ArgoCD tracks but does not own?
- What if the fix requires changes to the ArgoCD Application definition rather than the manifests?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The root cause of the `Progressing` state MUST be identified before any fix is applied.
- **FR-002**: The fix MUST result in ArgoCD reporting `Healthy` and `Synced` for the static-site application.
- **FR-003**: The static site MUST remain accessible at `https://fleet1.cloud` after the fix.
- **FR-004**: The fix MUST be committed to the repository so it persists across cluster rebuilds.
- **FR-005**: Re-running the services-deploy playbook MUST NOT revert the fix.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: ArgoCD static-site application shows `Healthy` and `Synced` — zero resources stuck in `Progressing`.
- **SC-002**: `https://fleet1.cloud` returns HTTP 200 after the fix.
- **SC-003**: Re-running the full deployment pipeline leaves the application in `Healthy/Synced` state.

## Assumptions

- The static site content is correct and serving — the issue is with ArgoCD health reporting, not missing content.
- Longhorn, Traefik, and cert-manager are all healthy (verified in feature 009).
- The fix will be a code change (manifests or ArgoCD app definition), not a manual kubectl workaround.
