#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="cilium-hubble-demo"

# Hubble Relay の port-forward をバックグラウンドで起動
echo "=== Starting Hubble port-forward ==="
cilium hubble port-forward &
HUBBLE_PF_PID=$!
trap 'kill $HUBBLE_PF_PID 2>/dev/null || true' EXIT
sleep 2

# 既存ポリシーをクリアして初期状態から開始
kubectl delete networkpolicy --all -n "$CLUSTER_NAME" 2>/dev/null || true

echo ""
echo "=========================================="
echo "  Step 1: ポリシー適用前 (全通信 OK)"
echo "=========================================="
"$SCRIPT_DIR/test-connectivity.sh"

echo ""
echo "--- Hubble: 全フロー確認 ---"
hubble observe --namespace "$CLUSTER_NAME" --since 30s 2>/dev/null || \
  echo "(Hubble からフローを取得できませんでした。hubble status を確認してください)"

echo ""
echo "=========================================="
echo "  Applying NetworkPolicies..."
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/policies/"
echo "NetworkPolicy applied:"
kubectl get networkpolicy -n "$CLUSTER_NAME"
sleep 3  # Cilium のポリシー伝播待ち

echo ""
echo "=========================================="
echo "  Step 2: ポリシー適用後 (制限あり)"
echo "=========================================="
"$SCRIPT_DIR/test-connectivity.sh"

echo ""
echo "--- Hubble: FORWARDED フロー ---"
hubble observe --namespace "$CLUSTER_NAME" --verdict FORWARDED --type policy-verdict --since 30s 2>/dev/null || \
  echo "(Hubble からフローを取得できませんでした)"

echo ""
echo "--- Hubble: DROPPED フロー ---"
hubble observe --namespace "$CLUSTER_NAME" --verdict DROPPED --type policy-verdict --since 30s 2>/dev/null || \
  echo "(Hubble からフローを取得できませんでした)"

echo ""
echo "=========================================="
echo "  Hubble UI"
echo "=========================================="
echo "別ターミナルで以下を実行すると、ブラウザで Hubble UI を確認できる:"
echo ""
echo "  cilium hubble ui"
echo ""
echo "リアルタイムでフローを観察するには、さらに別ターミナルでリクエストを流し続ける:"
echo ""
echo "  kubectl exec -n $CLUSTER_NAME client -- sh -c 'while true; do curl -s --connect-timeout 2 http://frontend; curl -s --connect-timeout 2 http://backend; sleep 1; done'"
echo ""

echo "=== Demo complete ==="
