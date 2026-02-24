# コンポーネントバージョン一覧

## Helm チャート

| コンポーネント | チャート                | バージョン | リポジトリ                            |
| -------------- | ----------------------- | ---------- | ------------------------------------- |
| Tetragon       | cilium/tetragon         | 1.6.0      | https://helm.cilium.io                |
| Loki           | grafana/loki            | 6.53.0     | https://grafana.github.io/helm-charts |
| Fluent Bit     | fluent/fluent-bit       | 0.55.0     | https://fluent.github.io/helm-charts  |
| Grafana        | grafana/grafana         | 10.5.15    | https://grafana.github.io/helm-charts |
| Envoy Gateway  | envoyproxy/gateway-helm | v1.7.0     | oci://docker.io                       |

## コンテナイメージ（アプリケーション）

| コンポーネント | イメージ                          | タグ                         |
| -------------- | --------------------------------- | ---------------------------- |
| MLflow         | ghcr.io/mlflow/mlflow             | v3.10.0                      |
| Keycloak       | quay.io/keycloak/keycloak         | 26.5.4                       |
| OAuth2 Proxy   | quay.io/oauth2-proxy/oauth2-proxy | v7.14.2                      |
| PostgreSQL     | postgres                          | 16.12                        |
| MinIO Server   | minio/minio                       | RELEASE.2025-09-07T16-13-09Z |
| MinIO Client   | minio/mc                          | RELEASE.2025-08-13T08-35-41Z |
| Nginx          | nginx                             | 1.29                         |

## コンテナイメージ（ユーティリティ / テスト）

| コンポーネント | イメージ            | タグ   |
| -------------- | ------------------- | ------ |
| cURL           | curlimages/curl     | 8.18.0 |
| HTTP Echo      | hashicorp/http-echo | 1.0.0  |
| Netshoot       | nicolaka/netshoot   | latest |

## 外部依存（マニフェスト URL 直接適用）

| コンポーネント           | バージョン | ソース                          |
| ------------------------ | ---------- | ------------------------------- |
| Calico (Tigera Operator) | v3.29.2    | github.com/projectcalico/calico |

## CRD API バージョン

| API グループ              | バージョン | リソース                               |
| ------------------------- | ---------- | -------------------------------------- |
| gateway.networking.k8s.io | v1         | GatewayClass, Gateway, HTTPRoute       |
| cilium.io                 | v1alpha1   | TracingPolicy, TracingPolicyNamespaced |
| kind.x-k8s.io            | v1alpha4   | Cluster                                |
