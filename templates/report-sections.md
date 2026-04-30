# OCP Migration Analysis — AI Section Generation Guide

This file guides the AI through generating each section of the migration analysis report.
Each section includes: **what to include**, **where to find the data**, and **quality checks**.

The AI reads `working/<namespace>/manifest-summary.md` and the individual YAML files,
then generates each section following this guide. The output is a single markdown file:
`report/<APP>-Migration-Analysis.md`.

---

## Document Header

```markdown
# <APP-NAME> — Migration Analysis Report
## OpenShift <SOURCE-CLUSTER> (<NAMESPACE>) → <TARGET-PLATFORM> Platform Migration

**Classification:** Protected B — Internal Use
**Prepared by:** <AUTHOR>, Developer / Architect (BC Gov AG/PSSG) — Co-author & Lead Architect
**AI Analysis by:** GitHub Copilot (Claude Sonnet 4.6) — Technical analysis, gap identification, and documentation
**Date:** <DATE>
**Namespace:** <NAMESPACE> (dev / test / prod / tools) — OpenShift <SOURCE-CLUSTER>, <DC>
**Repository:** https://github.com/<OWNER>/<REPO>
**Analysis scope:** Read-only — no changes made to repo, deployments, or environments.
```

---

## Section 1 — Executive Summary

**Generate from:** `workloads.yaml`, `network-svc-routes.yaml`, `image-refs.txt`, repo README, pom.xml / package.json

**Must include:**
- What the application does in one paragraph (purpose, users, data handled)
- The message/data pipeline described end-to-end (source → processing → destination)
- Number of microservices, tech stack (language/framework/version), last deployed version
- Current platform and why it is being migrated (not "Silver is end-of-life" — explain the specific limitation: Zone B connectivity, security posture, Emerald features, etc.)
- Count of migration tasks by category (high-level summary table)

**Quality check:** A non-technical reader should understand what this app does and why it is being migrated after reading this section.

---

## Section 2 — Current State — Technical Overview

**Generate from:** `workloads.yaml`, `storage.yaml`, `build-objects.yaml`, `image-refs.txt`, `network-svc-routes.yaml`, repo Containerfiles and build manifests

**Must include:**
- Table: each workload (name, kind, replicas, image, last built/deployed)
- For each workload: environment variables referenced, volume mounts, resource requests/limits
- Supporting infrastructure: message brokers, caches, databases, SMTP (kind, version, storage)
- Current deployment model: DeploymentConfig vs Deployment, image streams, build triggers
- GitHub Actions CI/CD summary: what triggers build, what registry is used, what deploys it
- Image stream / registry origin: is it OCP internal registry, Artifactory, or Docker Hub?
- Detect `SierraSystems/reusable-workflows` or similar third-party workflow dependencies

**Table example:**

| Service | Kind | Replicas | Runtime | Version | Image registry |
|---------|------|----------|---------|---------|----------------|
| jrcc-receiver | DeploymentConfig | 1 | Java 17 | v2.0.3 | image-registry.openshift-image-registry.svc |

---

## Section 3 — Security and Programmatic Concerns

**Generate from:** `secret-names.txt`, `image-refs.txt`, workflow files, Containerfiles, `rolebindings.txt`

**Must include:**
- Secrets inventory: count of plain Secrets, classify by purpose (DB credentials, SSH keys, API tokens, TLS certs), flag any that look hardcoded in ConfigMaps or workflow env vars
- Image CVE posture: base image (from Containerfile), known CVE status if detectable, Trivy scan status from CI
- GitHub Actions security: are actions pinned to SHA digests? Are third-party actions used?
- Pod security: is `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem` set?
- ServiceAccount bindings: any elevated SCCs (anyuid, privileged)?
- Rotation procedures: SSH keys, API tokens — are they documented?

**Flag as 🔴 CRITICAL:** Hardcoded credentials in YAML, unpinned third-party actions, `privileged: true`

---

## Section 4 — Distributed Tracing and Observability

**Generate from:** pom.xml / build.gradle / package.json (for tracing libraries), Containerfiles, workflow files

**Must include:**
- Logging framework: what library, is it structured JSON? (Logback, log4j, Serilog, Winston, etc.)
- Tracing SDK: Spring Cloud Sleuth (deprecated in Boot 3.x), OpenTelemetry, Jaeger client?
- Health probes: are `/health/live` and `/health/ready` endpoints configured? Wired as k8s probes?
- Prometheus metrics: any `/actuator/prometheus` or `/metrics` endpoint? Pod annotations set?
- Splunk integration: HEC endpoint, token source, log forwarding mechanism
- Gap note if Spring Cloud Sleuth is present: must migrate to Micrometer Tracing + OTel on Boot 3.x

---

## Section 5 — Gap Analysis — <SOURCE> to <TARGET> Migration

**Generate from:** all collected YAML files + knowledge from `bc-gov-emerald`, `bc-gov-devops`, `bc-gov-networkpolicy` skills

**Must include:**

### 5.1 Platform Differences Summary Table

| Dimension | <Source> | <Target> | Migration Gap |
|-----------|----------|----------|---------------|

Dimensions to always include: Network enforcement, Routing, Pod labels, Storage class,
Deployment API, Image registry, Secrets management, Helm charts, CI/CD triggers,
Health checks, Console access.

### 5.2 Detailed Gaps by Category

Group gaps into subsections: Networking, CI/CD, Application Code, Secrets Management, Data Migration.
Use this severity scale: ⛔ CRITICAL | ⚠ REQUIRED | ℹ RECOMMENDED.

**Never omit a gap category** — if no gaps are found, say "No gaps identified in this category."

---

## Section 6 — Network Flow Analysis

**Generate from:** `network-svc-routes.yaml`, `networkpolicies.yaml`, workload env vars (for external endpoints), `bc-gov-sdn-zones` skill

**Must include:**

### Flow table — one row per distinct traffic flow

| Source Service | Destination | Protocol | Port | External? | Zone | FWCR Required? | NP Exists? |
|----------------|-------------|----------|------|-----------|------|----------------|------------|

- Classify each destination as Internal (same namespace), Cross-namespace, Zone B (external AG mid-tier), or Internet
- For Zone B destinations: name the CSBC FWCR process, note dev/test/prod require separate FWCRs
- Flag DNS egress (UDP/TCP 53) — always required as first NP on Emerald
- For SMTP: note if direct CIDR or requires proxy

### 6.2 FWCR Requirements Summary

List each Zone B/external endpoint that requires a CSBC Firewall Change Request, with:
- Protocol / port
- Source CIDR (Emerald namespace CIDR — TBD at onboarding)
- Destination (service name, confirmed or TBD)
- Environment (dev / test / prod — each needs separate FWCR)

---

## Section 7 — Resilience and Availability Analysis

**Generate from:** `workloads.yaml`, `storage.yaml`, `resource-quotas.yaml`

**Must include:**
- Current replica counts per service — single points of failure?
- StatefulSet quorum: for clustered services (RabbitMQ, etc.), what is the quorum size?
- PodDisruptionBudget: exists? If not, note risk during node drain
- PVC redundancy: is storage replicated? `netapp-file-standard` vs `netapp-block-standard`
- Failover path for the critical pipeline: what happens if receiver pod crashes mid-poll?
- Resource limits: are limits set? Too low (OOMKill risk)? Too high (noisy neighbour)?

---

## Section 8 — Resource and Capacity Planning

**Generate from:** `workloads.yaml` (resources section), `resource-quotas.yaml`

**Must include:**
- Table: each workload × current requests/limits (CPU + memory)
- Namespace quota: current quota vs actual usage
- Emerald namespace sizing recommendation: what quota to request
- Note if any workload has no resource limits set (Polaris will fail this)

---

## Section 9 — Migration Plan and Task List

**Generate from:** all gap analysis findings, using task numbering convention

**Task prefix convention:**

| Prefix | Category |
|--------|----------|
| `ARCH-XX` | Architecture decisions — FWCRs, external connectivity, platform onboarding |
| `HELM-XX` | Helm chart authoring |
| `NP-XX` | NetworkPolicy suite |
| `CI-XX` | CI/CD pipeline updates |
| `APP-XX` | Application code changes |
| `VAULT-XX` | Secrets migration to Vault |
| `DATA-XX` | PVC / data migration |

**Phase ordering:**
1. Phase 0 — Pre-conditions (namespace provisioning, FWCR requests, Vault namespace)
2. Phase 1 — Infrastructure (Helm charts, NetworkPolicies, CI/CD, PriorityClass)
3. Phase 2 — Application (health probes, security contexts, secrets migration, observability)
4. Phase 3 — Validation (policy gate, integration tests, load testing)
5. Phase 4 — Cutover (DNS switch, Silver namespace freeze, data migration, smoke test)
6. Phase 5 — Decommission (Silver namespace cleanup)

**AI-assist level:**
- 🤖 Copilot — fully generated, no project context required
- 🤝 Copilot+Dev — Copilot drafts, developer supplies project-specific values
- 💼 Admin — GitHub Secrets, Vault namespace, CSBC FWCR (manual admin action)
- 🔎 Investigation — must gather more info before task can begin

---

## Section 10 — Effort Estimation

**Generate from:** migration plan task list

**Table format:**

| Task ID | Description | AI Assist | Estimated Hours | Notes |
|---------|-------------|-----------|-----------------|-------|

**Totals by category and by phase.**
**Include a note on overall AI leverage** — what percentage of total hours is AI-assisted vs manual.

---

## Section 11 — Diagrams

**Generate from:** collected workloads, services, external endpoints

**Always include:**

### 11.1 Current State Architecture

PlantUML component diagram showing:
- All workloads as components
- All services and routes
- External dependencies (Zone B, internet)
- Storage volumes
- Message queues / caches

Use this style header:
```
!theme plain
skinparam backgroundColor #FFFFFF
skinparam defaultFontName "Helvetica Neue"
left to right direction
```

### 11.2 Target State Architecture

Same diagram but showing Emerald equivalents:
- Deployments (not DCs)
- AVI-annotated Routes
- Emerald NetworkPolicies
- Vault-sourced secrets
- Artifactory images
- ArgoCD GitOps

Save as:
- `diagrams/plantuml/<app>-current-state.puml`
- `diagrams/plantuml/<app>-target-state.puml`
- `diagrams/plantuml/png/<app>-current-state.png`
- `diagrams/plantuml/png/<app>-target-state.png`

Render: `/opt/homebrew/bin/plantuml -tpng -o diagrams/plantuml/png diagrams/plantuml/<file>.puml`

---

## Section 12 — Appendices

**Must include:**

### Appendix A — Full Namespace Inventory
Table listing every resource across all environments. Generated from workloads.yaml.

### Appendix B — Skills Reference
Table: which rl-agents-n-skills skills apply to which tasks in this migration.

### Appendix C — FWCR Request Templates
For each Zone B egress identified in Section 6, provide a CSBC FWCR request template:
- Application name
- Source CIDR (Emerald namespace — TBD)
- Destination host / IP
- Protocol and port
- Business justification

### Appendix D — Vault Path Structure
Proposed Vault path structure for all secrets identified in Section 3.

### Appendix E — <SOURCE> Namespace Decommission Plan
Steps to decommission the source namespace after successful migration. Do NOT describe
the source platform as "end-of-life" — it may still be used by other projects.
Frame as "after <APP> leaves <source platform>".

---

## Quality Gate — Before Saving the Report

Before writing the final markdown file, verify:

- [ ] Every section is present (1–12) — no placeholder headings
- [ ] All workload names from `manifest-summary.md` appear in the report
- [ ] All external endpoints from image refs and env vars are in the flow table
- [ ] All gaps map to at least one task in Section 9
- [ ] All tasks in Section 9 appear in effort estimation (Section 10)
- [ ] CRITICAL gaps are flagged ⛔ in Section 5
- [ ] FWCR requirements are listed for every Zone B destination
- [ ] Diagram files are referenced with correct relative paths
- [ ] Document header has correct namespace, cluster, repo, and date

---

## Authoritative BC Government standards to cite

When generating each section, cite the relevant OCIO standard(s) inline so the
report can be defended in architecture review. Use these mappings (full control
text lives in the corresponding skill):

| Section | Standard / Skill | What to cite |
| --- | --- | --- |
| 3 — Security & Programmatic Concerns | [Security Standard for Application and Web Development and Deployment v1.3 (2015-04)](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/security_standard_application_web_development_deployment.pdf) \u2014 via `security-architect` agent | \u00a71.2 vulnerability mgmt; \u00a71.3 prod/non-prod segregation; no creds in source; 45-day dormant accounts; \u00a72.1 code review; \u00a72.2 secure coding; \u00a73.1 public-facing WAF |
| 3 — Security & Programmatic Concerns | [Guidelines on the Use of Open Source Software (R1.0, 2012-04)](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/guidelines_on_the_use_of_open_source_software_2016.pdf) | OSS dependency due diligence \u2014 license review, business value + TCO assessment |
| 3 — Security & Programmatic Concerns | `bc-gov-database-security` skill \u2014 [Database Security Standard v1.0 (2018-04)](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/database_security_standards_for_information_protection_-_2018-04_version_1.pdf) | If the application connects to a database: data classification, encryption-in-transit, separation of duties, no production data in test, audit |
| 5.2 — Detailed Gaps (CI/CD) | [Development Standards for Information Systems and Services v3.0 \u00a72.1](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/development_standards_for_information_systems_and_services.pdf) \u2014 via `github-workflow` agent | Source code in github.com/bcgov; 2FA on repo admins; approved licenses |
| 5.2 — Detailed Gaps (Application Code) | `bc-gov-rest-api` skill \u2014 [REST API Development Standard (2015-04)](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/api-standard.pdf) | If the workload exposes HTTP endpoints: 8 mandates (REST, verb correctness, single-resource URLs, metadata + ISO 8601 + OGL-BC, error messaging, version) |
| 6 — Network Flow Analysis | `bc-gov-sdn-zones`, `bc-gov-network-architect` \u2014 [IMIT 6.13 Zones](https://intranet.gov.bc.ca/assets/intranet/mtics/ocio/es/enterprise-services-division/information-security-branch/information-security-standards-and-guidelines/imit_613_network_security_zones_standard_v5.pdf), [IMIT 6.28 Comms](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/09_-_communications_security_standard_v10.pdf), [IMIT 5.08 N2N](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/imit_508_network_to_network_connectivity_standard.pdf) + [N2N Tech & Product](https://www2.gov.bc.ca/assets/gov/government/services-for-government-and-broader-public-sector/information-technology-services/standards-files/network_to_network_connectivity_technical_and_product_standard.pdf) | Zone classification, default-deny NetworkPolicy, third-party gateway requirements |
| 9 — Migration Plan | All applicable standards above | Each task that closes a standards gap should reference the standard \u00a7 in its description |

**Rule:** When a finding maps to a specific OCIO standard, name the standard in
the finding text (e.g. *"AppSec Standard v1.3 \u00a71.3"*) so reviewers can verify
the citation against the source PDF.
