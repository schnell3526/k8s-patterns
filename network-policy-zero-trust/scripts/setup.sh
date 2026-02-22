#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="zero-trust-demo"

echo "=== Creating kind cluster (default CNI disabled) ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo "=== Installing Calico CNI ==="
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/custom-resources.yaml

echo "=== Waiting for Calico to be ready ==="
echo "Waiting for calico-system namespace..."
until kubectl get ns calico-system &>/dev/null; do sleep 2; done
echo "Waiting for calico-node DaemonSet..."
kubectl wait --namespace calico-system \
  --for=condition=ready pod \
  --selector=k8s-app=calico-node \
  --timeout=300s
echo "Waiting for node to be Ready..."
kubectl wait --for=condition=ready node --all --timeout=120s

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
