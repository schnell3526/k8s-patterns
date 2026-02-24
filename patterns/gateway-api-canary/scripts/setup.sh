#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="canary-demo"

echo "=== Creating kind cluster ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo "=== Installing Envoy Gateway ==="
helm install eg oci://docker.io/envoyproxy/gateway-helm \
  --version v1.7.0 \
  -n envoy-gateway-system \
  --create-namespace

echo "=== Waiting for Envoy Gateway controller ==="
kubectl wait deployment/envoy-gateway \
  -n envoy-gateway-system \
  --for=condition=Available \
  --timeout=300s

echo "=== Deploying namespace and Gateway ==="
kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/gateway/gateway.yaml"

echo "=== Deploying applications ==="
kubectl apply -f "$PROJECT_DIR/manifests/apps/"

echo "=== Waiting for applications to be ready ==="
kubectl wait --namespace "$CLUSTER_NAME" \
  --for=condition=ready pod --all \
  --timeout=120s

echo "=== Applying initial route (100% v1) ==="
kubectl apply -f "$PROJECT_DIR/manifests/routes/route-v1-only.yaml"

echo "=== Waiting for Envoy proxy to be ready ==="
echo "Waiting for Envoy proxy pod to be created..."
until kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=eg \
  --no-headers 2>/dev/null | grep -q .; do
  sleep 2
done
kubectl wait --namespace envoy-gateway-system \
  --for=condition=ready pod \
  --selector=gateway.envoyproxy.io/owning-gateway-name=eg \
  --timeout=300s

echo ""
echo "=== Setup complete ==="
echo "  Cluster: $CLUSTER_NAME"
echo "  Namespace: $CLUSTER_NAME"
echo "  デモ実行: ./scripts/demo.sh"
echo "  クリーンアップ: ./scripts/teardown.sh"
