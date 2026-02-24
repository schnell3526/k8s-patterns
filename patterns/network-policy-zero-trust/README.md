# NetworkPolicy: Zero Trust マイクロサービス間通信

Default Deny Ingress で全 Ingress を遮断し、必要な通信だけを明示的に許可する Zero Trust パターン。

## アーキテクチャ

```
                  NetworkPolicy (Ingress 制御)
                  ┌─────────────────────────────┐
                  │    namespace: zero-trust-demo│
                  │                              │
  ┌────────┐  allow   ┌──────────┐  allow   ┌─────────┐
  │ client ├────────→ │ frontend ├────────→ │ backend │
  │ (curl) │  :80     │ (nginx)  │  :80     │ (nginx) │
  └────┬───┘          └──────────┘          └─────────┘
       │                                        ▲
       │              default-deny-ingress       │
       └──────────── BLOCKED ───────────────────┘
            client → backend は拒否
```

**ポリシー一覧:**

| ポリシー                      | 効果                                     |
| ----------------------------- | ---------------------------------------- |
| `default-deny-ingress`        | namespace 内の全 Pod への Ingress を拒否 |
| `allow-frontend-from-client`  | client → frontend (port 80) を許可       |
| `allow-backend-from-frontend` | frontend → backend (port 80) を許可      |

## 前提条件

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが以下を自動実行する:

1. kind クラスタ作成（デフォルト CNI 無効）
2. Calico CNI インストール
3. アプリケーション（frontend, backend, client）デプロイ
4. **ポリシー適用前の通信テスト** → 全通信 OK
5. NetworkPolicy 適用
6. **ポリシー適用後の通信テスト** → 制限あり

## デモシナリオ

### Step 1: ポリシー適用前（全通信 OK）

NetworkPolicy がない状態では namespace 内の全 Pod 間で自由に通信できる。

```
client → frontend   ✅ OK (HTTP 200)
client → backend    ✅ OK (HTTP 200)
frontend → backend  ✅ OK (HTTP 200)
```

### Step 2: ポリシー適用後（制限あり）

`default-deny-ingress` + 個別許可ポリシーを適用すると、明示的に許可された通信のみ成功する。

```
client → frontend   ✅ OK  (allow-frontend-from-client で許可)
client → backend    ❌ 拒否 (default-deny-ingress でブロック)
frontend → backend  ✅ OK  (allow-backend-from-frontend で許可)
```

### 手動テスト

```bash
# 通信テストを手動実行
./scripts/test-connectivity.sh

# client Pod から直接テスト
kubectl exec -n zero-trust-demo client -- curl -s --connect-timeout 3 http://frontend
kubectl exec -n zero-trust-demo client -- curl -s --connect-timeout 3 http://backend
```

## ディレクトリ構成

```
network-policy-zero-trust/
├── README.md
├── cluster/
│   └── kind-config.yaml          # kind クラスタ設定 (disableDefaultCNI: true)
├── manifests/
│   ├── namespace.yaml            # ns: zero-trust-demo
│   ├── apps/
│   │   ├── frontend.yaml         # nginx (port 80), label: role=frontend
│   │   ├── backend.yaml          # nginx (port 80), label: role=backend
│   │   └── client.yaml           # curl Pod, label: role=client
│   └── policies/
│       ├── default-deny-ingress.yaml
│       ├── allow-frontend-from-client.yaml
│       └── allow-backend-from-frontend.yaml
└── scripts/
    ├── setup.sh                  # ワンコマンドセットアップ
    ├── teardown.sh               # クリーンアップ
    └── test-connectivity.sh      # 通信テスト (許可/拒否を自動検証)
```

## NetworkPolicy 詳細解説

### default-deny-ingress

```yaml
spec:
  podSelector: {}       # namespace 内の全 Pod に適用
  policyTypes:
    - Ingress
```

`podSelector: {}` は namespace 内の全 Pod にマッチする。`ingress` ルールが定義されていないため、全 Ingress トラフィックが拒否される。

この NetworkPolicy は Ingress のみ制御する。Egress（Pod からの送信）は制限されない。client Pod からの `curl` リクエスト自体は送信されるが、宛先 Pod 側の Ingress で拒否される。

### allow-frontend-from-client

```yaml
spec:
  podSelector:
    matchLabels:
      role: frontend      # frontend Pod に適用
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: client  # client からの通信のみ許可
      ports:
        - protocol: TCP
          port: 80
```

`role: frontend` の Pod に対して、`role: client` の Pod からの TCP port 80 Ingress を許可する。

### allow-backend-from-frontend

```yaml
spec:
  podSelector:
    matchLabels:
      role: backend       # backend Pod に適用
  ingress:
    - from:
        - podSelector:
            matchLabels:
              role: frontend  # frontend からの通信のみ許可
      ports:
        - protocol: TCP
          port: 80
```

`role: backend` の Pod に対して、`role: frontend` の Pod からの TCP port 80 Ingress を許可する。

## ハマりポイント

### default-deny の影響範囲

`default-deny-ingress` は **namespace 内の全 Pod** に適用される。これにより:

- 同一 namespace 内の Pod 間通信がすべて遮断される
- 他の namespace からの通信も遮断される
- client Pod 自体への Ingress も遮断される（今回は client への Ingress は不要なので影響なし）

個別許可ポリシーを追加すると、**そのポリシーの `podSelector` にマッチする Pod に対してのみ**例外が適用される。許可ポリシーがない Pod（例: client）は default-deny のまま全 Ingress が拒否される。

### ラベル設計の重要性

NetworkPolicy は**ラベルセレクター**で Pod を指定するため、ラベル設計がセキュリティに直結する。`app` ラベルだけでなく `role` ラベルを分離しておくと、より細かい制御が可能になる。

### NetworkPolicy は CNI 依存

NetworkPolicy は Kubernetes の標準 API だが、実際の制御は **CNI プラグイン**が行う。kind のデフォルト CNI (kindnet) は NetworkPolicy を**サポートしていない**ため、Calico 等の CNI が必要。CNI が NetworkPolicy をサポートしていない場合、ポリシーを作成してもエラーにならず**単に無視される**ので注意。

## トラブルシューティング

### Calico Pod が起動しない

```bash
kubectl get pods -n calico-system
kubectl describe pod -n calico-system -l k8s-app=calico-node
```

kind のノードが Ready にならない場合、Calico のインストールが完了していない可能性がある。`calico-system` namespace の Pod 状態を確認する。

### テストが期待と異なる結果になる

```bash
# NetworkPolicy の確認
kubectl get networkpolicy -n zero-trust-demo
kubectl describe networkpolicy -n zero-trust-demo

# Pod のラベル確認
kubectl get pods -n zero-trust-demo --show-labels

# Calico が正しく動作しているか確認
kubectl get pods -n calico-system
```

Pod のラベルがポリシーの `podSelector` / `from.podSelector` と一致しているか確認する。

### curl がタイムアウトしない（拒否されるべき通信が通る）

Calico が正しくインストールされていない可能性がある。kind クラスタの CNI 設定を確認:

```bash
# kind-config.yaml で disableDefaultCNI: true が設定されているか確認
kubectl get nodes -o wide
# STATUS が NotReady なら CNI が未インストール
```

## 本番環境での考慮事項

| 項目               | デモ                          | 本番                                                         |
| ------------------ | ----------------------------- | ------------------------------------------------------------ |
| CNI                | Calico (kind)                 | Calico / Cilium / その他 NetworkPolicy 対応 CNI              |
| デフォルトポリシー | namespace 単位の default-deny | クラスタ全体のポリシーを検討 (Calico GlobalNetworkPolicy 等) |
| Egress 制御        | なし                          | Egress も default-deny + 必要な通信のみ許可                  |
| 監視               | なし                          | NetworkPolicy のログ・監査 (Calico Flow Logs 等)             |
| namespace 間通信   | 未考慮                        | `namespaceSelector` で明示的に許可                           |
| Pod セレクター     | `role` ラベル                 | RBAC と連携したラベルガバナンス                              |

## クリーンアップ

```bash
./scripts/teardown.sh
```
