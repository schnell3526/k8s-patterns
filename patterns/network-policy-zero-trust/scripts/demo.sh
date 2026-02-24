#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="zero-trust-demo"

# 既存ポリシーをクリアして初期状態から開始
kubectl delete networkpolicy --all -n "$CLUSTER_NAME" 2>/dev/null || true

echo ""
echo "=========================================="
echo "  Step 1: ポリシー適用前 (全通信 OK)"
echo "=========================================="
"$SCRIPT_DIR/test-connectivity.sh"

echo ""
echo "=========================================="
echo "  Applying NetworkPolicies..."
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/policies/"
echo "NetworkPolicy applied:"
kubectl get networkpolicy -n "$CLUSTER_NAME"

echo ""
echo "=========================================="
echo "  Step 2: ポリシー適用後 (制限あり)"
echo "=========================================="
"$SCRIPT_DIR/test-connectivity.sh"

echo ""
echo "=== Demo complete ==="
