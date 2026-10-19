#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/examples/vite-app"
KEY=vite-app
CSV="$ROOT/reports/$KEY.csv"
HEADER='"project_key","analysis_date","metric_key","metric_name","metric_type","value"'

fail() { echo "e2e: FAIL: $*" >&2; exit 1; }

"$ROOT/quality.sh" up
"$ROOT/quality.sh" token "$KEY"
"$ROOT/quality.sh" reference "$ROOT/reference/ci-default.json" "$KEY"
(cd "$APP" && npm ci --no-audit --no-fund && npm run coverage)
"$ROOT/quality.sh" scan "$APP" "$KEY"
"$ROOT/quality.sh" export "$KEY" "$CSV"

value() { awk -F'"?,"?' -v k="$1" '$3 == k { gsub(/"/, "", $6); print $6 }' "$CSV"; }

[[ "$(head -n1 "$CSV")" == "$HEADER" ]] || fail "header is '$(head -n1 "$CSV")'"
grep -q '"sqale_index"' "$CSV" || fail "no sqale_index row"
grep -q '"coverage"' "$CSV" || fail "no coverage row"
coverage="$(value coverage)"
ncloc="$(value ncloc)"
awk -v c="$coverage" 'BEGIN { exit !(c > 0 && c < 100) }' || fail "coverage '$coverage' not in (0, 100)"
awk -v n="$ncloc" 'BEGIN { exit !(n > 0) }' || fail "ncloc '$ncloc' not > 0"

cat "$CSV"
echo "e2e: PASS (coverage=$coverage ncloc=$ncloc)"
