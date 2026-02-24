# パターン共通トラブルシューティング

各パターン固有のコマンドは各ディレクトリの README を参照。

## Pod デバッグ

```bash
# Pod 一覧と状態確認
kubectl get pods -n <namespace>
kubectl get pods -n <namespace> --show-labels

# Pod の詳細（Events セクションでスケジューリング失敗や ImagePull エラーを確認）
kubectl describe pod <pod> -n <namespace>

# ログ確認
kubectl logs <pod> -n <namespace>
kubectl logs <pod> -n <namespace> --previous   # OOMKill 等で再起動した場合の前回ログ
kubectl logs -n <namespace> -l app=<label>      # ラベルで複数 Pod のログをまとめて確認

# namespace 内のイベント（時系列で問題を追える）
kubectl get events -n <namespace> --sort-by='.lastTimestamp'
```

## 接続テスト

```bash
# Pod から別の Service への疎通確認
kubectl exec -n <namespace> <pod> -- curl -s --connect-timeout 3 http://<service>:<port>

# DNS 解決の確認
kubectl exec -n <namespace> <pod> -- nslookup <service>

# クラスタ外への HTTPS 疎通
kubectl exec -n <namespace> <pod> -- curl -s --connect-timeout 5 https://httpbin.org/get
```

## NetworkPolicy デバッグ

NetworkPolicy が期待通り動かない場合、大半は **ラベルの不一致** か **CNI が NetworkPolicy を未サポート** のどちらか。

```bash
# 適用されている NetworkPolicy 一覧
kubectl get networkpolicy -n <namespace>

# ルールの詳細（podSelector / namespaceSelector を確認）
kubectl describe networkpolicy -n <namespace>

# Pod のラベルが NetworkPolicy のセレクタと一致しているか確認
kubectl get pods -n <namespace> --show-labels

# Namespace のラベル確認（namespaceSelector を使っている場合）
kubectl get ns --show-labels
```

### CNI が NetworkPolicy をサポートしているか

kindnet（Kind デフォルト）は NetworkPolicy を **サポートしていない**。Policy を適用しても無視される。
Calico または Cilium を使う必要がある。

```bash
# Calico の場合
kubectl get pods -n calico-system
kubectl get pods -n calico-system -l k8s-app=calico-node

# Cilium の場合
cilium status
kubectl get pods -n kube-system -l k8s-app=cilium
```

## ストレージ

```bash
# PVC の状態確認（Bound になっていなければ StorageClass やキャパシティを確認）
kubectl get pvc -n <namespace>

# PV の状態
kubectl get pv
```

## Port Forward

```bash
# Service 経由でローカルからアクセス
kubectl port-forward -n <namespace> svc/<service> <local-port>:<service-port>

# Pod 直接（Service がない場合）
kubectl port-forward -n <namespace> <pod> <local-port>:<container-port>
```

## Kind クラスタ

```bash
# クラスタ一覧
kind get clusters

# ノード状態（NotReady の場合は CNI 未インストールの可能性）
kubectl get nodes -o wide

# Kind コンテナのログ（クラスタ自体が起動しない場合）
docker logs <cluster-name>-control-plane
```

## リソースの Ready 待ち

スクリプト内で使う `kubectl wait` のパターン集。

```bash
# Pod が Ready になるまで待つ
kubectl wait -n <namespace> --for=condition=ready pod -l app=<label> --timeout=120s

# 全 Pod が Ready になるまで
kubectl wait -n <namespace> --for=condition=ready pod --all --timeout=120s

# Node が Ready になるまで（CNI インストール後）
kubectl wait --for=condition=ready node --all --timeout=120s

# Job の完了待ち
kubectl wait -n <namespace> --for=condition=complete job/<job-name> --timeout=60s

# Deployment の Available 待ち
kubectl wait -n <namespace> deployment/<name> --for=condition=Available --timeout=120s

# DaemonSet のロールアウト完了待ち
kubectl rollout status daemonset/<name> -n <namespace> --timeout=300s

# CRD が利用可能になるまで
kubectl wait crd/<crd-name> --for=condition=Established --timeout=60s
```
