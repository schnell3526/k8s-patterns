#!/usr/bin/env bash
set -euo pipefail

echo "=== Deleting kind cluster ==="
kind delete cluster --name mlflow-postgres
echo "=== Cluster deleted ==="
