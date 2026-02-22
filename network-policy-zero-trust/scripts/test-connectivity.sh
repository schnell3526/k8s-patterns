#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="zero-trust-demo"
TIMEOUT=3

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass=0
fail=0

test_connection() {
  local from="$1"
  local to="$2"
  local expected="$3"  # "allow" or "deny"
  local description="$4"

  printf "  %-45s" "$description"

  if [[ "$from" == "client" ]]; then
    result=$(kubectl exec -n "$NAMESPACE" "$from" -- \
      curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" "http://$to" 2>/dev/null) || result="000"
  else
    pod=$(kubectl get pod -n "$NAMESPACE" -l "app=$from" -o jsonpath='{.items[0].metadata.name}')
    result=$(kubectl exec -n "$NAMESPACE" "$pod" -- \
      curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" "http://$to" 2>/dev/null) || result="000"
  fi

  if [[ "$expected" == "allow" ]]; then
    if [[ "$result" == "200" ]]; then
      echo -e "${GREEN}PASS${NC} (HTTP $result) - 期待通り許可"
      ((pass++)) || true
    else
      echo -e "${RED}FAIL${NC} (HTTP $result) - 許可されるべき通信がブロック"
      ((fail++)) || true
    fi
  else
    if [[ "$result" == "000" ]]; then
      echo -e "${GREEN}PASS${NC} (timeout) - 期待通り拒否"
      ((pass++)) || true
    else
      echo -e "${RED}FAIL${NC} (HTTP $result) - 拒否されるべき通信が許可"
      ((fail++)) || true
    fi
  fi
}

echo "--- 通信テスト ---"

# NetworkPolicy の有無を確認して期待値を決定
policy_count=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ "$policy_count" -eq 0 ]]; then
  echo "(NetworkPolicy なし: 全通信が許可されるはず)"
  test_connection "client"   "frontend" "allow" "client → frontend (port 80)"
  test_connection "client"   "backend"  "allow" "client → backend (port 80)"
  test_connection "frontend" "backend"  "allow" "frontend → backend (port 80)"
else
  echo "(NetworkPolicy あり: 制限された通信のみ許可)"
  test_connection "client"   "frontend" "allow" "client → frontend (port 80)"
  test_connection "client"   "backend"  "deny"  "client → backend (port 80)"
  test_connection "frontend" "backend"  "allow" "frontend → backend (port 80)"
fi

echo ""
echo -e "結果: ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}"

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
