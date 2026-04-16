# ocp-migration-toolkit

**A deterministic, AI-augmented platform migration analysis toolkit for BC Government OpenShift projects.**

Produces a structured migration analysis report (markdown + PDF) from any OCP namespace and GitHub
repository. Designed to run as a **GitHub Composite Action**, a **VS Code / Copilot agent workflow**,
or a **standalone CLI** on a developer workstation.

---

## The Problem

Migrating an OCP project from Silver → Emerald (or to AWS / another platform) requires:

1. Comprehensive namespace inventory (workloads, storage, network, secrets, build objects)
2. GitHub repository inspection (CI/CD, Helm charts, Containerfiles, build manifests)
3. Gap analysis against target platform standards (ag-devops, Emerald requirements, NetworkPolicy)
4. A structured migration task list with effort estimates and AI-assist levels
5. A polished PDF report suitable for architecture review or project sponsor sign-off

This toolkit automates steps 1 and 5 deterministically. Steps 2–4 are AI-guided using
the [rl-agents-n-skills](https://github.com/rloisell/rl-agents-n-skills) skill library,
specifically the `ocp-migration-analyst` orchestrator skill.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Inputs: --namespace  --cluster  --repo  --target  --output     │
└──────────────────────┬──────────────────────────────────────────┘
                       │
            ┌──────────▼──────────┐
            │  collect/collect.sh │  ← deterministic: oc + gh CLI
            │  (Phase 1 only)     │
            └──────────┬──────────┘
                       │  working/<namespace>/
                       │    manifest-summary.md
                       │    workloads.yaml
                       │    networkpolicies.yaml
                       │    storage.yaml  ...
                       │
            ┌──────────▼───────────────────────────────────────────┐
            │  AI Analysis  (Copilot / Claude Code)                 │
            │  Skill: ocp-migration-analyst  (orchestrator)         │
            │  Skills: bc-gov-emerald · bc-gov-devops               │
            │          bc-gov-networkpolicy · vault-secrets         │
            │          security-architect · observability           │
            └──────────┬───────────────────────────────────────────┘
                       │  report/<APP>-Migration-Analysis.md
                       │
            ┌──────────▼──────────┐
            │  render/render.sh   │  ← pandoc + Chrome headless
            └──────────┬──────────┘
                       │  report/<APP>-Migration-Analysis.pdf
                       ▼
              GitHub Actions Artifact  /  local file  /  GitHub Pages
```

---

## Quick Start

### Option A — Local (developer workstation)

```bash
# Prerequisites: oc (logged in), gh CLI (authenticated), pandoc, Chrome

git clone https://github.com/rloisell/ocp-migration-toolkit.git
cd ocp-migration-toolkit
git submodule update --init --recursive   # pulls rl-agents-n-skills

# Step 1: Collect namespace data
./collect/collect.sh \
  --namespace f1b263 \
  --cluster silver \
  --repo bcgov-c/justinrcc \
  --target emerald \
  --output working/

# Step 2: AI analysis (VS Code / Copilot)
# Open VS Code, open the working/f1b263/manifest-summary.md file, then:
# "Use the ocp-migration-analyst skill to generate the full migration analysis
#  from working/f1b263/manifest-summary.md, target platform Emerald"

# Step 3: Render PDF
./render/render.sh \
  --input report/JUSTINRCC-Migration-Analysis.md \
  --output report/
```

### Option B — GitHub Actions (any BC Gov project)

Add to any repository's workflow:

```yaml
name: Migration Analysis
on:
  workflow_dispatch:
    inputs:
      namespace:
        description: 'OCP namespace prefix (e.g. f1b263)'
        required: true
      cluster:
        description: 'Source cluster (silver | gold)'
        default: 'silver'

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: rloisell/ocp-migration-toolkit@main
        with:
          namespace: ${{ inputs.namespace }}
          cluster: ${{ inputs.cluster }}
          repo: ${{ github.repository }}
          target: emerald
          oc-token: ${{ secrets.OC_SA_TOKEN }}
          gh-token: ${{ secrets.GITHUB_TOKEN }}
          openai-api-key: ${{ secrets.OPENAI_API_KEY }}  # or GitHub Models token
```

The action produces a GitHub Actions artifact: `migration-analysis-<namespace>.zip`
containing the markdown report and rendered PDF.

### Option C — VS Code Prompt Template

Open any project in VS Code with `rl-agents-n-skills` installed as a submodule at `.github/agents/`.
Then use the prompt template at `.github/prompts/ocp-migration-analysis.prompt.md`:

```
/ocp-migration-analysis namespace=f1b263 cluster=silver repo=bcgov-c/justinrcc target=emerald
```

---

## Service Architecture (Tier 3 — Copilot Extension)

> For BC Gov platform teams who want to offer migration analysis as a shared service.

Deploy this toolkit as a **GitHub Copilot Extension** (GitHub App + Copilot Extensions API)
on Emerald OpenShift. Any BC Gov team can then type in any GitHub Copilot Chat interface:

```
@bc-migrate analyze namespace:f1b263 repo:bcgov-c/justinrcc
```

The extension:
1. Validates the caller has access to the requested namespace
2. Runs `collect.sh` in a Job pod (ephemeral, namespace-scoped)
3. Invokes an LLM via the GitHub Models API to perform the gap analysis
4. Streams the analysis back to the Copilot Chat interface
5. Uploads the PDF as a GitHub release artifact and returns a link

**Deployment:** One `Deployment` + `Service` + `Route` on Emerald, using Vault-stored
secrets for the GitHub App private key and LLM API key. Scales to zero when idle using
KEDA HTTP-based autoscaling.

---

## File Structure

```
ocp-migration-toolkit/
├── README.md                                    # This file
├── CLAUDE.md                                    # Claude Code plugin configuration
├── CODING_STANDARDS.md                          # Coding conventions
├── action.yml                                   # GitHub Composite Action entry point
├── collect/
│   ├── collect.sh                               # Main collection script
│   ├── lib/
│   │   ├── collect-namespace.sh                 # OCP namespace inventory
│   │   ├── collect-repo.sh                      # GitHub repo inspection
│   │   └── summarize.sh                         # Generate manifest-summary.md
│   └── README.md
├── templates/
│   ├── report-sections.md                       # AI-guided section generation prompts
│   ├── style/
│   │   └── report-style.css                     # PDF styling (pandoc + Chrome)
│   └── diagrams/
│       ├── current-state.puml.template          # PlantUML current state template
│       └── target-state.puml.template           # PlantUML target state template
├── render/
│   └── render.sh                                # pandoc + Chrome PDF rendering
├── .github/
│   ├── agents/                                  # git submodule: rl-agents-n-skills
│   ├── workflows/
│   │   ├── on-demand-analysis.yml               # Manual trigger workflow
│   │   └── scheduled-drift-check.yml            # Re-run analysis periodically
│   └── prompts/
│       └── ocp-migration-analysis.prompt.md     # VS Code prompt template
└── examples/
    └── justinrcc/                               # Reference output (JUSTINRCC analysis)
        ├── collect/                             # Sanitized working directory
        └── report/                             # Generated reports (see justinrcc-analysis repo)
```

---

## Inputs

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `--namespace` | ✅ | — | OCP namespace prefix (e.g. `f1b263`) |
| `--cluster` | ✅ | — | Source cluster: `silver`, `gold`, or `emerald` |
| `--repo` | ✅ | — | GitHub repo `owner/name` |
| `--target` | ❌ | `emerald` | Target platform: `emerald`, `aws-ecs`, `aws-eks` |
| `--output` | ❌ | `working/` | Output directory for collected data |
| `--envs` | ❌ | `dev,test,prod,tools` | Comma-separated environment suffixes to collect |
| `--skip-repo` | ❌ | false | Skip GitHub repo collection (when using local clone) |

---

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| `oc` | OCP namespace collection | [OpenShift CLI](https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html) |
| `gh` | GitHub repo inspection | `brew install gh` |
| `pandoc` | Markdown → HTML | `brew install pandoc` |
| Chrome / Chromium | HTML → PDF | System Chrome or `chromium-browser` |
| `jq` | JSON processing | `brew install jq` |
| `yq` | YAML processing | `brew install yq` |

---

## Output: Report Structure

Every generated report follows the 12-section structure:

| Section | Content |
|---------|---------|
| 1. Executive Summary | App purpose, current platform, migration rationale |
| 2. Current State | Services, versions, deployment model, CI/CD, image info |
| 3. Security | Secrets exposure, CVE status, OWASP concerns |
| 4. Observability | Logging, tracing, health probes, Prometheus |
| 5. Gap Analysis | Platform differences table + detailed gaps by category |
| 6. Network Flow Analysis | Flow table with protocols, CIDRs, FWCR requirements |
| 7. Resilience | Replica counts, PDB, StatefulSet quorum, failover |
| 8. Resource Planning | Current limits/requests vs Emerald equivalents |
| 9. Migration Plan | Tasked by prefix: HELM-XX, NP-XX, CI-XX, APP-XX, VAULT-XX |
| 10. Effort Estimation | Hours per task with AI-assist level |
| 11. Diagrams | PlantUML architecture (current state + target state) |
| 12. Appendices | Raw namespace inventory, FWCR templates, Vault paths |

---

## Reference Implementation

The **JUSTINRCC Migration Analysis** (April 2026) is the reference output for this toolkit.
It was produced manually and represents the quality bar for all generated reports.

> Source: `justinrcc-analysis/report/JUSTINRCC-Migration-Analysis.md`  
> Namespace: `f1b263` (Silver, Kamloops DC)  
> Repo: `bcgov-c/justinrcc`  
> Target: Emerald OpenShift  

---

## Contributing

Skill library: [rl-agents-n-skills](https://github.com/rloisell/rl-agents-n-skills) —
PR improvements to the `ocp-migration-analyst` skill there; this toolkit pulls it as a submodule.

---

## License

Apache 2.0 — see [LICENSE](LICENSE).
