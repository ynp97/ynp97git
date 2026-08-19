#!/bin/zsh
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: st97_pipeline.sh PAYLOAD_JSON HTML_OUTPUT PDF_OUTPUT QA_DIR" >&2
  exit 64
fi

payload_path="$1"
html_path="$2"
pdf_path="$3"
qa_path="$4"

skill_dir="${0:A:h}"
python_bin="/Users/yoshiakinagumo/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

"$python_bin" "$skill_dir/render_st97.py" "$payload_path" "$html_path"
mkdir -p "${pdf_path:h}"
html_url="file://${html_path:A:gs/ /%20/}"
chrome_profile="$(mktemp -d "${TMPDIR:-/tmp}/st97-chrome.XXXXXX")"
pdf_tmp="${pdf_path}.tmp.pdf"
rm -f "$pdf_tmp"
trap 'rm -rf "$chrome_profile"; rm -f "$pdf_tmp"' EXIT
"$chrome_bin" --headless=new --disable-gpu --no-pdf-header-footer \
  --user-data-dir="$chrome_profile" --print-to-pdf="$pdf_tmp" "$html_url" &
chrome_pid=$!
for _ in {1..60}; do
  [[ -s "$pdf_tmp" ]] && break
  sleep 0.5
done
if kill -0 "$chrome_pid" 2>/dev/null; then
  kill "$chrome_pid" 2>/dev/null || true
  wait "$chrome_pid" 2>/dev/null || true
fi
if [[ ! -s "$pdf_tmp" ]]; then
  echo "PDF generation failed: $pdf_path" >&2
  exit 1
fi
mv -f "$pdf_tmp" "$pdf_path"
"$python_bin" "$skill_dir/qa_st97_pdf.py" "$pdf_path" "$payload_path" "$qa_path"
