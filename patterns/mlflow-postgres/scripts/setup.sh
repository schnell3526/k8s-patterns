#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="mlflow-postgres"
NAMESPACE="mlflow-postgres"

echo "=== Creating kind cluster ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo "=== Creating namespace ==="
kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"

echo "=== Creating Secrets ==="
# --dry-run=client -o yaml | kubectl apply -f - で冪等に Secret を作成
kubectl create secret generic postgres-secret \
  --namespace "$NAMESPACE" \
  --from-literal=POSTGRES_PASSWORD=postgres-password \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic minio-secret \
  --namespace "$NAMESPACE" \
  --from-literal=MINIO_ROOT_USER=minioadmin \
  --from-literal=MINIO_ROOT_PASSWORD=minioadmin123 \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Deploying PostgreSQL ==="
kubectl apply -f "$PROJECT_DIR/manifests/postgres/"

echo "=== Waiting for PostgreSQL to be ready ==="
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=ready pod \
  --selector=app=postgres \
  --timeout=120s

echo "=== Deploying MinIO ==="
kubectl apply -f "$PROJECT_DIR/manifests/minio/deployment.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/minio/service.yaml"

echo "=== Waiting for MinIO to be ready ==="
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=ready pod \
  --selector=app=minio \
  --timeout=120s

echo "=== Creating MLflow bucket ==="
kubectl apply -f "$PROJECT_DIR/manifests/minio/create-bucket-job.yaml"
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=complete job/create-mlflow-bucket \
  --timeout=60s

echo "=== Deploying MLflow ==="
kubectl apply -f "$PROJECT_DIR/manifests/mlflow/"

echo "=== Waiting for MLflow to be ready ==="
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=ready pod \
  --selector=app=mlflow \
  --timeout=180s

echo ""
echo "=== Setup complete ==="
echo "  Cluster: $CLUSTER_NAME"
echo "  Namespace: $NAMESPACE"
echo ""
echo "  MLflow UI:   kubectl port-forward -n $NAMESPACE svc/mlflow 5000:5000"
echo "  MinIO Console: kubectl port-forward -n $NAMESPACE svc/minio 9001:9001"
echo ""
echo "  デモ実行:     ./scripts/demo.sh"
echo "  クリーンアップ: ./scripts/teardown.sh"
