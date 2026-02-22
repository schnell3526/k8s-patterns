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
| `--skip-oidc-discovery` | `true` | OIDC discovery を無効化し、各エンドポイントを明示指定 |
| `--oidc-issuer-url` | `http://keycloak...svc:8080/...` | クラスタ内 issuer URL（`--skip-oidc-discovery` 時も必須） |
| `--insecure-oidc-skip-issuer-verification` | `true` | 内部/外部で issuer URL が異なるため検証スキップ |
| `--login-url` | `http://localhost/keycloak/...` | ブラウザリダイレクト用外部 URL |
| `--redeem-url` | `http://keycloak...svc:8080/...` | バックチャネル（トークン交換）用内部 URL |
| `--profile-url` | `http://keycloak...svc:8080/...` | UserInfo エンドポイント（内部 URL） |
| `--oidc-jwks-url` | `http://keycloak...svc:8080/...` | JWKS エンドポイント（内部 URL） |
| `--skip-claims-from-profile-url` | — | profile URL からの claims 取得をスキップ（ID トークンから取得） |
| `--cookie-secure` | `false` | HTTP（非 TLS）環境用 |

**なぜ `--skip-oidc-discovery=true` を使うのか？**

クラスタ内では Keycloak に `http://keycloak.mlflow-oidc.svc.cluster.local:8080/...` でアクセスしますが、ブラウザからは `http://localhost/keycloak/...` でアクセスします。OIDC discovery を使うと issuer URL の不一致でエラーになるため、discovery をスキップし、ブラウザ向け（`--login-url`）とバックチャネル向け（`--redeem-url`, `--profile-url`, `--oidc-jwks-url`）のエンドポイントを個別に指定しています。

**なぜ `--skip-claims-from-profile-url` が必要か？**

Keycloak が発行するアクセストークンの `iss` claim は `http://localhost/keycloak/...`（外部 URL）ですが、oauth2-proxy は `http://keycloak...svc:8080/...`（内部 URL）で userinfo エンドポイントにアクセスします。Keycloak はトークンの issuer とリクエスト先の不一致を検出して 401 を返すため、profile URL からの claims 取得をスキップし、ID トークンに含まれる email 等の claims を使用します。

### Keycloak の設定

- 開発モード (`start-dev`) で起動
- `KC_HTTP_RELATIVE_PATH=/keycloak` でサブパス運用
- `KC_PROXY_HEADERS=xforwarded` で Ingress 背後の動作に対応

## Keycloak の再セットアップ

Keycloak は開発モード（`start-dev`）で動作しており、データを永続化していません。Keycloak の Pod が再起動すると realm・client・ユーザーがすべてリセットされます。

再セットアップが必要なケース:
- Keycloak の Deployment を変更して Pod が再作成された
- Pod が OOMKilled やクラッシュで再起動した
- `kubectl rollout restart` を実行した

```bash
# 1. Keycloak が Ready になるまで待機
kubectl wait -n mlflow-oidc --for=condition=ready pod -l app=keycloak --timeout=180s

# 2. Keycloak の realm, client, user を再作成 + Secret 再生成
./scripts/configure-keycloak.sh

# 3. oauth2-proxy を再起動（Secret が再生成されるため）
kubectl rollout restart -n mlflow-oidc deployment/oauth2-proxy
kubectl wait -n mlflow-oidc --for=condition=ready pod -l app=oauth2-proxy --timeout=120s
```

## トラブルシューティング

### Keycloak 管理画面が「Page not found」（黒い画面）

Keycloak の Deployment を変更すると Pod が再作成されますが、開発モードではデータが永続化されないため realm・client・ユーザーがすべて消失します。この状態で管理画面にアクセスすると、SPA が初期化に失敗して「We are sorry... Page not found」と表示されます。

ブラウザに古いセッション Cookie が残っていることも原因になります。

**対処**: [Keycloak の再セットアップ](#keycloak-の再セットアップ) を実行し、シークレットウィンドウまたは Cookie クリア後にアクセスしてください。

### ログイン後に 500 Internal Server Error

oauth2-proxy のログに以下のエラーが出ている場合:

```
could not get claim "groups": failed to fetch claims from profile URL:
error making request to profile URL: unexpected status "401"
```

**原因**: oauth2-proxy が userinfo エンドポイント（クラスタ内部 URL）にアクセスする際、アクセストークンの `iss` claim（`http://localhost/keycloak/...`）とリクエスト先 URL（`http://keycloak...svc:8080/...`）が一致しないため、Keycloak が 401 を返しています。

**対処**: `--skip-claims-from-profile-url` が設定されているか確認してください。この設定により userinfo への問い合わせをスキップし、ID トークンに含まれる claims のみを使用します。

### oauth2-proxy が起動しない

```bash
kubectl logs -n mlflow-oidc -l app=oauth2-proxy
```

`missing required setting: issuer-url` エラーの場合、`--skip-oidc-discovery=true` を使用していても `--oidc-issuer-url` は必須です。

Secret `oauth2-proxy` が存在するか確認:

```bash
kubectl get secret -n mlflow-oidc oauth2-proxy
```

Secret がない場合は [Keycloak の再セットアップ](#keycloak-の再セットアップ) を実行してください。

### Ingress が動作しない

```bash
kubectl get ingress -n mlflow-oidc
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=20
```

## 本番環境への適用

このデモの複雑さの大半は、**クラスタ内に IdP (Keycloak) をセルフホストしたことによる issuer URL の内部/外部不一致** に起因しています。本番でマネージド IdP を使えば oauth2-proxy の設定は大幅にシンプルになります。

### oauth2-proxy の設定（本番例: Okta）

```yaml
args:
  - --provider=oidc
  - --oidc-issuer-url=https://your-org.okta.com/oauth2/default
  - --upstream=http://mlflow:5000
  - --redirect-url=https://mlflow.example.com/oauth2/callback
  - --email-domain=your-org.com
```

デモで必要だった以下のワークアラウンドはすべて不要になります:

| デモで必要だった設定 | 不要になる理由 |
|------|------|
| `--skip-oidc-discovery` + 各エンドポイント明示指定 | マネージド IdP は外部到達可能な issuer URL を持つため discovery が使える |
| `--insecure-oidc-skip-issuer-verification` | issuer URL が内部/外部で一致する |
| `--skip-claims-from-profile-url` | userinfo に正しい issuer でアクセスできる |
| `--cookie-secure=false` | TLS 環境ではデフォルト (true) のまま |

### その他の本番考慮事項

| 項目 | デモ | 本番 |
|------|------|------|
| IdP | Keycloak (セルフホスト・開発モード) | Okta / Azure AD / Google 等のマネージド IdP |
| TLS | なし | cert-manager + Ingress TLS |
| email-domain | `*`（全許可） | 自社ドメインに制限 |
| MLflow ストレージ | ローカルファイル（揮発） | S3/GCS + PostgreSQL |
| Secret 管理 | スクリプトで自動生成 | External Secrets / Sealed Secrets |

## クリーンアップ

```bash
./scripts/teardown.sh
```
