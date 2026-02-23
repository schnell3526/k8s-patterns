#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="tetragon-audit-demo"

# Loki への port-forward を一時的に開始
kubectl port-forward -n "$NAMESPACE" svc/loki 3100:3100 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 2

LOKI_URL="http://localhost:3100"

echo "--- 全 Tetragon イベント (直近 10 件) ---"
curl -sG "$LOKI_URL/loki/api/v1/query_range" \
  --data-urlencode 'query={job="tetragon"}' \
  --data-urlencode "limit=10" \
  --data-urlencode "start=$(date -u -v-30M +%s 2>/dev/null || date -u -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  | jq -r '.data.result[].values[][1]' 2>/dev/null \
  | head -10 \
  | jq -r 'if .process_exec then "EXEC: \(.process_exec.process.binary) \(.process_exec.process.arguments // "")" elif .process_kprobe then "KPROBE: \(.process_kprobe.function_name) \(.process_kprobe.process.binary)" else .process_type // "OTHER" end' 2>/dev/null \
  || echo "(Loki にイベントがまだ転送されていません。数秒後に再実行してください)"

echo ""
echo "--- プロセス実行イベント ---"
curl -sG "$LOKI_URL/loki/api/v1/query_range" \
  --data-urlencode 'query={job="tetragon"} |= "process_exec"' \
  --data-urlencode "limit=5" \
  --data-urlencode "start=$(date -u -v-30M +%s 2>/dev/null || date -u -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  | jq -r '.data.result[].values[][1]' 2>/dev/null \
  | head -5 \
  | jq -r '"\(.process_exec.process.binary) \(.process_exec.process.arguments // "")"' 2>/dev/null \
  || echo "(イベントなし)"

echo ""
echo "--- kprobe イベント (ファイルアクセス / ネットワーク) ---"
curl -sG "$LOKI_URL/loki/api/v1/query_range" \
  --data-urlencode 'query={job="tetragon"} |= "kprobe"' \
  --data-urlencode "limit=5" \
  --data-urlencode "start=$(date -u -v-30M +%s 2>/dev/null || date -u -d '30 minutes ago' +%s)000000000" \
  --data-urlencode "end=$(date -u +%s)000000000" \
  | jq -r '.data.result[].values[][1]' 2>/dev/null \
  | head -5 \
  | jq -r '"\(.process_kprobe.function_name) \(.process_kprobe.process.binary)"' 2>/dev/null \
  || echo "(イベントなし)"
