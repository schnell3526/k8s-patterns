#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAMESPACE="mlflow-postgres"

# バックグラウンドプロセスの PID を記録し、終了時にクリーンアップ
PIDS=()
cleanup() {
  for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

echo "=========================================="
echo "  Step 1: MLflow UI にアクセス"
echo "=========================================="
echo ""
echo "port-forward を開始します..."
kubectl port-forward -n "$NAMESPACE" svc/mlflow 5000:5000 >/dev/null 2>&1 &
PIDS+=($!)
kubectl port-forward -n "$NAMESPACE" svc/minio 9000:9000 >/dev/null 2>&1 &
PIDS+=($!)
kubectl port-forward -n "$NAMESPACE" svc/minio 9001:9001 >/dev/null 2>&1 &
PIDS+=($!)
sleep 2

echo "  MLflow UI:      http://localhost:5000"
echo "  MinIO Console:  http://localhost:9001 (minioadmin / minioadmin123)"
echo ""

echo "=========================================="
echo "  Step 2: モデルを学習・記録"
echo "=========================================="
echo ""
echo "Python スクリプトを実行して MLflow に実験を記録します..."
echo ""
uv run --with mlflow --with scikit-learn --with boto3 "$SCRIPT_DIR/train-model.py"
echo ""

echo "=========================================="
echo "  Step 3: PostgreSQL テーブル確認"
echo "=========================================="
echo ""
echo "MLflow が PostgreSQL に作成したテーブル:"
echo ""
kubectl exec -n "$NAMESPACE" postgres-0 -- \
  psql -U mlflow -d mlflow -c "\dt" 2>/dev/null || \
  echo "(PostgreSQL への接続に失敗しました)"
echo ""

echo "最新の実験ラン:"
kubectl exec -n "$NAMESPACE" postgres-0 -- \
  psql -U mlflow -d mlflow -c "SELECT run_uuid, name, status, start_time FROM runs ORDER BY start_time DESC LIMIT 5;" 2>/dev/null || true
echo ""

echo "=========================================="
echo "  Step 4: MinIO アーティファクト確認"
echo "=========================================="
echo ""
echo "MinIO Console (http://localhost:9001) で mlflow バケットを確認してください"
echo "  ユーザー: minioadmin"
echo "  パスワード: minioadmin123"
echo ""
echo "=== Demo complete ==="
echo ""
echo "port-forward は Ctrl+C で停止します"
echo "Press Ctrl+C to exit..."
wait
