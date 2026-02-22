#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="cilium-hubble-demo"

echo "=== Creating kind cluster (default CNI disabled) ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo "=== Installing Cilium CNI ==="
cilium install --wait

echo "=== Enabling Hubble ==="
cilium hubble enable --ui

echo "=== Waiting for Hubble to be ready ==="
cilium hubble wait

echo "=== Verifying Cilium status ==="
cilium status

echo "=== Deploying applications ==="
kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/apps/"

echo "=== Waiting for applications to be ready ==="
kubectl wait --namespace "$CLUSTER_NAME" \
  --for=condition=ready pod --all \
  --timeout=120s

echo ""
echo "=== Setup complete ==="
echo "  Cluster: $CLUSTER_NAME"
echo "  Namespace: $CLUSTER_NAME"
echo "  デモ実行: ./scripts/demo.sh"
echo "  クリーンアップ: ./scripts/teardown.sh"
