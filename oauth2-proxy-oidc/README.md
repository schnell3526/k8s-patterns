# oauth2-proxy + MLflow + Keycloak (OIDC)

認証機能を持たない MLflow OSS の前段に [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/) を配置し、クラスタ内の [Keycloak](https://www.keycloak.org/) による OIDC 認証を実現するパターン。

## アーキテクチャ

```
Browser → localhost:80
  ├─ /           → ingress-nginx → oauth2-proxy (4180) → MLflow (5000)
  └─ /keycloak/  → ingress-nginx → Keycloak (8080)
                        ↕
              oauth2-proxy ←→ Keycloak (OIDC)
```

- **Keycloak**: OIDC Identity Provider（クラスタ内セルフホスト）
- **oauth2-proxy**: リバースプロキシ。未認証リクエストを Keycloak にリダイレクトし、認証済みリクエストを MLflow に転送
- **MLflow**: 認証なしの ML 実験管理 UI
- **ingress-nginx**: パスベースルーティング

## 前提条件

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [jq](https://jqlang.github.io/jq/download/)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップ完了後:

| URL | 用途 | 認証情報 |
|-----|------|----------|
| http://localhost/ | MLflow UI（OIDC 認証あり） | user / password |
| http://localhost/keycloak/admin/ | Keycloak 管理画面 | admin / admin |

## 認証フロー

1. ブラウザが `http://localhost/` にアクセス
2. ingress-nginx → oauth2-proxy へルーティング
3. セッション Cookie がなければ Keycloak の認可エンドポイントにリダイレクト
4. ユーザーが Keycloak でログイン（テストユーザー: `user` / `password`）
5. Keycloak が `http://localhost/oauth2/callback` に認可コードとともにリダイレクト
6. oauth2-proxy が Keycloak のトークンエンドポイント（クラスタ内部経由）でトークン交換
7. セッション Cookie 設定後、MLflow にリクエスト転送
8. MLflow UI がブラウザに表示

## ディレクトリ構成

```
oauth2-proxy-oidc/
├── README.md
├── cluster/
│   └── kind-config.yaml          # kind クラスタ設定
├── manifests/
│   ├── namespace.yaml
│   ├── keycloak/
│   │   ├── deployment.yaml       # Keycloak (dev mode)
│   │   └── service.yaml
│   ├── mlflow/
│   │   ├── deployment.yaml       # MLflow Tracking Server
│   │   └── service.yaml
│   ├── oauth2-proxy/
│   │   ├── deployment.yaml       # oauth2-proxy (OIDC)
│   │   └── service.yaml
│   └── ingress.yaml              # パスベースルーティング
└── scripts/
    ├── setup.sh                  # ワンコマンドセットアップ
    ├── configure-keycloak.sh     # Keycloak 自動設定
    └── teardown.sh               # クリーンアップ
```

## 手動セットアップ

```bash
# 1. kind クラスタ作成
kind create cluster --config cluster/kind-config.yaml

# 2. ingress-nginx インストール
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 3. マニフェスト適用（oauth2-proxy 以外）
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/keycloak/
kubectl apply -f manifests/mlflow/

# 4. Keycloak Ready 待機
kubectl wait -n mlflow-oidc --for=condition=ready pod -l app=keycloak --timeout=180s

# 5. Keycloak 設定（realm, client, user 作成 + Secret 生成）
./scripts/configure-keycloak.sh

# 6. oauth2-proxy + Ingress 適用
kubectl apply -f manifests/oauth2-proxy/
kubectl apply -f manifests/ingress.yaml

# 7. 全 Pod Ready 待機
kubectl wait -n mlflow-oidc --for=condition=ready pod --all --timeout=120s
```

## 動作確認

```bash
# Pod 状態確認
kubectl get pods -n mlflow-oidc

# ブラウザでアクセス
open http://localhost/
# → Keycloak ログイン画面にリダイレクト → user/password でログイン → MLflow UI

# Keycloak 管理画面
open http://localhost/keycloak/admin/
# → admin/admin でログイン
```

## コンポーネント詳細

### oauth2-proxy の設定ポイント

| 設定 | 値 | 説明 |
|------|-----|------|
| `--oidc-issuer-url` | `http://keycloak...svc:8080/...` | クラスタ内 issuer URL |
| `--login-url` | `http://localhost/keycloak/...` | ブラウザリダイレクト用外部 URL |
| `--redeem-url` | `http://keycloak...svc:8080/...` | バックチャネル（トークン交換）用内部 URL |
| `--insecure-oidc-skip-issuer-verification` | `true` | 内部/外部で issuer URL が異なるためスキップ |
| `--cookie-secure` | `false` | HTTP（非 TLS）環境用 |

### Keycloak の設定

- 開発モード (`start-dev`) で起動
- `KC_HTTP_RELATIVE_PATH=/keycloak` でサブパス運用
- `KC_PROXY_HEADERS=xforwarded` で Ingress 背後の動作に対応

## トラブルシューティング

### oauth2-proxy が起動しない

```bash
kubectl logs -n mlflow-oidc -l app=oauth2-proxy
```

Secret `oauth2-proxy` が存在するか確認:

```bash
kubectl get secret -n mlflow-oidc oauth2-proxy
```

### Keycloak ログイン後にエラー

oauth2-proxy のログで issuer mismatch エラーが出る場合は `--insecure-oidc-skip-issuer-verification=true` が設定されているか確認。

### Ingress が動作しない

```bash
kubectl get ingress -n mlflow-oidc
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20
```

## クリーンアップ

```bash
./scripts/teardown.sh
```
