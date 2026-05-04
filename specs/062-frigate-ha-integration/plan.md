# Implementation Plan: Frigate Home Assistant Integration

**Branch**: `062-frigate-ha-integration` | **Date**: 2026-05-03 | **Spec**: [specs/062-frigate-ha-integration/spec.md](spec.md)
**Input**: Feature specification from `/specs/062-frigate-ha-integration/spec.md`

## Summary

The goal is to integrate the Frigate NVR (running on 10.1.10.11:5000) into the Home Assistant (HA) instance managed by the cluster. This involves installing the Frigate custom integration (custom component) into HA, configuring it to connect to the NVR host, and ensuring detection events flow via the existing MQTT broker. The approach will follow the project's GitOps principles, using ArgoCD for configuration and maintenance.

## Technical Context

**Language/Version**: YAML (Kubernetes/Ansible), Home Assistant (latest), Frigate (stable)
**Primary Dependencies**: Frigate Custom Integration, HACS (Home Assistant Community Store), Mosquitto (MQTT)
**Storage**: Longhorn (existing HA PVC)
**Testing**: Manual verification in HA UI, MQTT topic inspection
**Target Platform**: K3s Cluster (Raspberry Pi CM5) + NVR Host (10.1.10.11)
**Project Type**: Home Automation / Infrastructure Integration
**Performance Goals**: < 2s stream latency, instant detection event updates
**Constraints**: Must follow Principle XI (GitOps) for HA configuration; no direct Helm installs for app workloads.
**Scale/Scope**: Single NVR host, multiple camera streams.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Check | Status |
|-----------|-------|--------|
| I. IaC | Is the integration expressed as code (ConfigMaps/manifests)? | [x] |
| IV. Secrets | Are any credentials (NVR admin pass) handled via SealedSecrets? | [x] |
| VI. Encryption | Is the HA -> NVR connection secure (HTTPS where possible)? | [x] |
| XI. GitOps | Is HA configuration managed via ArgoCD (manifests/home-automation)? | [x] |

## Project Structure

### Documentation (this feature)

```text
specs/062-frigate-ha-integration/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output
```

### Source Code (repository root)

```text
manifests/home-automation/
├── prereqs/
│   └── config-extra.yaml       # Updated with Frigate integration fragments
└── home-assistant-values.yaml  # Updated with any new volumes/env vars

roles/home-assistant/
└── templates/
    └── config-extra.yaml.j2    # Template for HA packages
```

**Structure Decision**: Integration will be managed via the `home-automation` namespace manifests, leveraging the existing `packages` pattern in HA for clean configuration fragments.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | N/A |
