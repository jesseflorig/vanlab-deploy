# Feature Specification: Static Site with End-to-End TLS

**Feature Branch**: `004-static-site-tls`
**Created**: 2026-03-30
**Status**: Draft
**Input**: User description: "Deploy a default static site at fleet1.cloud with end-to-end HTTPS. Traefik terminates TLS using cert-manager with DNS-01 challenge via Cloudflare API. The Cloudflare tunnel sends HTTPS traffic to Traefik. All requests to www.fleet1.cloud and unrecognised subdomains redirect to fleet1.cloud. Static site content is a placeholder page."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Valid Certificate Issued and Auto-Renewed (Priority: P1)

An operator runs the provisioning playbook and a valid TLS certificate for `fleet1.cloud` is automatically obtained and installed. The certificate is issued by a trusted authority, covers the apex domain, and will renew automatically before expiry without manual intervention.

**Why this priority**: Without a valid certificate, the HTTPS endpoint cannot be trusted by browsers or the Cloudflare tunnel. This is the foundational requirement for all other stories.

**Independent Test**: After provisioning, inspect the certificate presented at the Traefik HTTPS endpoint and confirm it is valid, issued for `fleet1.cloud`, and trusted.

**Acceptance Scenarios**:

1. **Given** a fresh cluster with certificate management not yet installed, **When** the provisioning playbook runs, **Then** a valid certificate for `fleet1.cloud` is present and not expired.
2. **Given** a valid certificate exists, **When** the provisioning playbook runs again, **Then** no changes are made and the certificate is unchanged.
3. **Given** a certificate is approaching expiry, **When** the renewal window is reached, **Then** the certificate is renewed automatically without operator intervention.

---

### User Story 2 - Static Site Reachable at fleet1.cloud over HTTPS (Priority: P2)

A visitor navigates to `https://fleet1.cloud` and receives a placeholder web page. The connection is encrypted end-to-end: from the visitor browser through Cloudflare to Traefik, with no unencrypted hop between Cloudflare and the cluster. The browser shows a valid padlock with no warnings.

**Why this priority**: This is the primary deliverable — a live, secure public-facing site at the apex domain.

**Independent Test**: From any browser on any network, navigate to `https://fleet1.cloud` and confirm the placeholder page loads with a valid padlock and no certificate warnings.

**Acceptance Scenarios**:

1. **Given** the cluster and tunnel are running, **When** a visitor navigates to `https://fleet1.cloud`, **Then** the placeholder page is returned over a fully encrypted connection with no browser warnings.
2. **Given** the services playbook has run, **When** it runs again, **Then** no changes are made.
3. **Given** the cluster is restarted, **When** pods return to Ready state, **Then** `https://fleet1.cloud` becomes reachable again without any manual steps.

---

### User Story 3 - All Non-Apex Requests Redirect to fleet1.cloud (Priority: P3)

A visitor who navigates to `https://www.fleet1.cloud` or any other subdomain (e.g., `https://old.fleet1.cloud`) is automatically redirected to `https://fleet1.cloud` with a permanent redirect. The visitor ends up on the correct URL without any manual URL correction.

**Why this priority**: Prevents SEO fragmentation and user confusion from multiple entry points. Required for a production-quality site but not blocking for the core HTTPS delivery.

**Independent Test**: Navigate to `https://www.fleet1.cloud` from a browser and confirm a permanent redirect to `https://fleet1.cloud` occurs with the placeholder page loading at the final URL.

**Acceptance Scenarios**:

1. **Given** routing is configured, **When** a request arrives for `www.fleet1.cloud`, **Then** it is permanently redirected (301) to `https://fleet1.cloud`.
2. **Given** routing is configured, **When** a request arrives for an unrecognised subdomain (e.g., `foo.fleet1.cloud`), **Then** it is permanently redirected to `https://fleet1.cloud`.
3. **Given** redirects are in place, **When** a redirect is followed, **Then** the visitor lands on the correct placeholder page at `https://fleet1.cloud` in a single hop.

---

### Edge Cases

- What if the DNS-01 challenge fails because the Cloudflare API token has insufficient permissions? The certificate request should fail with a clear error rather than silently retrying indefinitely.
- What if the Cloudflare tunnel is still configured for HTTP when this feature updates Traefik to HTTPS? The tunnel backend URL must be updated atomically to avoid a window where the site is unreachable.
- What if the certificate has not yet been issued when Traefik starts? Traefik should fall back gracefully rather than refusing to serve traffic.
- What if a subdomain redirect loop occurs? Redirect rules must terminate at the apex domain only and not create circular chains.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: A valid TLS certificate for `fleet1.cloud` MUST be automatically obtained from a trusted certificate authority using DNS-based domain validation.
- **FR-002**: The certificate MUST renew automatically before expiry without operator intervention.
- **FR-003**: The Cloudflare tunnel MUST deliver traffic to Traefik over HTTPS.
- **FR-004**: Traefik MUST serve `https://fleet1.cloud` using the automatically obtained certificate.
- **FR-005**: A placeholder static web page MUST be served at `https://fleet1.cloud`.
- **FR-006**: All HTTP requests to `fleet1.cloud` MUST be redirected to HTTPS.
- **FR-007**: All requests to `www.fleet1.cloud` MUST be permanently redirected (301) to `https://fleet1.cloud`.
- **FR-008**: All requests to unrecognised subdomains of `fleet1.cloud` MUST be permanently redirected (301) to `https://fleet1.cloud`.
- **FR-009**: All provisioning steps MUST be idempotent — re-running any playbook MUST produce no changes when the target state is already met.
- **FR-010**: The Cloudflare API credential used for DNS validation MUST be stored as a cluster secret and never committed to the repository.

### Key Entities

- **TLS Certificate**: Issued for `fleet1.cloud`, automatically renewed, stored as a cluster secret; never manually managed after initial issuance.
- **Static Site**: A minimal placeholder HTML page served at the apex domain; content is replaceable in a future feature.
- **Redirect Rule**: A routing rule that catches `www.fleet1.cloud` and all unrecognised subdomains and issues a 301 to `https://fleet1.cloud`.
- **Cloudflare API Credential**: A scoped token used only for DNS record manipulation during certificate validation; stored outside version control.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: `https://fleet1.cloud` loads in a browser with a valid padlock and no certificate warnings from a network outside the home.
- **SC-002**: The certificate presented at `https://fleet1.cloud` is valid, not expired, and issued for the correct domain.
- **SC-003**: Navigating to `https://www.fleet1.cloud` results in a 301 redirect landing on `https://fleet1.cloud` within one redirect hop.
- **SC-004**: Re-running all provisioning playbooks against an already-provisioned cluster produces zero changes.
- **SC-005**: No Cloudflare API credential appears in any committed file in the repository.

## Assumptions

- The K3s cluster from feature 003 is running with Traefik deployed via Helm on NodePort 30080.
- The Cloudflare tunnel from feature 002 is healthy and currently routing to Traefik on port 30080 over HTTP; this feature updates it to HTTPS on port 30443.
- Traefik will be updated to expose the HTTPS entrypoint as NodePort 30443.
- The Cloudflare API credential will be provided by the operator and stored in `group_vars/all.yml` (gitignored) before running the playbook.
- The static site placeholder content (a single HTML page) is sufficient for this feature; content management is out of scope.
- `www.fleet1.cloud` is the only explicitly named redirect subdomain; all other subdomains are caught by a wildcard redirect rule.
- The Cloudflare tunnel backend will be updated from HTTP to HTTPS as part of this feature. Traefik will present the trusted certificate so the tunnel can verify it without disabling certificate verification.
