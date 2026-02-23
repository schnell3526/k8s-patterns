#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="canary-demo"

# Envoy proxy Pod が Ready であることを確認
echo "=== Waiting for Envoy proxy ==="
until kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=eg \
  --no-headers 2>/dev/null | grep -q .; do
  sleep 2
done
kubectl wait --namespace envoy-gateway-system \
  --for=condition=ready pod \
  --selector=gateway.envoyproxy.io/owning-gateway-name=eg \
  --timeout=120s

# Envoy Service への port-forward をバックグラウンドで起動
echo "=== Starting port-forward to Envoy proxy ==="
ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=canary-demo,gateway.envoyproxy.io/owning-gateway-name=eg \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward "service/${ENVOY_SERVICE}" 8888:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

echo ""
echo "=========================================="
echo "  Step 1: 100% v1 (初期状態)"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/routes/route-v1-only.yaml"
sleep 2
"$SCRIPT_DIR/test-traffic.sh"

echo ""
echo "=========================================="
echo "  Step 2: カナリア 90:10"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/routes/route-canary-10.yaml"
sleep 2
"$SCRIPT_DIR/test-traffic.sh"

echo ""
echo "=========================================="
echo "  Step 3: 50:50"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/routes/route-canary-50.yaml"
sleep 2
"$SCRIPT_DIR/test-traffic.sh"

echo ""
echo "=========================================="
echo "  Step 4: 100% v2 (ロールアウト完了)"
echo "=========================================="
kubectl apply -f "$PROJECT_DIR/manifests/routes/route-full-v2.yaml"
sleep 2
"$SCRIPT_DIR/test-traffic.sh"

echo ""
echo "=== Demo complete ==="
