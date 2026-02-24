#!/usr/bin/env bash
set -euo pipefail

echo "=== Deleting kind cluster ==="
kind delete cluster --name cilium-hubble-demo
echo "=== Cluster deleted ==="
