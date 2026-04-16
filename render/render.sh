#!/usr/bin/env bash
# =============================================================================
# ocp-migration-toolkit — render.sh
# Renders a migration analysis markdown file to PDF using pandoc + Chrome.
#
# Usage:
#   ./render/render.sh --input report/<APP>-Migration-Analysis.md --output report/
#   ./render/render.sh --input report/<APP>-Migration-Analysis.md --output report/ --open
#
# Prerequisites: pandoc, Google Chrome or Chromium
# =============================================================================
set -euo pipefail

INPUT=""
OUTPUT_DIR="report"
OPEN_PDF=false
CSS_FILE="$(dirname "$0")/../templates/style/report-style.css"
HTML_TMP="/tmp/ocp-migration-report.html"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[render]${NC} $*"; }
ok()    { echo -e "${GREEN}[render]${NC} ✓ $*"; }
fatal() { echo -e "${RED}[render]${NC} ✗ $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)   INPUT="$2";      shift 2 ;;
    --output)  OUTPUT_DIR="$2"; shift 2 ;;
    --css)     CSS_FILE="$2";   shift 2 ;;
    --open)    OPEN_PDF=true;   shift   ;;
    *) fatal "Unknown argument: $1" ;;
  esac
done

[[ -z "$INPUT" ]] && fatal "--input is required"
[[ -f "$INPUT" ]] || fatal "Input file not found: $INPUT"

command -v pandoc >/dev/null 2>&1 || fatal "pandoc not found — brew install pandoc"

# Detect Chrome/Chromium
CHROME=""
for candidate in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "google-chrome-stable" \
  "google-chrome" \
  "chromium-browser" \
  "chromium"; do
  if command -v "$candidate" >/dev/null 2>&1 || [[ -f "$candidate" ]]; then
    CHROME="$candidate"
    break
  fi
done
[[ -z "$CHROME" ]] && fatal "Chrome/Chromium not found — install Google Chrome"

# Derive output PDF path from input filename
INPUT_BASE="$(basename "$INPUT" .md)"
PDF_OUT="${OUTPUT_DIR}/${INPUT_BASE}.pdf"
mkdir -p "${OUTPUT_DIR}"

# Derive report title from filename (replace hyphens with spaces)
TITLE="${INPUT_BASE//-/ }"
TITLE="${TITLE//_/ }"

info "Input:  ${INPUT}"
info "Output: ${PDF_OUT}"
info "CSS:    ${CSS_FILE}"

# ── Step 1: Markdown → HTML (pandoc) ─────────────────────────────────────────
info "Rendering HTML intermediate ..."

# Run pandoc from the input file's directory so relative image paths resolve
INPUT_DIR="$(cd "$(dirname "$INPUT")" && pwd)"
INPUT_FILE="$(basename "$INPUT")"

CSS_ABS="$(cd "$(dirname "$CSS_FILE")" && pwd)/$(basename "$CSS_FILE")"
[[ -f "$CSS_ABS" ]] || warn "CSS file not found at ${CSS_ABS} — PDF will use browser defaults"

(
  cd "${INPUT_DIR}"
  pandoc "${INPUT_FILE}" \
    --from=markdown \
    --to=html5 \
    --standalone \
    $( [[ -f "${CSS_ABS}" ]] && echo "--css=${CSS_ABS} --embed-resources" ) \
    --output="${HTML_TMP}" \
    --metadata title="${TITLE}"
)
ok "HTML intermediate at ${HTML_TMP}"

# ── Step 2: HTML → PDF (Chrome headless) ─────────────────────────────────────
info "Rendering PDF ..."
PDF_ABS="$(cd "${OUTPUT_DIR}" && pwd)/${INPUT_BASE}.pdf"

"${CHROME}" \
  --headless \
  --disable-gpu \
  --no-sandbox \
  --print-to-pdf="${PDF_ABS}" \
  --print-to-pdf-no-header \
  --no-pdf-header-footer \
  "file://${HTML_TMP}" 2>/dev/null

ok "PDF rendered: ${PDF_ABS} ($(du -sh "${PDF_ABS}" | cut -f1))"

# ── Open if requested ─────────────────────────────────────────────────────────
if [[ "$OPEN_PDF" == true ]]; then
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${PDF_ABS}"
  elif command -v open >/dev/null 2>&1; then
    open "${PDF_ABS}"
  fi
fi
