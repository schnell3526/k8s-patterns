# PostgreSQL 挙動調査メモ

## 接続

```bash
# mlflow ユーザーで接続
kubectl exec -n mlflow-postgres -it postgres-0 -- psql -U mlflow -d mlflow

# postgres (管理者) ユーザーで接続
kubectl exec -n mlflow-postgres -it postgres-0 -- psql -U postgres
```

## 調査ログ

