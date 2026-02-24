# Tetragon 監査ログ: eBPF → Fluent Bit → Loki → Grafana

Tetragon (eBPF) でコマンド実行・ファイルアクセス・ネットワーク接続の監査ログを取得し、Fluent Bit → Loki → Grafana で可視化するパターン。

## アーキテクチャ

```
Tetragon (eBPF DaemonSet)
    │  JSON イベントログ
    ▼
/var/run/cilium/tetragon/tetragon.log (hostPath)
    │  tail input
    ▼
Fluent Bit (DaemonSet)
    │  loki output plugin
    ▼
Loki (SingleBinary mode)
    │  LogQL
    ▼
Grafana (port-forward :3000)
```

**Tetragon が検出するイベント:**

| イベント種別     | TracingPolicy           | kprobe / フック | 検出対象例                                 |
| ---------------- | ----------------------- | --------------- | ------------------------------------------ |
| プロセス実行     | (デフォルト)            | process_exec    | `cat`, `curl`, `wget`, `openssl` 等        |
| ファイルアクセス | file-access-monitor     | fd_install      | `/etc/shadow`, `/etc/passwd`, `/root/.ssh` |
| ネットワーク接続 | network-connect-monitor | tcp_connect     | TCP 接続 (tetragon-audit-demo namespace)   |

## 前提条件

- [Docker](https://docs.docker.com/get-docker/) (4GB+ RAM)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [jq](https://jqlang.github.io/jq/download/)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが以下を自動実行する:

1. kind クラスタ作成
2. Tetragon インストール (kube-system)
3. TracingPolicy 適用 (ファイルアクセス / ネットワーク監視)
4. Loki インストール (SingleBinary mode)
5. Grafana ConfigMap 作成 (datasource + dashboard)
6. Fluent Bit インストール (Tetragon ログを Loki に転送)
7. Grafana インストール (sidecar で ConfigMap を自動読込)
8. demo-workload Pod デプロイ

セットアップ完了後、デモを実行する:

```bash
./scripts/demo.sh
```

## デモシナリオ

### Step 1: 不審コマンドの実行

demo-workload Pod 内で以下のコマンドを実行し、Tetragon がイベントを検出する:

```
cat /etc/shadow        ← ファイルアクセス検出
cat /etc/passwd        ← ファイルアクセス検出
curl example.com       ← ネットワーク接続検出
wget example.com       ← ネットワーク接続検出
openssl rand -base64   ← プロセス実行検出
```

### Step 2: Tetragon ログの直接確認

Tetragon Pod のログから直近のイベントを表示する。

```bash
# 手動確認
kubectl logs -n kube-system -l app.kubernetes.io/name=tetragon \
  -c export-stdout --tail=20 | jq .
```

### Step 3: Loki API 経由でクエリ

LogQL でイベントをフィルタする。

```bash
./scripts/query-logs.sh
```

### Step 4: Grafana で可視化

```
URL:        http://localhost:3000
ユーザー:   admin
パスワード: admin
```

ダッシュボード「Tetragon 監査ログ」で以下を確認できる:

- 全イベントのログストリーム
- ファイルアクセスイベント
- ネットワーク接続イベント
- プロセス実行イベント
- イベント数の時系列推移

## Helm チャート

| コンポーネント | チャート            | バージョン | 備考                                     |
| -------------- | ------------------- | ---------- | ---------------------------------------- |
| Tetragon       | `cilium/tetragon`   | 1.3.0      | kube-system にインストール               |
| Loki           | `grafana/loki`      | 6.7.3      | SingleBinary, filesystem, auth 無効      |
| Fluent Bit     | `fluent/fluent-bit` | 0.49.0     | hostPath マウント, runAsUser: 0          |
| Grafana        | `grafana/grafana`   | 8.8.2      | sidecar で datasource/dashboard 自動読込 |

## ディレクトリ構成

```
tetragon-audit-log/
├── README.md
├── cluster/
│   └── kind-config.yaml               # kind クラスタ設定
├── manifests/
│   ├── namespace.yaml                 # ns: tetragon-audit-demo
│   ├── apps/
│   │   └── demo-workload.yaml         # nicolaka/netshoot Pod
│   ├── policies/
│   │   ├── file-access.yaml           # TracingPolicy: ファイルアクセス監視
│   │   └── network-monitor.yaml       # TracingPolicy: TCP 接続監視
│   └── grafana/
│       ├── datasource.yaml            # Loki データソース (ConfigMap)
│       └── dashboard.yaml             # 監査ログダッシュボード (ConfigMap)
└── scripts/
    ├── setup.sh                       # クラスタ作成 → 全コンポーネント構築
    ├── demo.sh                        # 不審コマンド実行 → ログ確認 → Grafana
    ├── query-logs.sh                  # Loki HTTP API 直接クエリ
    └── teardown.sh                    # kind delete cluster
```

## TracingPolicy

### file-access.yaml

`fd_install` kprobe で以下のパスへの読み取りを検出する:

- `/etc/shadow`
- `/etc/passwd`
- `/etc/sudoers`
- `/root/.ssh`

### network-monitor.yaml

`tcp_connect` kprobe で TCP 接続を検出する。`TracingPolicyNamespaced` を使用して `tetragon-audit-demo` namespace に限定し、コントロールプレーンのノイズを回避する。

## トラブルシューティング

### Tetragon Pod が起動しない

Tetragon は eBPF を使用するため、カーネルバージョン 4.19+ が必要。kind のノードイメージは通常これを満たしている。

### Fluent Bit がログを読めない (Permission denied)

Fluent Bit は `runAsUser: 0` で実行する設定にしている。それでもエラーが出る場合:

```bash
# Fluent Bit Pod のログ確認
kubectl logs -n tetragon-audit-demo -l app.kubernetes.io/name=fluent-bit

# hostPath のパーミッション確認
docker exec tetragon-audit-demo-control-plane ls -la /var/run/cilium/tetragon/
```

### Loki にログが届かない

```bash
# Fluent Bit → Loki の接続確認
kubectl logs -n tetragon-audit-demo -l app.kubernetes.io/name=fluent-bit | grep -i error

# Loki の準備状態を確認
kubectl exec -n tetragon-audit-demo svc/loki -- wget -qO- http://localhost:3100/ready
```

Fluent Bit のログに `[error]` がある場合、Loki の起動が完了していない可能性がある。setup.sh は依存関係順にインストールするが、タイミングによっては Fluent Bit が先に起動することがある。その場合は Fluent Bit Pod を再起動する:

```bash
kubectl rollout restart daemonset/fluent-bit -n tetragon-audit-demo
```

### Grafana にダッシュボードが表示されない

```bash
# sidecar がConfigMap を検出しているか確認
kubectl logs -n tetragon-audit-demo -l app.kubernetes.io/name=grafana -c grafana-sc-dashboard
```

ConfigMap のラベル `grafana_dashboard: "1"` が正しく設定されているか確認する。

### Loki の `allow_structured_metadata` エラー

Loki 6.7.3 に固定しているため通常は発生しない。もし発生する場合は Loki の Helm values で明示的に無効化する:

```yaml
loki:
  limits_config:
    allow_structured_metadata: false
```

## クリーンアップ

```bash
./scripts/teardown.sh
```
