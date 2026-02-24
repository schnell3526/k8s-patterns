#!/usr/bin/env bash
set -euo pipefail

REQUESTS=50

GREEN='\033[0;32m'
NC='\033[0m'

echo "--- トラフィック分布テスト ($REQUESTS リクエスト) ---"

results=""
for i in $(seq 1 "$REQUESTS"); do
  resp=$(curl -s -H "Host: myapp.example.com" http://localhost:8888/ 2>/dev/null) || resp="error"
  results="${results}${resp}"$'\n'
done

# 集計
v1_count=$(echo "$results" | grep -c "^v1$" || true)
v2_count=$(echo "$results" | grep -c "^v2$" || true)
error_count=$(echo "$results" | grep -c "^error$" || true)

v1_pct=$((v1_count * 100 / REQUESTS))
v2_pct=$((v2_count * 100 / REQUESTS))

echo -e "  v1: ${GREEN}$v1_count${NC} ($v1_pct%)"
echo -e "  v2: ${GREEN}$v2_count${NC} ($v2_pct%)"
if [[ "$error_count" -gt 0 ]]; then
  echo "  error: $error_count"
fi
