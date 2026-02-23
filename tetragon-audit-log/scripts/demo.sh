#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="tetragon-audit-demo"
POD_NAME="demo-workload"

echo "=== Starting Grafana port-forward ==="
kubectl port-forward -n "$NAMESPACE" svc/grafana 3000:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

echo ""
echo "=========================================="
echo "  Step 1: 不審コマンドの実行"
echo "=========================================="
echo ""

echo "--- cat /etc/shadow ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /etc/shadow 2>/dev/null || true
sleep 1

echo ""
echo "--- cat /etc/passwd ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- cat /etc/passwd 2>/dev/null | head -3
sleep 1

echo ""
echo "--- curl example.com ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- curl -s -o /dev/null -w "HTTP %{http_code}" https://example.com 2>/dev/null || true
sleep 1

echo ""
echo "--- wget example.com ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- wget -q -O /dev/null https://example.com 2>/dev/null || true
sleep 1

echo ""
echo "--- openssl rand -base64 32 ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- openssl rand -base64 32
sleep 1

echo ""
echo "--- whoami ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- whoami
sleep 1

echo ""
echo "--- ls /root/.ssh ---"
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- ls /root/.ssh 2>/dev/null || echo "(ディレクトリなし)"
sleep 1

echo ""
echo "=========================================="
echo "  Step 2: Tetragon ログの直接確認"
echo "=========================================="
echo ""
echo "直近の process_exec イベント:"
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout --tail=20 2>/dev/null \
  | grep "$NAMESPACE" \
  | jq -r 'select(.process_exec != null) | "\(.time) \(.process_exec.process.binary) \(.process_exec.process.arguments // "")"' 2>/dev/null \
  | tail -5 || echo "(イベントなし)"

echo ""
echo "直近の kprobe イベント:"
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon -c export-stdout --tail=50 2>/dev/null \
  | grep "$NAMESPACE" \
  | jq -r 'select(.process_kprobe != null) | "\(.time) \(.process_kprobe.function_name) \(.process_kprobe.process.binary)"' 2>/dev/null \
  | tail -5 || echo "(イベントなし)"

echo ""
echo "=========================================="
echo "  Step 3: Loki API 経由でログ確認"
echo "=========================================="
echo ""
"$SCRIPT_DIR/query-logs.sh"

echo ""
echo "=========================================="
echo "  Step 4: Grafana で可視化"
echo "=========================================="
echo ""
echo "  URL:      http://localhost:3000"
echo "  ユーザー: admin"
echo "  パスワード: admin"
echo ""
echo "  ダッシュボード: Dashboards → Tetragon 監査ログ"
echo ""
echo "  port-forward を維持中 (Ctrl+C で終了)"
echo ""
wait $PF_PID 2>/dev/null || true
