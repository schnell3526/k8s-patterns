"""
scikit-learn の Wine データセットで RandomForest 分類モデルを学習し、
MLflow Tracking Server に実験結果を記録するデモスクリプト。

使い方:
  # port-forward を起動した状態で実行
  kubectl port-forward -n mlflow-postgres svc/mlflow 5000:5000 &
  kubectl port-forward -n mlflow-postgres svc/minio 9000:9000 &
  uv run --with mlflow --with scikit-learn --with boto3 scripts/train-model.py
"""

import os

import mlflow
from sklearn.datasets import load_wine
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split

# MLflow Tracking Server への接続設定
mlflow.set_tracking_uri("http://localhost:5000")

# MinIO (S3 互換) のエンドポイント設定
os.environ["MLFLOW_S3_ENDPOINT_URL"] = "http://localhost:9000"
os.environ["AWS_ACCESS_KEY_ID"] = "minioadmin"
os.environ["AWS_SECRET_ACCESS_KEY"] = "minioadmin123"

# Wine データセットの読み込み
wine = load_wine()
X_train, X_test, y_train, y_test = train_test_split(
    wine.data, wine.target, test_size=0.2, random_state=42
)

# MLflow 実験の設定
mlflow.set_experiment("wine-classification")

# ハイパーパラメータ
params = {
    "n_estimators": 100,
    "max_depth": 5,
    "random_state": 42,
}

with mlflow.start_run():
    # パラメータの記録
    mlflow.log_params(params)

    # モデルの学習
    model = RandomForestClassifier(**params)
    model.fit(X_train, y_train)

    # 評価
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)

    # メトリクスの記録
    mlflow.log_metric("accuracy", accuracy)
    mlflow.log_metric("n_features", X_train.shape[1])
    mlflow.log_metric("n_train_samples", X_train.shape[0])
    mlflow.log_metric("n_test_samples", X_test.shape[0])

    # モデルのアーティファクト保存（MinIO の s3://mlflow/ に保存される）
    mlflow.sklearn.log_model(model, name="random-forest-wine")

    print(f"Accuracy: {accuracy:.4f}")
    print(f"Run ID: {mlflow.active_run().info.run_id}")
    print(f"Experiment: wine-classification")
    print(f"Tracking URI: {mlflow.get_tracking_uri()}")
    print("MLflow UI で結果を確認してください: http://localhost:5000")
