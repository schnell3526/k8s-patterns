#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NAMESPACE="egress-demo"

# 既存ポリシーをクリアして初期状態から開始
kubectl delete networkpolicy --all -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "=========================================="
echo "  Step 1: ポリシーなし (全通信 OK)"
echo "=========================================="
"$SCRIPT_DIR/test-egress.sh"

echo ""
echo "=========================================="
echo "  Step 2: default-deny-egress 適用"
echo "  → DNS も外部通信もすべて失敗"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/policies/default-deny-egress.yaml"
echo "Applied: default-deny-egress"
"$SCRIPT_DIR/test-egress.sh"

echo ""
echo "=========================================="
echo "  Step 3: allow-dns 適用"
echo "  → DNS は解決するが HTTPS 接続はタイムアウト"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/policies/allow-dns.yaml"
echo "Applied: allow-dns"
"$SCRIPT_DIR/test-egress.sh"

echo ""
echo "=========================================="
echo "  Step 4: allow-external-https 適用"
echo "  → 外部 HTTPS 通信が成功"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/policies/allow-external-https.yaml"
echo "Applied: allow-external-https"
"$SCRIPT_DIR/test-egress.sh"

echo ""
echo "=== Demo complete ==="
