# NetworkPolicy: 外部 Egress 制御

Default Deny Egress で全 Egress を遮断し、DNS と特定の外部 HTTPS 通信のみを段階的に許可するパターン。Egress 制御でよくある「DNS が死ぬ」ハマりポイントを体験できる。

## アーキテクチャ

```
  namespace: egress-demo          kube-system
  ┌──────────────┐               ┌──────────────┐
  │              │  allow-dns     │              │
  │   client   ──┼──── UDP/TCP 53 ──→ CoreDNS   │
  │   (curl)     │               │              │
  │              │               └──────────────┘
  └──────┬───────┘
         │
         │ allow-external-https
         │ (port 443, クラスタ外 IP のみ)
         ▼
    ┌──────────┐
    │ 外部 API  │  例: httpbin.org
    │ (HTTPS)  │
    └──────────┘
```

**ポリシー一覧:**

| ポリシー               | 効果                                                        |
| ---------------------- | ----------------------------------------------------------- |
| `default-deny-egress`  | namespace 内の全 Pod からの Egress を拒否                   |
| `allow-dns`            | kube-system の CoreDNS (port 53 UDP/TCP) への Egress を許可 |
| `allow-external-https` | クラスタ外 IP への port 443 (HTTPS) のみ許可                |

## 前提条件

- [Docker](https://docs.docker.com/get-docker/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが 4 段階のデモを自動実行する。

## デモシナリオ

### Step 1: ポリシーなし（全通信 OK）

```
DNS 解決 (nslookup httpbin.org)          ✅ OK
外部 HTTPS (curl https://httpbin.org)    ✅ OK
外部 HTTP (curl http://httpbin.org)      ✅ OK
```

### Step 2: default-deny-egress 適用（全通信失敗）

全 Egress が遮断される。DNS 解決すらできなくなる。

```
DNS 解決 (nslookup httpbin.org)          ❌ 失敗
外部 HTTPS (curl https://httpbin.org)    ❌ 失敗
外部 HTTP (curl http://httpbin.org)      ❌ 失敗
```

### Step 3: allow-dns 適用（DNS は解決するが接続タイムアウト）

CoreDNS への Egress を許可すると DNS は解決するが、外部 IP への通信はまだ遮断されている。

```
DNS 解決 (nslookup httpbin.org)          ✅ OK
外部 HTTPS (curl https://httpbin.org)    ❌ タイムアウト
外部 HTTP (curl http://httpbin.org)      ❌ タイムアウト
```

### Step 4: allow-external-https 適用（HTTPS のみ成功）

外部 IP への port 443 を許可すると HTTPS 通信が成功する。HTTP (port 80) は許可していないため失敗する。

```
DNS 解決 (nslookup httpbin.org)          ✅ OK
外部 HTTPS (curl https://httpbin.org)    ✅ OK
外部 HTTP (curl http://httpbin.org)      ❌ タイムアウト
```

### 手動テスト

```bash
# Egress テストを手動実行
./scripts/test-egress.sh

# client Pod から直接テスト
kubectl exec -n egress-demo client -- nslookup httpbin.org
kubectl exec -n egress-demo client -- curl -s --connect-timeout 5 https://httpbin.org/get
kubectl exec -n egress-demo client -- curl -s --connect-timeout 5 http://httpbin.org/get
```

## ディレクトリ構成

```
network-policy-egress/
├── README.md
├── cluster/
│   └── kind-config.yaml          # kind クラスタ設定 (disableDefaultCNI: true)
├── manifests/
│   ├── namespace.yaml            # ns: egress-demo
│   ├── apps/
│   │   └── client.yaml           # curl Pod
│   └── policies/
│       ├── default-deny-egress.yaml
│       ├── allow-dns.yaml        # CoreDNS への Egress 許可
│       └── allow-external-https.yaml  # 外部 HTTPS のみ許可
└── scripts/
    ├── setup.sh                  # ワンコマンドセットアップ (段階的デモ)
    ├── teardown.sh               # クリーンアップ
    └── test-egress.sh            # Egress テスト (DNS / HTTPS / HTTP)
```

## NetworkPolicy 詳細解説

### default-deny-egress

```yaml
spec:
  podSelector: {}       # namespace 内の全 Pod に適用
  policyTypes:
    - Egress
```

namespace 内の全 Pod からの Egress を拒否する。**DNS への通信も遮断される**ため、名前解決ができなくなる。

### allow-dns（ハマりポイント: DNS 許可）

```yaml
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
```

ポイント:

1. **`namespaceSelector` と `podSelector` の組み合わせ**: CoreDNS は `kube-system` namespace にあるため、`namespaceSelector` で namespace を、`podSelector` で CoreDNS Pod を指定する。この 2 つは**同じ `to` 要素内で AND 条件**になる。
2. **UDP と TCP の両方**: DNS は通常 UDP だが、レスポンスが 512 バイトを超える場合 TCP にフォールバックする。両方許可しておくのがベストプラクティス。
3. **`kubernetes.io/metadata.name` ラベル**: Kubernetes 1.21+ で自動付与される namespace ラベル。

### allow-external-https

```yaml
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
```

ポイント:

1. **`ipBlock` でクラスタ外のみ許可**: `0.0.0.0/0` から RFC 1918 プライベートアドレスを除外し、クラスタ外の IP のみを対象にする。
2. **port 443 のみ**: HTTPS のみ許可。HTTP (port 80) は許可しない。
3. **特定ホストへの制限**: NetworkPolicy は IP ベースなのでドメイン名では制御できない。特定ホストのみに限定する場合はそのホストの IP レンジを `cidr` に指定する（CDN 利用時は IP が変わる可能性があるため注意）。

## ハマりポイント

### Egress 制御すると DNS が死ぬ

最もよくあるハマりポイント。default-deny-egress を適用すると Pod から CoreDNS への UDP/TCP 53 番ポートも遮断される。`curl httpbin.org` が失敗する原因は「外部への通信がブロックされた」のではなく「DNS 解決ができない」可能性がある。

対処: 必ず `allow-dns` ポリシーを併用する。

### namespaceSelector と podSelector の AND/OR

`to` 配列内の要素の書き方で AND/OR が変わる:

```yaml
# AND: kube-system namespace 内の kube-dns Pod のみ
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
      podSelector:
        matchLabels:
          k8s-app: kube-dns

# OR: kube-system namespace の全 Pod、または kube-dns ラベルの全 Pod
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    - podSelector:
        matchLabels:
          k8s-app: kube-dns
```

YAML のインデントに注意。`namespaceSelector` と `podSelector` が同じ配列要素（`-` の下）にあれば AND、別々の配列要素（各々に `-`）であれば OR。

### NetworkPolicy は IP ベース

NetworkPolicy はドメイン名をサポートしていない。`httpbin.org` を許可したい場合、その IP アドレスを調べて `ipBlock.cidr` に指定する必要がある。CDN やロードバランサーの IP は変更される可能性があるため、本番で FQDN ベースの制御が必要な場合は Cilium の `CiliumNetworkPolicy` 等を検討する。

## トラブルシューティング

### DNS が解決できない

`allow-dns` ポリシーが kube-dns への通信を許可しているか確認する。`namespaceSelector` と `podSelector` が CoreDNS の実際のラベルと一致している必要がある:

```bash
# allow-dns ポリシーが適用されているか確認
kubectl get networkpolicy -n egress-demo allow-dns

# CoreDNS の Pod ラベルを確認（allow-dns の podSelector と一致するか）
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels

# kube-system namespace のラベルを確認（allow-dns の namespaceSelector と一致するか）
kubectl get ns kube-system --show-labels
```

### curl がタイムアウトする

DNS は解決できるのに接続がタイムアウトする場合、`allow-external-https` ポリシーが適用されているか確認する。

## 本番環境での考慮事項

| 項目                     | デモ                                | 本番                                                    |
| ------------------------ | ----------------------------------- | ------------------------------------------------------- |
| CNI                      | Calico (kind)                       | Calico / Cilium / その他 NetworkPolicy 対応 CNI         |
| 外部通信制限             | 全外部 HTTPS 許可                   | 特定 IP/CIDR のみ許可                                   |
| FQDN ベース制御          | 非対応（標準 NetworkPolicy の制限） | Cilium CiliumNetworkPolicy / Calico GlobalNetworkPolicy |
| DNS 許可                 | CoreDNS のみ                        | NodeLocal DNSCache 使用時は追加許可が必要               |
| Ingress 制御             | なし                                | Egress と併せて Ingress も default-deny                 |
| 監視                     | なし                                | Egress トラフィックのログ・監査                         |
| プライベートアドレス除外 | RFC 1918 のみ                       | クラスタ固有の CIDR に合わせて調整                      |

## クリーンアップ

```bash
./scripts/teardown.sh
```
