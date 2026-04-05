---
id: 038
title: OPNsense Metrics Collection
branch: 038-opnsense-metrics
---

# Feature Spec: OPNsense Metrics Collection

## Problem Statement

The cluster's Prometheus/Grafana monitoring stack currently covers Kubernetes node metrics,
Longhorn storage, and application logs via Loki, but has no visibility into the OPNsense
router (`10.1.1.1`) that sits at the boundary of all four VLANs. Network throughput,
firewall state counts, interface errors, and system health (CPU/memory/temperature) are
invisible to the operator unless logged into the OPNsense web UI directly.

## Goal

Deploy a Prometheus exporter that scrapes OPNsense metrics via its REST API and makes them
available to the existing kube-prometheus-stack, with a Grafana dashboard for visualization.

## User Stories

### US1 (P1) — Network Interface Metrics
As an operator, I can open Grafana and see per-interface throughput (bytes in/out), packet
rates, and error counts for all OPNsense interfaces (WAN, LAN, VLAN subinterfaces) so that
I can identify bandwidth saturation and misconfigured devices.

**Acceptance criteria:**
- Grafana dashboard shows per-interface Mbps in/out for at least WAN + cluster VLAN
- Metrics update at ≤60s intervals
- Dashboard persists across Grafana restarts (provisioned, not manually imported)

### US2 (P2) — Firewall & Connection State Metrics
As an operator, I can see firewall connection table size, state counts by protocol, and
packets matched/blocked per rule so that I can detect anomalous traffic and rule hits.

**Acceptance criteria:**
- Grafana panels show pf state table count and state limits
- Blocked packet counts visible over time

### US3 (P3) — System Health Metrics
As an operator, I can see OPNsense CPU utilization, memory usage, and (if available) CPU
temperature so that I can detect when the router is resource-constrained.

**Acceptance criteria:**
- CPU % and memory % panels visible in Grafana dashboard
- Alerting threshold configurable via Prometheus rules (optional stretch goal)

## Constraints

- OPNsense is at `10.1.1.1` (management VLAN); cluster pods are on `10.1.20.x`
- Must use OPNsense REST API with API key auth (not SSH)
- API key must be stored as SealedSecret (Principle IV)
- Exporter is an application workload → must be ArgoCD-managed (Principle XI)
- kube-prometheus-stack is infrastructure → Prometheus scrape config changes must be
  made via its Helm values (Ansible-managed), not via ArgoCD
- No new StorageClass dependencies — exporter is stateless
