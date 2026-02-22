# k8s-patterns

Kubernetes ネイティブなシステム設計パターンのリポジトリ。

## パターン一

| ディレクトリ                                              | 概要                                                      |
| --------------------------------------------------------- | --------------------------------------------------------- |
| [oauth2-proxy-oidc](./oauth2-proxy-oidc/)                 | oauth2-proxy + Keycloak による OIDC 認証                  |
| [network-policy-zero-trust](./network-policy-zero-trust/) | Default Deny Ingress + 個別許可による Zero Trust 通信制御 |
| [network-policy-egress](./network-policy-egress/)         | Default Deny Egress + DNS 許可 + 外部 HTTPS 制御          |
| [cilium-hubble](./cilium-hubble/)                         | Cilium + Hubble による NetworkPolicy の可視化             |

## Kubernetes の IF / 実装分離パターン

Kubernetes のコアは API とインターフェース（IF）だけを持ち、実際の処理はプラグインに委譲する設計で一貫している。

### コンテナランタイム

| IF                                    | K8s が定義するもの                                                                                                               | 実装 (プラグイン)                     |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| **OCI** (Open Container Initiative)   | コンテナイメージフォーマットとランタイム実行仕様の標準。K8s が定義したものではなく業界標準団体の仕様だが、K8s エコシステムの土台 | runc, crun, youki, kata-containers 等 |
| **CRI** (Container Runtime Interface) | kubelet とコンテナランタイム間の gRPC API。Pod/コンテナの作成・削除・状態取得を抽象化                                            | containerd, CRI-O                     |

### ネットワーク

| IF                                    | K8s が定義するもの                                                                                                                 | 実装 (プラグイン)                                             |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **CNI** (Container Network Interface) | Pod ネットワークの仕様。Pod 起動時の IP 割り当て・ルーティング設定のプラグイン IF                                                  | Calico, Cilium, Flannel, Weave, AWS VPC CNI 等                |
| **NetworkPolicy**                     | L3/L4 トラフィック制御の API スキーマ                                                                                              | CNI プラグインが実装（Calico, Cilium 等）。kindnet 等は未実装 |
| **Gateway API**                       | L4/L7 ルーティングの CRD (SIG-Network が策定)。Ingress の後継であり、GAMMA イニシアティブによりサービスメッシュ IF (旧 SMI) も統合 | Envoy Gateway, nginx-gateway-fabric, Istio, Cilium 等         |
| **Ingress**                           | L7 HTTP ルーティングの API スキーマ。Gateway API への移行が進行中                                                                  | ingress-nginx, ALB Controller, Traefik 等                     |

### ストレージ

| IF                                    | K8s が定義するもの                                         | 実装 (プラグイン)                         |
| ------------------------------------- | ---------------------------------------------------------- | ----------------------------------------- |
| **CSI** (Container Storage Interface) | 永続ストレージのプロビジョニング・アタッチ・マウントの仕様 | EBS CSI, GCE PD CSI, NFS CSI, Ceph CSI 等 |

### デバイス・リソース

| IF                                   | K8s が定義するもの                                                                                                                             | 実装 (プラグイン)                                             |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **Device Plugin API**                | ノード上の特殊ハードウェア（GPU, FPGA 等）を kubelet に登録し、Pod にリソースとして割り当てる API                                              | NVIDIA Device Plugin, Intel Device Plugins 等                 |
| **CDI** (Container Device Interface) | Device Plugin と連携し、コンテナランタイムが特殊デバイスをコンテナに組み込むための標準仕様。デバイスファイルのマウントやドライバ設定を抽象化   | NVIDIA Container Toolkit (CDI 対応), Intel CDI 等             |
| **NRI** (Node Resource Interface)    | コンテナランタイムのライフサイクルイベント（作成・開始・停止）にフックし、cgroup 制御や CPU ピンニング等のカスタム処理を挿入するフレームワーク | Topology-aware scheduling plugins, Resource policy plugins 等 |

### 全体像

```
kubectl apply
    │
    ▼
API Server → Scheduler → kubelet
                            │
                ┌───────────┼───────────────┐
                ▼           ▼               ▼
              CRI         CNI             CSI
          (コンテナ)   (ネットワーク)   (ストレージ)
                │
         ┌──────┼──────┐
         ▼      ▼      ▼
        OCI    CDI    NRI
      (実行) (デバイス)(リソース)
```

この構造により:
- K8s 本体はパケット制御もストレージ操作もコンテナ実行も一切やらない
- 同じマニフェストが異なるプラグイン環境で動作する（ポータビリティ）
- IF の実装が欠けていても K8s はエラーを出さないことがある。NetworkPolicy を書いて「効かない」場合、CNI が未対応なだけで**単に無視される**ので気づきにくい

## Kubernetes ネットワーク関連リソース

### ネットワークポリシー

| リソース      | API グループ           | スコープ  | 説明                                                                                                                                                          |
| ------------- | ---------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NetworkPolicy | `networking.k8s.io/v1` | Namespace | Pod 間および外部との L3/L4 トラフィック制御。`podSelector` と `namespaceSelector` で対象を指定し、Ingress/Egress を許可・拒否する。CNI プラグインが実装を担う |

### サービスディスカバリ

| リソース      | API グループ          | スコープ  | 説明                                                                                                                                                                                                                                                                      |
| ------------- | --------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service       | `v1` (core)           | Namespace | Pod へのアクセスを抽象化するリソース。種類が複数ある: **ClusterIP**（クラスタ内部 IP）、**NodePort**（ノードのポートを公開）、**LoadBalancer**（外部 LB を作成）、**ExternalName**（外部 DNS 名への CNAME）、**Headless**（`clusterIP: None`、個別 Pod の IP を直接返す） |
| EndpointSlice | `discovery.k8s.io/v1` | Namespace | Service のバックエンド Pod の IP とポートを管理する。Service 作成時に自動生成される。手動作成でクラスタ外のサービスを Service 経由でアクセス可能にできる                                                                                                                  |

### L7 ルーティング

| リソース       | API グループ                         | スコープ  | 説明                                                                                                                                                                 |
| -------------- | ------------------------------------ | --------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ingress        | `networking.k8s.io/v1`               | Namespace | HTTP/HTTPS の L7 ルーティング。ホストベース・パスベースのルーティング、TLS 終端を提供する。実装は Ingress Controller（nginx, Traefik 等）が担う                      |
| IngressClass   | `networking.k8s.io/v1`               | Cluster   | どの Ingress Controller が Ingress を処理するかを指定する。複数の Controller を使い分ける場合に必要                                                                  |
| Gateway        | `gateway.networking.k8s.io/v1`       | Namespace | Gateway API のエントリポイント。Ingress の後継にあたる。インフラ提供者とアプリ開発者の責務分離、クロス namespace 参照、トラフィック分割など Ingress にない機能を持つ |
| HTTPRoute      | `gateway.networking.k8s.io/v1`       | Namespace | Gateway API の HTTP ルーティングルール。ヘッダベースマッチ、weight によるトラフィック分割（カナリアリリース）、リクエスト/レスポンスの書き換えが可能                 |
| GRPCRoute      | `gateway.networking.k8s.io/v1`       | Namespace | Gateway API の gRPC ルーティングルール                                                                                                                               |
| TCPRoute       | `gateway.networking.k8s.io/v1alpha2` | Namespace | Gateway API の L4 TCP ルーティング。DB やメッセージキュー等の非 HTTP トラフィックに使う                                                                              |
| TLSRoute       | `gateway.networking.k8s.io/v1alpha2` | Namespace | Gateway API の TLS ルーティング。SNI ベースでバックエンドを振り分ける                                                                                                |
| ReferenceGrant | `gateway.networking.k8s.io/v1beta1`  | Namespace | Gateway API でクロス namespace 参照を許可するためのリソース。別 namespace の Service を HTTPRoute から参照する場合に必要                                             |

### DNS

| リソース / 設定 | API グループ | スコープ | 説明                                                                                                                                                         |
| --------------- | ------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Service DNS     | —            | —        | Service を作成すると `<service>.<namespace>.svc.cluster.local` の DNS レコードが自動登録される。Headless Service の場合は個別 Pod の A レコードが返る        |
| Pod `dnsPolicy` | `v1` (core)  | Pod spec | Pod の DNS 解決方法を制御する。`ClusterFirst`（デフォルト、クラスタ DNS → 上流）、`Default`（ノードの DNS 設定を継承）、`None`（`dnsConfig` で完全手動設定） |
| Pod `dnsConfig` | `v1` (core)  | Pod spec | Pod の `/etc/resolv.conf` を直接カスタマイズする。カスタム nameserver や search ドメインを追加できる                                                         |

## セキュリティ関連リソース

| リソース             | API グループ                   | スコープ           | 説明                                                                                                                |
| -------------------- | ------------------------------ | ------------------ | ------------------------------------------------------------------------------------------------------------------- |
| ServiceAccount       | `v1` (core)                    | Namespace          | Pod のアイデンティティ。Pod が Kubernetes API にアクセスする際の認証に使う。RBAC と組み合わせて権限を制御する       |
| Role                 | `rbac.authorization.k8s.io/v1` | Namespace          | namespace スコープの権限定義。特定の API リソースに対する操作（get, list, create, delete 等）を定義する             |
| ClusterRole          | `rbac.authorization.k8s.io/v1` | Cluster            | クラスタスコープの権限定義。namespace をまたぐリソースや全 namespace 共通の権限に使う                               |
| RoleBinding          | `rbac.authorization.k8s.io/v1` | Namespace          | Role を ServiceAccount / User / Group に紐づける                                                                    |
| ClusterRoleBinding   | `rbac.authorization.k8s.io/v1` | Cluster            | ClusterRole をクラスタ全体で紐づける                                                                                |
| SecurityContext      | `v1` (core)                    | Pod/Container spec | Pod / Container の権限を制限する設定。`runAsNonRoot`、`readOnlyRootFilesystem`、`capabilities` の drop/add 等       |
| PodSecurityAdmission | `v1` (core)                    | Namespace ラベル   | namespace ラベルで Pod のセキュリティ基準を強制する（Privileged / Baseline / Restricted）。PodSecurityPolicy の後継 |

## リソース管理

| リソース      | API グループ           | スコープ  | 説明                                                                                                                                          |
| ------------- | ---------------------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| ResourceQuota | `v1` (core)            | Namespace | namespace 単位の CPU / メモリ / Pod 数 / Service 数等の上限。チーム間でクラスタリソースを公平に分配する                                       |
| LimitRange    | `v1` (core)            | Namespace | namespace 内の個々の Pod / Container のリソースデフォルト値・上下限を設定する。ResourceQuota と併用して「requests/limits 未指定の Pod」を防ぐ |
| PriorityClass | `scheduling.k8s.io/v1` | Cluster   | Pod のスケジューリング優先度。リソース不足時に低優先度の Pod を追い出して高優先度の Pod を配置する（Preemption）                              |

## スケジューリング

| リソース / 設定               | API グループ | スコープ        | 説明                                                                                                                       |
| ----------------------------- | ------------ | --------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Taint / Toleration            | `v1` (core)  | Node / Pod spec | ノードに Taint を付け、対応する Toleration を持つ Pod のみ配置を許可する。GPU ノードや専用ノードの分離に使う               |
| NodeAffinity                  | `v1` (core)  | Pod spec        | Pod を特定のノード（ラベル条件）に配置する。`requiredDuringScheduling`（必須）と `preferredDuringScheduling`（優先）がある |
| PodAffinity / PodAntiAffinity | `v1` (core)  | Pod spec        | Pod 同士を同じノード/ゾーンに配置、または分散配置する。レイテンシ削減や可用性向上に使う                                    |
| TopologySpreadConstraints     | `v1` (core)  | Pod spec        | AZ やノード間で Pod を均等に分散する。PodAntiAffinity より柔軟な分散制御が可能                                             |

## 可用性

| リソース                      | API グループ            | スコープ  | 説明                                                                                                               |
| ----------------------------- | ----------------------- | --------- | ------------------------------------------------------------------------------------------------------------------ |
| PodDisruptionBudget (PDB)     | `policy/v1`             | Namespace | ノードドレインやローリングアップデート時に最小稼働 Pod 数を保証する。`minAvailable` または `maxUnavailable` で指定 |
| HorizontalPodAutoscaler (HPA) | `autoscaling/v2`        | Namespace | CPU / メモリ / カスタムメトリクスに基づいて Pod 数を自動スケールする                                               |
| VerticalPodAutoscaler (VPA)   | `autoscaling.k8s.io/v1` | Namespace | Pod の requests/limits を使用実績に基づいて自動調整する。HPA とは排他的に使うことが多い                            |
