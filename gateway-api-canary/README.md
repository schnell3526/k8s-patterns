# Gateway API: HTTPRoute によるカナリアリリース

Gateway API の HTTPRoute で `weight` ベースのトラフィック分割を行い、段階的にカナリアリリースするパターン。

## アーキテクチャ

```
                        Gateway (Envoy)
                        ┌──────────────┐
  curl                  │              │   weight: 90
  -H "Host: myapp..."  │   HTTPRoute  ├──────────────→ app-v1 (http-echo)
 ──────────────────────→│  canary-route│                "v1"
                        │              │   weight: 10
                        │              ├──────────────→ app-v2 (http-echo)
                        └──────────────┘                "v2"
```

**カナリアリリースの流れ:**

| Step | v1 weight | v2 weight | 状態             |
| ---- | --------- | --------- | ---------------- |
| 1    | 100       | 0         | 初期状態         |
| 2    | 90        | 10        | カナリア開始     |
| 3    | 50        | 50        | 検証中           |
| 4    | 0         | 100       | ロールアウト完了 |

## 前提条件

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが以下を自動実行する:

1. kind クラスタ作成
2. Envoy Gateway インストール（Helm）
3. Gateway リソース作成
4. アプリケーション（app-v1, app-v2）デプロイ
5. 初期ルート（100% v1）適用

セットアップ完了後、デモを実行する:

```bash
./scripts/demo.sh
```

## デモシナリオ

### Step 1: 100% v1（初期状態）

全トラフィックが v1 に向いている。

```
--- トラフィック分布テスト (50 リクエスト) ---
  v1: 50 (100%)
  v2: 0 (0%)
```

### Step 2: カナリア 90:10

v2 に 10% のトラフィックを流し始める。

```
--- トラフィック分布テスト (50 リクエスト) ---
  v1: 45 (90%)
  v2: 5 (10%)
```

### Step 3: 50:50

v2 の安定を確認し、トラフィックを半分に引き上げる。

```
--- トラフィック分布テスト (50 リクエスト) ---
  v1: 25 (50%)
  v2: 25 (50%)
```

### Step 4: 100% v2（ロールアウト完了）

全トラフィックを v2 に切り替え、カナリアリリース完了。

```
--- トラフィック分布テスト (50 リクエスト) ---
  v1: 0 (0%)
  v2: 50 (100%)
```

### 手動テスト

```bash
# Envoy への port-forward
ENVOY_SERVICE=$(kubectl get svc -n envoy-gateway-system \
  --selector=gateway.envoyproxy.io/owning-gateway-namespace=canary-demo,gateway.envoyproxy.io/owning-gateway-name=eg \
  -o jsonpath='{.items[0].metadata.name}')
kubectl -n envoy-gateway-system port-forward service/${ENVOY_SERVICE} 8888:80 &

# リクエスト送信
curl -s -H "Host: myapp.example.com" http://localhost:8888/

# ルートの切り替え
kubectl apply -f manifests/routes/route-canary-10.yaml
```

## HTTPRoute の weight

`weight` はバックエンド間の比率を指定する。パーセンテージではなく比率なので、以下は全て同じ意味になる:

```yaml
# 90:10
backendRefs:
  - name: app-v1
    weight: 90
  - name: app-v2
    weight: 10

# これも 90:10
backendRefs:
  - name: app-v1
    weight: 9
  - name: app-v2
    weight: 1
```

トラフィック比率 = `weight / sum(all weights)` で計算される。

## Ingress との比較

同じカナリアリリースを Ingress (nginx) で実現する場合、コントローラー固有のアノテーションが必要になる:

```yaml
# Ingress (nginx): コントローラー固有のアノテーションが必要
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"           # nginx 固有
    nginx.ingress.kubernetes.io/canary-weight: "10"      # nginx 固有
spec:
  ingressClassName: nginx
  rules:
    - host: myapp.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-v2
                port:
                  number: 8080
```

```yaml
# Gateway API: 標準 API だけで完結
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: canary-route
spec:
  parentRefs:
    - name: eg
  rules:
    - backendRefs:
        - name: app-v1
          port: 8080
          weight: 90
        - name: app-v2
          port: 8080
          weight: 10
```

| 観点           | Ingress (nginx)                      | Gateway API                             |
| -------------- | ------------------------------------ | --------------------------------------- |
| カナリア設定   | アノテーション（nginx 固有）         | `weight` フィールド（標準 API）         |
| ポータビリティ | nginx 以外では動かない               | Envoy Gateway / Istio / Cilium 等で動く |
| リソース数     | 本番用 + カナリア用の 2 つの Ingress | 1 つの HTTPRoute                        |
| L7 マッチング  | アノテーション依存                   | 標準の `matches` フィールド             |

## Gateway API のリソースモデル

Gateway API は責務を 3 つのレイヤーに分離している:

```
GatewayClass (cluster-scoped)          ← インフラ提供者が管理
  └── Gateway (namespace-scoped)       ← クラスタ運用者が管理
       └── HTTPRoute (namespace-scoped) ← アプリ開発者が管理
```

| リソース     | 誰が管理するか | 役割                                       |
| ------------ | -------------- | ------------------------------------------ |
| GatewayClass | インフラ提供者 | どのコントローラーを使うか（Envoy 等）     |
| Gateway      | クラスタ運用者 | リスナー（ポート、プロトコル）の定義       |
| HTTPRoute    | アプリ開発者   | ルーティングルール（パス、ヘッダー、重み） |

Ingress では 1 つのリソースに全ての設定が混在していたが、Gateway API ではロールごとに分離されている。

## ディレクトリ構成

```
gateway-api-canary/
├── README.md
├── cluster/
│   └── kind-config.yaml              # kind クラスタ設定
├── manifests/
│   ├── namespace.yaml                # ns: canary-demo
│   ├── gateway/
│   │   └── gateway.yaml              # Gateway リソース
│   ├── apps/
│   │   ├── app-v1.yaml               # http-echo "v1" + Service
│   │   └── app-v2.yaml               # http-echo "v2" + Service
│   └── routes/
│       ├── route-v1-only.yaml        # 100% v1
│       ├── route-canary-10.yaml      # 90:10
│       ├── route-canary-50.yaml      # 50:50
│       └── route-full-v2.yaml        # 100% v2
└── scripts/
    ├── setup.sh                      # ワンコマンドセットアップ
    ├── demo.sh                       # 段階的カナリアデモ
    ├── test-traffic.sh               # トラフィック分布テスト
    └── teardown.sh                   # クリーンアップ
```

## トラブルシューティング

### Envoy Gateway Pod が起動しない

```bash
kubectl get pods -n envoy-gateway-system
kubectl describe pod -n envoy-gateway-system -l app.kubernetes.io/name=gateway-helm
```

### Gateway が Programmed にならない

```bash
kubectl get gateway -n canary-demo
kubectl describe gateway eg -n canary-demo
```

`status.conditions` で `Programmed: True` になっていることを確認する。

### port-forward でレスポンスが返らない

```bash
# Envoy proxy Pod の確認
kubectl get pods -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=eg

# HTTPRoute の状態確認
kubectl get httproute -n canary-demo
kubectl describe httproute canary-route -n canary-demo
```

`parentRefs` の Gateway 名と namespace が正しいか確認する。

### トラフィック分布が期待と大きく異なる

weight ベースの分散は確率的であるため、リクエスト数が少ないと偏ることがある。`test-traffic.sh` は 50 リクエスト送信するが、さらに精度が必要な場合は `REQUESTS` 変数を増やす。

## クリーンアップ

```bash
./scripts/teardown.sh
```
