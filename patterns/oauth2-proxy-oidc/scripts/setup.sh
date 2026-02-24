#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="mlflow-oidc"

echo "=== Creating kind cluster ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo "=== Installing ingress-nginx ==="
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "=== Waiting for ingress-nginx to be ready ==="
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

echo "=== Applying manifests ==="
kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"
kubectl apply -f "$PROJECT_DIR/manifests/keycloak/"
kubectl apply -f "$PROJECT_DIR/manifests/mlflow/"

echo "=== Waiting for Keycloak to be ready ==="
kubectl wait --namespace mlflow-oidc \
  --for=condition=ready pod \
  --selector=app=keycloak \
  --timeout=180s

echo "=== Waiting for MLflow to be ready ==="
kubectl wait --namespace mlflow-oidc \
  --for=condition=ready pod \
  --selector=app=mlflow \
  --timeout=120s

echo "=== Configuring Keycloak (realm, client, user) ==="
"$SCRIPT_DIR/configure-keycloak.sh"

echo "=== Applying oauth2-proxy manifests ==="
kubectl apply -f "$PROJECT_DIR/manifests/oauth2-proxy/"

echo "=== Applying ingress ==="
kubectl apply -f "$PROJECT_DIR/manifests/ingress.yaml"

echo "=== Waiting for oauth2-proxy to be ready ==="
kubectl wait --namespace mlflow-oidc \
  --for=condition=ready pod \
  --selector=app=oauth2-proxy \
  --timeout=120s

echo ""
echo "=== Setup complete ==="
echo "  MLflow UI:          http://localhost/"
echo "  Keycloak Admin:     http://localhost/keycloak/admin/"
echo "  Test user:          user / password"
echo "  Keycloak admin:     admin / admin"
