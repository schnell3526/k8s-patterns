# MLflow + PostgreSQL + MinIO: ML 実験管理基盤

PostgreSQL をバックエンドストア、MinIO をアーティファクトストアとして使用する MLflow Tracking Server を素のマニフェストで構築するパターン。

## アーキテクチャ

```
                          ┌──────────────────────────┐
                          │    MLflow Tracking Server │
  Browser                 │    (Deployment)           │
  http://localhost:5000   │    :5000                  │
 ─────────────────────────┤                           │
                          │  backend-store-uri:       │
                          │    postgresql://...       │
                          │  default-artifact-root:   │
                          │    s3://mlflow/           │
                          └────────┬──────────┬───────┘
                                   │          │
                    メタデータ     │          │  アーティファクト
                    (実験、パラメータ、       │  (モデル、ファイル)
                     メトリクス)   │          │
                                   ▼          ▼
                          ┌────────────┐  ┌──────────┐
                          │ PostgreSQL │  │  MinIO   │
                          │(StatefulSet)│  │(Deployment)│
                          │ :5432      │  │ :9000 API│
                          │            │  │ :9001 UI │
                          │ PVC: 2Gi   │  │ PVC: 5Gi │
                          └────────────┘  └──────────┘
```

**データの流れ:**
- MLflow UI / Python クライアント → MLflow Server (:5000)
- MLflow Server → PostgreSQL: 実験メタデータ（パラメータ、メトリクス、ラン情報）
- MLflow Server → MinIO (S3 互換): アーティファクト（学習済みモデル、画像等）

## 前提条件

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [uv](https://docs.astral.sh/uv/getting-started/installation/)（デモスクリプト用）

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが以下を自動実行する:

1. kind クラスタ作成（control-plane 1 + worker 2）
2. Namespace 作成
3. Secret 作成（PostgreSQL / MinIO 認証情報）
4. PostgreSQL デプロイ → Ready 待機
5. MinIO デプロイ → Ready 待機
6. バケット作成 Job 実行
7. MLflow デプロイ → Ready 待機

セットアップ完了後:

```bash
./scripts/demo.sh
```

## デモシナリオ

### Step 1: MLflow UI にアクセス

```bash
kubectl port-forward -n mlflow-postgres svc/mlflow 5000:5000
```

ブラウザで http://localhost:5000 にアクセスする。

### Step 2: モデルを学習・記録

```bash
# MinIO への port-forward も必要（アーティファクトアップロード用）
kubectl port-forward -n mlflow-postgres svc/minio 9000:9000 &
uv run --with mlflow --with scikit-learn --with boto3 scripts/train-model.py
```

Wine データセットで RandomForest 分類モデルを学習し、MLflow に記録する。`uv run --with` で依存を自動解決するため事前インストール不要。

### Step 3: PostgreSQL テーブル確認

```bash
kubectl exec -n mlflow-postgres postgres-0 -- psql -U mlflow -d mlflow -c "\dt"
```

MLflow が自動作成したテーブル（experiments, runs, metrics, params 等）を確認する。

### Step 4: MinIO アーティファクト確認

```bash
kubectl port-forward -n mlflow-postgres svc/minio 9001:9001
```

http://localhost:9001 で MinIO Console にアクセスし、`mlflow` バケットに保存されたモデルアーティファクトを確認する（minioadmin / minioadmin123）。

## 学習ポイント

### StatefulSet vs Deployment

| 観点 | StatefulSet (PostgreSQL) | Deployment (MinIO, MLflow) |
|------|--------------------------|----------------------------|
| Pod 名 | `postgres-0`, `postgres-1` （固定） | `minio-xyz` （ランダム） |
| PVC | `volumeClaimTemplates` で Pod ごとに自動作成 | 別途 PVC を定義して参照 |
| スケーリング | 順序付き（0→1→2）| 並列 |
| ユースケース | データベース、ステートフルアプリ | ステートレスアプリ |

PostgreSQL に StatefulSet を使う理由:
- Pod 再スケジュール時に同じ PVC に再接続される必要がある
- 将来レプリケーション構成にする際、安定した Pod 名が必要（primary: postgres-0）

### ConfigMap

- `postgresql.conf`: PostgreSQL の設定ファイルを外部化
- `init-mlflow-db.sql`: 初期化 SQL を `/docker-entrypoint-initdb.d/` にマウント
- `subPath` マウントで個別ファイルとして配置（ディレクトリ丸ごと上書きを避ける）

### Secret

- `postgres-secret`: PostgreSQL の管理者パスワード
- `minio-secret`: MinIO のルートユーザー認証情報
- setup.sh で `kubectl create secret --dry-run=client -o yaml | kubectl apply -f -` による冪等な作成

### Job

- `create-bucket-job`: MinIO にバケットを作成するワンショットタスク
- `backoffLimit: 3` でリトライ回数を制限
- init container ではなく Job を使う理由: MinIO Pod の起動前に init container は実行できない（鶏卵問題）

### PVC (PersistentVolumeClaim)

- PostgreSQL: `volumeClaimTemplates` で StatefulSet に紐づく PVC を自動作成
- MinIO: 同一ファイル内に PVC と Deployment を `---` で区切って定義
- PostgreSQL の `PGDATA` に `subPath` を使う理由: PVC ルートの `lost+found` 等を回避

### Service Discovery

- MLflow → PostgreSQL: `postgres:5432`（Service 名で名前解決）
- MLflow → MinIO: `minio:9000`
- 内部 DNS: `<service>.<namespace>.svc.cluster.local`

## ディレクトリ構成

```
mlflow-postgres/
├── README.md
├── cluster/
│   └── kind-config.yaml              # kind クラスタ設定（worker 2 台）
├── manifests/
│   ├── namespace.yaml                # ns: mlflow-postgres
│   ├── postgres/
│   │   ├── configmap.yaml            # postgresql.conf + init SQL
│   │   ├── statefulset.yaml          # PVC 付き StatefulSet
│   │   └── service.yaml              # ClusterIP :5432
│   ├── minio/
│   │   ├── deployment.yaml           # PVC 付き Deployment
│   │   ├── service.yaml              # API :9000 + Console :9001
│   │   └── create-bucket-job.yaml    # mc で mlflow バケット作成
│   └── mlflow/
│       ├── deployment.yaml           # Tracking Server
│       └── service.yaml              # ClusterIP :5000
└── scripts/
    ├── setup.sh                      # ワンコマンドセットアップ
    ├── demo.sh                       # 4 ステップデモ
    ├── teardown.sh                   # クリーンアップ
    └── train-model.py                # scikit-learn デモスクリプト
```

## トラブルシューティング

### PostgreSQL Pod が起動しない

```bash
kubectl get pods -n mlflow-postgres
kubectl describe pod postgres-0 -n mlflow-postgres
kubectl logs postgres-0 -n mlflow-postgres
```

PVC がプロビジョニングされているか確認:

```bash
kubectl get pvc -n mlflow-postgres
```

### MLflow が PostgreSQL に接続できない

```bash
kubectl logs -n mlflow-postgres -l app=mlflow
```

PostgreSQL が Ready であることを確認:

```bash
kubectl exec -n mlflow-postgres postgres-0 -- pg_isready -U postgres
```

mlflow ユーザーで接続テスト:

```bash
kubectl exec -n mlflow-postgres postgres-0 -- psql -U mlflow -d mlflow -c "SELECT 1;"
```

### バケット作成 Job が失敗する

```bash
kubectl get jobs -n mlflow-postgres
kubectl logs -n mlflow-postgres -l job-name=create-mlflow-bucket
```

MinIO が Ready か確認:

```bash
kubectl exec -n mlflow-postgres deploy/minio -- curl -s http://localhost:9000/minio/health/ready
```

### train-model.py が接続エラーになる

port-forward が起動しているか確認:

```bash
# MLflow Tracking Server
kubectl port-forward -n mlflow-postgres svc/mlflow 5000:5000 &

# MinIO (アーティファクトアップロード用)
kubectl port-forward -n mlflow-postgres svc/minio 9000:9000 &
```

## 本番環境への考慮事項

| 観点 | この学習環境 | 本番環境 |
|------|-------------|---------|
| MLflow イメージ | 起動時に `pip install` で依存追加 | psycopg2-binary, boto3 を含むカスタムイメージ |
| DB 接続文字列 | args に直書き | Secret + 環境変数 (`MLFLOW_BACKEND_STORE_URI`) |
| PostgreSQL | 単一 Pod | レプリケーション（Streaming Replication or Patroni） |
| MinIO | 単一 Pod | 分散モード（4+ ノード） |
| 認証情報 | Secret に平文 | External Secrets Operator + Vault |
| バックアップ | なし | pg_dump / WAL アーカイブ + MinIO バージョニング |
| ネットワーク | 制限なし | NetworkPolicy で Pod 間通信を制限 |
| リソース | 固定 | HPA + VPA で自動スケーリング |

## クリーンアップ

```bash
./scripts/teardown.sh
```
