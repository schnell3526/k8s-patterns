#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="egress-demo"
TIMEOUT=5

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass=0
fail=0

# 現在のポリシー状態を判定
policies=$(kubectl get networkpolicy -n "$NAMESPACE" --no-headers 2>/dev/null | awk '{print $1}')
has_deny=false
has_dns=false
has_https=false

for p in $policies; do
  case "$p" in
    default-deny-egress) has_deny=true ;;
    allow-dns) has_dns=true ;;
    allow-external-https) has_https=true ;;
  esac
done

check_result() {
  local description="$1"
  local actual="$2"     # "ok" or "fail"
  local expected="$3"   # "ok" or "fail"

  printf "  %-50s" "$description"

  if [[ "$actual" == "$expected" ]]; then
    if [[ "$expected" == "ok" ]]; then
      echo -e "${GREEN}PASS${NC} - 期待通り成功"
    else
      echo -e "${GREEN}PASS${NC} - 期待通り失敗"
    fi
    ((pass++)) || true
  else
    if [[ "$expected" == "ok" ]]; then
      echo -e "${RED}FAIL${NC} - 成功するはずが失敗"
    else
      echo -e "${RED}FAIL${NC} - 失敗するはずが成功"
    fi
    ((fail++)) || true
  fi
}

echo "--- Egress テスト ---"

# DNS テスト
dns_result="fail"
if kubectl exec -n "$NAMESPACE" client -- nslookup httpbin.org &>/dev/null; then
  dns_result="ok"
fi

# 期待値: deny なし → ok, deny あり + dns なし → fail, deny あり + dns あり → ok
if [[ "$has_deny" == false ]]; then
  expected_dns="ok"
elif [[ "$has_dns" == true ]]; then
  expected_dns="ok"
else
  expected_dns="fail"
fi
check_result "DNS 解決 (nslookup httpbin.org)" "$dns_result" "$expected_dns"

# 外部 HTTPS テスト (httpbin.org)
https_result="fail"
http_code=$(kubectl exec -n "$NAMESPACE" client -- \
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" "https://httpbin.org/get" 2>/dev/null) || http_code="000"
if [[ "$http_code" == "200" ]]; then
  https_result="ok"
fi

# 期待値: deny なし → ok, deny + dns + https → ok, それ以外 → fail
if [[ "$has_deny" == false ]]; then
  expected_https="ok"
elif [[ "$has_https" == true && "$has_dns" == true ]]; then
  expected_https="ok"
else
  expected_https="fail"
fi
check_result "外部 HTTPS (curl https://httpbin.org/get)" "$https_result" "$expected_https"

# 外部 HTTP テスト (port 80 - 許可されないはず)
http_result="fail"
http_code=$(kubectl exec -n "$NAMESPACE" client -- \
  curl -s -o /dev/null -w '%{http_code}' --connect-timeout "$TIMEOUT" "http://httpbin.org/get" 2>/dev/null) || http_code="000"
if [[ "$http_code" == "200" ]]; then
  http_result="ok"
fi

# 期待値: deny なし → ok, deny あり → fail (port 80 は許可していない)
if [[ "$has_deny" == false ]]; then
  expected_http="ok"
else
  expected_http="fail"
fi
check_result "外部 HTTP (curl http://httpbin.org/get)" "$http_result" "$expected_http"

echo ""
echo -e "結果: ${GREEN}$pass passed${NC}, ${RED}$fail failed${NC}"

if [[ "$fail" -gt 0 ]]; then
  exit 1
fi
