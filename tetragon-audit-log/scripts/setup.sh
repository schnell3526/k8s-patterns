#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLUSTER_NAME="tetragon-audit-demo"
NAMESPACE="tetragon-audit-demo"

echo "=== Creating kind cluster ==="
kind create cluster --config "$PROJECT_DIR/cluster/kind-config.yaml"

echo ""
echo "=== Adding Helm repositories ==="
helm repo add cilium https://helm.cilium.io
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

echo ""
echo "=== Installing Tetragon (kube-system) ==="
helm install tetragon cilium/tetragon \
  --version 1.3.0 \
  --namespace kube-system

echo "Waiting for Tetragon DaemonSet..."
kubectl rollout status daemonset/tetragon -n kube-system --timeout=300s

echo ""
echo "=== Waiting for Tetragon CRDs ==="
echo "Waiting for TracingPolicy CRD to be registered..."
until kubectl get crd tracingpolicies.cilium.io >/dev/null 2>&1; do
  sleep 2
done
kubectl wait crd/tracingpolicies.cilium.io --for=condition=Established --timeout=60s
kubectl wait crd/tracingpoliciesnamespaced.cilium.io --for=condition=Established --timeout=60s

echo ""
echo "=== Creating namespace ==="
kubectl apply -f "$PROJECT_DIR/manifests/namespace.yaml"

echo ""
echo "=== Applying TracingPolicy ==="
kubectl apply -f "$PROJECT_DIR/manifests/policies/"

echo ""
echo "=== Installing Loki ==="
helm install loki grafana/loki \
  --version 6.7.3 \
  --namespace "$NAMESPACE" \
  --values - <<'EOF'
deploymentMode: SingleBinary
loki:
  auth_enabled: false
  commonConfig:
    replication_factor: 1
  storage:
    type: filesystem
  schemaConfig:
    configs:
      - from: "2024-01-01"
        store: tsdb
        object_store: filesystem
        schema: v13
        index:
          prefix: index_
          period: 24h
singleBinary:
  replicas: 1
  persistence:
    size: 2Gi
read:
  replicas: 0
write:
  replicas: 0
backend:
  replicas: 0
chunksCache:
  enabled: false
resultsCache:
  enabled: false
gateway:
  enabled: false
EOF

echo "Waiting for Loki..."
kubectl wait pod \
  --namespace "$NAMESPACE" \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=loki \
  --timeout=300s

echo ""
echo "=== Applying Grafana ConfigMaps (datasource + dashboard) ==="
kubectl apply -f "$PROJECT_DIR/manifests/grafana/"

echo ""
echo "=== Installing Fluent Bit ==="
helm install fluent-bit fluent/fluent-bit \
  --version 0.49.0 \
  --namespace "$NAMESPACE" \
  --values - <<'EOF'
securityContext:
  runAsUser: 0
config:
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/run/cilium/tetragon/tetragon.log
        Tag               tetragon.*
        Parser            json
        Refresh_Interval  5
        Read_from_Head    true
  filters: |
    [FILTER]
        Name              modify
        Match             tetragon.*
        Add               job tetragon
  outputs: |
    [OUTPUT]
        Name              loki
        Match             tetragon.*
        Host              loki.tetragon-audit-demo.svc.cluster.local
        Port              3100
        Labels            job=tetragon
        Auto_Kubernetes_Labels off
  customParsers: ""
extraVolumes:
  - name: tetragon-log
    hostPath:
      path: /var/run/cilium/tetragon
      type: DirectoryOrCreate
extraVolumeMounts:
  - name: tetragon-log
    mountPath: /var/run/cilium/tetragon
    readOnly: true
EOF

echo "Waiting for Fluent Bit..."
kubectl rollout status daemonset/fluent-bit -n "$NAMESPACE" --timeout=300s

echo ""
echo "=== Installing Grafana ==="
helm install grafana grafana/grafana \
  --version 8.8.2 \
  --namespace "$NAMESPACE" \
  --values - <<'EOF'
adminPassword: admin
sidecar:
  datasources:
    enabled: true
    label: grafana_datasource
  dashboards:
    enabled: true
    label: grafana_dashboard
persistence:
  enabled: false
EOF

echo "Waiting for Grafana..."
kubectl wait pod \
  --namespace "$NAMESPACE" \
  --for=condition=ready \
  --selector=app.kubernetes.io/name=grafana \
  --timeout=300s

echo ""
echo "=== Deploying demo workload ==="
kubectl apply -f "$PROJECT_DIR/manifests/apps/"

echo "Waiting for demo workload..."
kubectl wait pod \
  --namespace "$NAMESPACE" \
  --for=condition=ready \
  --selector=app=demo-workload \
  --timeout=120s

echo ""
echo "=== Setup complete ==="
echo "  Cluster:   $CLUSTER_NAME"
echo "  Namespace: $NAMESPACE"
echo "  デモ実行:       ./scripts/demo.sh"
echo "  ログクエリ:     ./scripts/query-logs.sh"
echo "  クリーンアップ: ./scripts/teardown.sh"
