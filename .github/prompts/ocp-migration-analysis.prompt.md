---
mode: agent
description: Generate a full OCP platform migration analysis report for any namespace and repo.
tools:
  - codebase
  - terminal
  - read_file
  - grep_search
  - file_search
---

# OCP Migration Analysis

Generate a complete migration analysis report for the following project.

**Inputs:**
- Namespace prefix: `${input:namespace:OCP namespace prefix (e.g. f1b263)}`
- Source cluster: `${input:cluster:Source cluster (silver|gold|emerald):silver}`
- Repository: `${input:repo:GitHub repo owner/name (e.g. bcgov-c/myapp)}`
- Target platform: `${input:target:Target platform (emerald|aws-ecs|aws-eks):emerald}`
- Output directory: `${input:outputDir:Report output directory:report}`

---

## Instructions

You are the **OCP Migration Analyst**. Follow the five-phase workflow defined in
[`ocp-migration-analyst/SKILL.md`](../../.github/agents/ocp-migration-analyst/SKILL.md) exactly.

### Phase 1 — Discovery

If `working/${input:namespace}/manifest-summary.md` already exists (from `collect.sh`), read it
and all referenced YAML files. Otherwise run:

```bash
ocp-migration-toolkit/collect/collect.sh \
  --namespace ${input:namespace} \
  --cluster   ${input:cluster} \
  --repo      ${input:repo} \
  --target    ${input:target} \
  --output    working/
```

### Phase 2 — Gap Analysis

Load and apply these skills before performing gap analysis:
- `bc-gov-emerald` — platform labels, AVI annotations, StorageClass, PriorityClass, edge Routes
- `bc-gov-devops` — policy-as-code gate (4 tools), Helm, deployment checklist
- `bc-gov-networkpolicy` — intent API, default-deny egress, CIDR patterns
- `bc-gov-sdn-zones` — Zone B flows, FWCR process
- `vault-secrets` — Vault + ESO migration
- `security-architect` — pod security, CVE, action pinning
- `observability` — health probes, structured logging, tracing

Evaluate all 12 gap categories (G1–G12) from the skill.

### Phase 3 — Network Flow Mapping

Build the complete flow table. For every external destination, determine whether a
CSBC FWCR is required (Zone B services always require one per environment).

### Phase 4 — Report Generation

Follow the 12-section structure from
[`ocp-migration-toolkit/templates/report-sections.md`](../../ocp-migration-toolkit/templates/report-sections.md).

Write the report to: `${input:outputDir}/${input:namespace}-Migration-Analysis.md`

Do not use placeholder text in any section. Every section must contain real analysis
from the collected data. Quality bar: match the JUSTINRCC reference report.

### Phase 5 — PDF Rendering

```bash
ocp-migration-toolkit/render/render.sh \
  --input  ${input:outputDir}/${input:namespace}-Migration-Analysis.md \
  --output ${input:outputDir}/ \
  --open
```

---

## Output

Report: `${input:outputDir}/${input:namespace}-Migration-Analysis.md`
PDF:    `${input:outputDir}/${input:namespace}-Migration-Analysis.pdf`
