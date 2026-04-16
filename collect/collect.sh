#!/usr/bin/env bash
# =============================================================================
# ocp-migration-toolkit — collect.sh
# Collects OCP namespace data and GitHub repo metadata for migration analysis.
#
# Usage:
#   ./collect/collect.sh \
#     --namespace f1b263 \
#     --cluster   silver \
#     --repo      bcgov-c/justinrcc \
#     --target    emerald \
#     --output    working/
#     [--envs     dev,test,prod,tools]
#     [--skip-repo]
#
# Prerequisites: oc (logged in), gh (authenticated), jq, yq
# Output:  working/<namespace>/
#            manifest-summary.md     ← AI analysis entry point
#            {env}/workloads.yaml
#            {env}/network-svc-routes.yaml
#            {env}/storage.yaml
#            {env}/networkpolicies.yaml
#            {env}/build-objects.yaml
#            {env}/resource-quotas.yaml
#            {env}/secret-names.txt
#            {env}/configmap-names.txt
#            {env}/image-refs.txt
#            {env}/events.txt
#            repo/                   ← shallow clone of the source repo
# =============================================================================
set -euo pipefail

# ── argument defaults ─────────────────────────────────────────────────────────
NAMESPACE=""
CLUSTER="silver"
REPO=""
TARGET="emerald"
OUTPUT_DIR="working"
ENVS="dev,test,prod,tools"
SKIP_REPO=false
COLLECTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ── colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[collect]${NC} $*"; }
ok()    { echo -e "${GREEN}[collect]${NC} ✓ $*"; }
warn()  { echo -e "${YELLOW}[collect]${NC} ⚠ $*"; }
fatal() { echo -e "${RED}[collect]${NC} ✗ $*" >&2; exit 1; }

# ── parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)  NAMESPACE="$2";  shift 2 ;;
    --cluster)    CLUSTER="$2";    shift 2 ;;
    --repo)       REPO="$2";       shift 2 ;;
    --target)     TARGET="$2";     shift 2 ;;
    --output)     OUTPUT_DIR="$2"; shift 2 ;;
    --envs)       ENVS="$2";       shift 2 ;;
    --skip-repo)  SKIP_REPO=true;  shift   ;;
    *) fatal "Unknown argument: $1" ;;
  esac
done

# ── validate ──────────────────────────────────────────────────────────────────
[[ -z "$NAMESPACE" ]] && fatal "--namespace is required"
[[ -z "$REPO" ]]      && fatal "--repo is required (format: owner/name)"

command -v oc  >/dev/null 2>&1 || fatal "oc CLI not found — install OpenShift CLI and log in"
command -v jq  >/dev/null 2>&1 || fatal "jq not found — brew install jq"
command -v yq  >/dev/null 2>&1 || fatal "yq not found — brew install yq"
if [[ "$SKIP_REPO" == false ]]; then
  command -v gh >/dev/null 2>&1 || fatal "gh CLI not found — brew install gh"
fi

# ── directory setup ───────────────────────────────────────────────────────────
NS_DIR="${OUTPUT_DIR}/${NAMESPACE}"
mkdir -p "${NS_DIR}"

info "Collecting namespace: ${NAMESPACE} | cluster: ${CLUSTER} | target: ${TARGET}"
info "Output: ${NS_DIR}/"
echo ""

# =============================================================================
# FUNCTION: collect_environment
# Collects all OCP resource types for a single namespace (e.g. f1b263-prod)
# =============================================================================
collect_environment() {
  local env_suffix="$1"
  local ns="${NAMESPACE}-${env_suffix}"
  local env_dir="${NS_DIR}/${env_suffix}"

  # Check the namespace exists
  if ! oc get namespace "${ns}" >/dev/null 2>&1; then
    warn "Namespace ${ns} not found — skipping"
    return
  fi

  mkdir -p "${env_dir}"
  info "  Collecting ${ns} ..."

  # Workloads: DC, Deployment, StatefulSet, DaemonSet, CronJob
  oc get dc,deployment,statefulset,daemonset,cronjob \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/workloads.yaml" && ok "    workloads.yaml"

  # Services and Routes
  oc get svc,route \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/network-svc-routes.yaml" && ok "    network-svc-routes.yaml"

  # Persistent storage
  oc get pvc \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/storage.yaml" && ok "    storage.yaml"

  # NetworkPolicies
  oc get networkpolicy \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/networkpolicies.yaml" && ok "    networkpolicies.yaml"

  # Build objects (signals old OCP S2I patterns)
  oc get bc,is \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/build-objects.yaml" && ok "    build-objects.yaml"

  # Resource quotas and LimitRanges
  oc get resourcequota,limitrange \
    -n "${ns}" -o yaml 2>/dev/null \
    > "${env_dir}/resource-quotas.yaml" && ok "    resource-quotas.yaml"

  # Secret NAMES only (never export values — security boundary)
  oc get secret -n "${ns}" \
    --no-headers \
    -o custom-columns='NAME:.metadata.name,TYPE:.type,AGE:.metadata.creationTimestamp' \
    2>/dev/null \
    > "${env_dir}/secret-names.txt" && ok "    secret-names.txt"

  # ConfigMap names
  oc get configmap -n "${ns}" \
    --no-headers 2>/dev/null \
    > "${env_dir}/configmap-names.txt" && ok "    configmap-names.txt"

  # Image references for all running pods
  oc get pods -n "${ns}" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}' \
    2>/dev/null \
    > "${env_dir}/image-refs.txt" && ok "    image-refs.txt"

  # Recent events (errors / warnings)
  oc get events -n "${ns}" \
    --sort-by='.lastTimestamp' 2>/dev/null | tail -50 \
    > "${env_dir}/events.txt" && ok "    events.txt"

  # ServiceAccounts (detect special SCC bindings)
  oc get sa -n "${ns}" \
    --no-headers 2>/dev/null \
    > "${env_dir}/service-accounts.txt" && ok "    service-accounts.txt"

  # RoleBindings (detect elevated permissions)
  oc get rolebinding -n "${ns}" \
    -o custom-columns='NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name' \
    --no-headers 2>/dev/null \
    > "${env_dir}/rolebindings.txt" && ok "    rolebindings.txt"
}

# =============================================================================
# PHASE 1A: OCP namespace collection — all specified environments
# =============================================================================
echo ""
info "=== Phase 1A: OCP Namespace Collection ==="
IFS=',' read -ra ENV_LIST <<< "$ENVS"
for env in "${ENV_LIST[@]}"; do
  collect_environment "$env"
done

# =============================================================================
# PHASE 1B: GitHub repo collection
# =============================================================================
if [[ "$SKIP_REPO" == false ]]; then
  echo ""
  info "=== Phase 1B: GitHub Repo Collection (${REPO}) ==="

  REPO_DIR="${NS_DIR}/repo"
  if [[ -d "${REPO_DIR}/.git" ]]; then
    warn "Repo already cloned at ${REPO_DIR} — skipping clone (use --skip-repo to suppress)"
  else
    info "  Cloning ${REPO} (depth=1) ..."
    gh repo clone "${REPO}" "${REPO_DIR}" -- --depth=1 --quiet
    ok "  Cloned to ${REPO_DIR}"
  fi

  # Extract key metadata
  REPO_META_DIR="${NS_DIR}/repo-meta"
  mkdir -p "${REPO_META_DIR}"

  # Workflow files
  find "${REPO_DIR}/.github/workflows" -name '*.yml' -o -name '*.yaml' 2>/dev/null \
    | sort > "${REPO_META_DIR}/workflow-files.txt"
  ok "  workflow-files.txt"

  # Containerfiles / Dockerfiles
  find "${REPO_DIR}" \( -name 'Containerfile' -o -name 'Dockerfile' \) 2>/dev/null \
    | sort > "${REPO_META_DIR}/containerfiles.txt"
  ok "  containerfiles.txt"

  # Build manifests
  find "${REPO_DIR}" -maxdepth 5 \
    \( -name 'pom.xml' -o -name 'build.gradle' -o -name 'package.json' \
       -o -name '*.csproj' -o -name '*.sln' \) 2>/dev/null \
    | grep -v node_modules | sort > "${REPO_META_DIR}/build-manifests.txt"
  ok "  build-manifests.txt"

  # Helm charts
  find "${REPO_DIR}" \( -name 'Chart.yaml' -o -name 'values.yaml' \) 2>/dev/null \
    | sort > "${REPO_META_DIR}/helm-files.txt"
  ok "  helm-files.txt"

  # Raw k8s YAML (non-Helm)
  find "${REPO_DIR}" -name '*.yaml' -o -name '*.yml' 2>/dev/null \
    | xargs grep -l 'kind: Deployment\|kind: DeploymentConfig\|kind: StatefulSet' 2>/dev/null \
    | grep -v '.git' | sort > "${REPO_META_DIR}/k8s-manifests.txt"
  ok "  k8s-manifests.txt"

  # NetworkPolicy files in repo
  find "${REPO_DIR}" -name '*.yaml' -o -name '*.yml' 2>/dev/null \
    | xargs grep -l 'kind: NetworkPolicy' 2>/dev/null \
    | grep -v '.git' | sort > "${REPO_META_DIR}/networkpolicy-files.txt"
  ok "  networkpolicy-files.txt"

  # Health probe definitions
  grep -rl 'livenessProbe\|readinessProbe\|startupProbe' \
    "${REPO_DIR}" --include='*.yaml' --include='*.yml' 2>/dev/null \
    | grep -v '.git' | sort > "${REPO_META_DIR}/health-probe-files.txt"
  ok "  health-probe-files.txt"

  # Vault / ESO references
  grep -rl 'kind: ExternalSecret\|vault\.' \
    "${REPO_DIR}" --include='*.yaml' --include='*.yml' 2>/dev/null \
    | grep -v '.git' | sort > "${REPO_META_DIR}/vault-eso-files.txt"
  ok "  vault-eso-files.txt"
fi

# =============================================================================
# PHASE 1C: Generate manifest-summary.md — AI analysis entry point
# =============================================================================
echo ""
info "=== Phase 1C: Generating manifest-summary.md ==="

SUMMARY="${NS_DIR}/manifest-summary.md"

cat > "${SUMMARY}" << EOF
# OCP Migration Collection Summary

**Namespace prefix:** \`${NAMESPACE}\`
**Source cluster:** ${CLUSTER}
**Target platform:** ${TARGET}
**Source repo:** ${REPO}
**Collected at:** ${COLLECTED_AT}
**Environments collected:** ${ENVS}

---

## Collection Contents

\`\`\`
$(find "${NS_DIR}" -type f | sort | sed "s|${NS_DIR}/||")
\`\`\`

---

## Workload Summary

EOF

# Append workload counts per environment
for env in "${ENV_LIST[@]}"; do
  ns="${NAMESPACE}-${env}"
  env_dir="${NS_DIR}/${env}"
  if [[ -f "${env_dir}/workloads.yaml" ]]; then
    echo "### ${ns}" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    # Count each workload kind
    for kind in DeploymentConfig Deployment StatefulSet DaemonSet CronJob; do
      count=$(yq "select(.kind == \"${kind}\") | .metadata.name" "${env_dir}/workloads.yaml" 2>/dev/null | grep -c "^" || echo 0)
      if [[ "$count" -gt 0 ]]; then
        echo "${kind}: ${count}" >> "${SUMMARY}"
        yq "select(.kind == \"${kind}\") | .metadata.name" "${env_dir}/workloads.yaml" 2>/dev/null \
          | sed 's/^/  - /' >> "${SUMMARY}"
      fi
    done
    echo "\`\`\`" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
  fi
done

cat >> "${SUMMARY}" << EOF

---

## NetworkPolicy Summary

EOF

for env in "${ENV_LIST[@]}"; do
  env_dir="${NS_DIR}/${env}"
  if [[ -f "${env_dir}/networkpolicies.yaml" ]]; then
    np_count=$(yq 'select(.kind == "NetworkPolicy") | .metadata.name' "${env_dir}/networkpolicies.yaml" 2>/dev/null | grep -c "^" || echo 0)
    echo "### ${NAMESPACE}-${env}: ${np_count} NetworkPolicies" >> "${SUMMARY}"
    if [[ "$np_count" -gt 0 ]]; then
      echo "\`\`\`" >> "${SUMMARY}"
      yq 'select(.kind == "NetworkPolicy") | .metadata.name + " — policyTypes: " + (.spec.policyTypes // [] | join(","))' \
        "${env_dir}/networkpolicies.yaml" 2>/dev/null >> "${SUMMARY}" || true
      echo "\`\`\`" >> "${SUMMARY}"
    fi
    echo "" >> "${SUMMARY}"
  fi
done

cat >> "${SUMMARY}" << EOF

---

## Storage Summary

EOF

for env in "${ENV_LIST[@]}"; do
  env_dir="${NS_DIR}/${env}"
  if [[ -f "${env_dir}/storage.yaml" ]]; then
    echo "### ${NAMESPACE}-${env}" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    yq 'select(.kind == "PersistentVolumeClaim") | .metadata.name + " — " + .spec.storageClassName + " — " + .spec.resources.requests.storage' \
      "${env_dir}/storage.yaml" 2>/dev/null >> "${SUMMARY}" || true
    echo "\`\`\`" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
  fi
done

cat >> "${SUMMARY}" << EOF

---

## Secret Names (values never exported)

EOF

for env in "${ENV_LIST[@]}"; do
  env_dir="${NS_DIR}/${env}"
  if [[ -f "${env_dir}/secret-names.txt" ]]; then
    echo "### ${NAMESPACE}-${env}" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    cat "${env_dir}/secret-names.txt" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
  fi
done

cat >> "${SUMMARY}" << EOF

---

## Image References

EOF

for env in "${ENV_LIST[@]}"; do
  env_dir="${NS_DIR}/${env}"
  if [[ -f "${env_dir}/image-refs.txt" ]]; then
    echo "### ${NAMESPACE}-${env}" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    cat "${env_dir}/image-refs.txt" >> "${SUMMARY}"
    echo "\`\`\`" >> "${SUMMARY}"
    echo "" >> "${SUMMARY}"
  fi
done

cat >> "${SUMMARY}" << EOF

---

## Repo Structure

EOF

if [[ "$SKIP_REPO" == false && -d "${NS_DIR}/repo-meta" ]]; then
  echo "**Workflows:**" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"
  cat "${NS_DIR}/repo-meta/workflow-files.txt" 2>/dev/null >> "${SUMMARY}" || echo "(none found)" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"

  echo "" >> "${SUMMARY}"
  echo "**Containerfiles:**" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"
  cat "${NS_DIR}/repo-meta/containerfiles.txt" 2>/dev/null >> "${SUMMARY}" || echo "(none found)" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"

  echo "" >> "${SUMMARY}"
  echo "**Helm charts:**" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"
  cat "${NS_DIR}/repo-meta/helm-files.txt" 2>/dev/null >> "${SUMMARY}" || echo "(none — raw YAML only)" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"

  echo "" >> "${SUMMARY}"
  echo "**Build manifests:**" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"
  cat "${NS_DIR}/repo-meta/build-manifests.txt" 2>/dev/null >> "${SUMMARY}" || echo "(none found)" >> "${SUMMARY}"
  echo "\`\`\`" >> "${SUMMARY}"
fi

cat >> "${SUMMARY}" << EOF

---

## Next Step

Read this file, then read the individual YAML files listed above to perform the full migration analysis.
Use the \`ocp-migration-analyst\` skill to generate the analysis report.

Invoke from VS Code:
> "Use the ocp-migration-analyst skill to generate the migration analysis for namespace
> ${NAMESPACE} (source: ${CLUSTER}, target: ${TARGET}) using the data in working/${NAMESPACE}/"
EOF

ok "manifest-summary.md generated"

# =============================================================================
# Done
# =============================================================================
echo ""
ok "Collection complete → ${NS_DIR}/"
echo ""
echo "Next step:"
echo "  Open VS Code and invoke the ocp-migration-analyst skill:"
echo "  \"Use the ocp-migration-analyst skill to generate the migration analysis for"
echo "   namespace ${NAMESPACE} using working/${NAMESPACE}/manifest-summary.md\""
