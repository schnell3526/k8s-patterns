# Cilium + Hubble: NetworkPolicy の可視化

[Zero Trust パターン](../network-policy-zero-trust/)と同じ `networking.k8s.io/v1` NetworkPolicy を Cilium 上で再現し、Hubble でトラフィックフローを可視化するパターン。

同じマニフェストが CNI を変えても同じ挙動をすることを示す（Kubernetes の IF / 実装分離）。Calico にはない eBPF ベースの観測機能を Hubble で体験する。

## アーキテクチャ

```
                  NetworkPolicy (Ingress 制御)
                  ┌──────────────────────────────────┐
                  │    namespace: cilium-hubble-demo  │
                  │                                   │
  ┌────────┐  allow   ┌──────────┐  allow   ┌─────────┐
  │ client ├────────→ │ frontend ├────────→ │ backend │
  │ (curl) │  :80     │ (nginx)  │  :80     │ (nginx) │
  └────┬───┘          └──────────┘          └─────────┘
       │                                        ▲
       │              default-deny-ingress       │
       └──────────── BLOCKED ───────────────────┘
            client → backend は拒否

  ════════════════════════════════════════════════
  Hubble (eBPF)  ← 全フローを観測・記録
  ════════════════════════════════════════════════
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
- [Cilium CLI](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/#install-the-cilium-cli)
- [Hubble CLI](https://docs.cilium.io/en/stable/gettingstarted/hubble_setup/#install-the-hubble-client)

## クイックスタート

```bash
./scripts/setup.sh
```

セットアップスクリプトが以下を自動実行する:

1. kind クラスタ作成（デフォルト CNI 無効）
2. Cilium CNI インストール
3. Hubble 有効化（UI 含む）
4. アプリケーション（frontend, backend, client）デプロイ

セットアップ完了後、デモを実行する:

```bash
./scripts/demo.sh
```

## デモシナリオ

### Step 1: ポリシー適用前（全通信 OK）

NetworkPolicy がない状態では namespace 内の全 Pod 間で自由に通信できる。

```
client → frontend   ✅ OK (HTTP 200)
client → backend    ✅ OK (HTTP 200)
frontend → backend  ✅ OK (HTTP 200)
```

Hubble で全フローが FORWARDED であることを確認:

```
hubble observe --namespace cilium-hubble-demo --since 30s
```

### Step 2: ポリシー適用後（制限あり）

`default-deny-ingress` + 個別許可ポリシーを適用すると、明示的に許可された通信のみ成功する。

```
client → frontend   ✅ OK  (allow-frontend-from-client で許可)
client → backend    ❌ 拒否 (default-deny-ingress でブロック)
frontend → backend  ✅ OK  (allow-backend-from-frontend で許可)
```

Hubble で FORWARDED と DROPPED を確認:

```bash
# 許可されたフロー
hubble observe --namespace cilium-hubble-demo --verdict FORWARDED --type policy-verdict --since 30s

# 拒否されたフロー
hubble observe --namespace cilium-hubble-demo --verdict DROPPED --type policy-verdict --since 30s
```

## Hubble の読み方

`hubble observe` の出力は以下の形式で表示される:

```
TIMESTAMP  SOURCE             DESTINATION        TYPE          VERDICT   SUMMARY
<time>     cilium-hubble-demo/client  cilium-hubble-demo/frontend  policy-verdict  FORWARDED  TCP Flags: SYN
<time>     cilium-hubble-demo/client  cilium-hubble-demo/backend   policy-verdict  DROPPED    TCP Flags: SYN
```

| フィールド  | 説明                                                             |
| ----------- | ---------------------------------------------------------------- |
| SOURCE      | 送信元 Pod（namespace/pod 形式）                                 |
| DESTINATION | 宛先 Pod または Service                                          |
| TYPE        | `policy-verdict` はポリシー判定イベント。`l7` は L7 プロキシ経由 |
| VERDICT     | `FORWARDED`（許可）/ `DROPPED`（拒否）/ `AUDIT`（監査モード）    |
| SUMMARY     | TCP フラグやプロトコル情報                                       |

## Hubble UI

Hubble UI はブラウザベースのフローマップを提供する。別ターミナルで以下を実行する:

```bash
cilium hubble ui
```

ブラウザが自動的に開き、namespace を選択するとフローマップが表示される。`cilium-hubble-demo` を選択すると:

- Pod 間の通信が矢印で可視化される
- 緑の矢印は FORWARDED（許可）、赤の矢印は DROPPED（拒否）
- 各矢印をクリックするとフローの詳細が確認できる

## Calico との比較

このパターンは [Zero Trust パターン](../network-policy-zero-trust/) と**同じ `networking.k8s.io/v1` NetworkPolicy マニフェスト**を使用している（namespace 名のみ異なる）。これが Kubernetes の IF / 実装分離パターンの実例である:

| 項目              | Zero Trust (Calico)    | このパターン (Cilium)          |
| ----------------- | ---------------------- | ------------------------------ |
| CNI               | Calico                 | Cilium                         |
| NetworkPolicy API | `networking.k8s.io/v1` | `networking.k8s.io/v1`（同一） |
| マニフェスト      | 同一スキーマ           | 同一スキーマ                   |
| フロー可視化      | なし                   | Hubble（CLI + UI）             |
| 実装技術          | iptables               | eBPF                           |
| 拡張ポリシー      | Calico NetworkPolicy   | CiliumNetworkPolicy（L7 対応） |

同じ `NetworkPolicy` リソースが CNI 実装に依存せずに動作することで、マニフェストのポータビリティが確認できる。

## ディレクトリ構成

```
cilium-hubble/
├── README.md
├── cluster/
│   └── kind-config.yaml          # kind クラスタ設定 (disableDefaultCNI: true)
├── manifests/
│   ├── namespace.yaml            # ns: cilium-hubble-demo
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
    ├── demo.sh                   # デモ実行 (Hubble 可視化含む)
    ├── test-connectivity.sh      # 通信テスト (許可/拒否を自動検証)
    └── teardown.sh               # クリーンアップ
```

## トラブルシューティング

### Cilium の状態確認

```bash
cilium status
```

全コンポーネントが `OK` と表示されることを確認する。`Hubble Relay` が `disabled` の場合は `cilium hubble enable` を実行する。

### Hubble の状態確認

```bash
hubble status
```

`Hubble is ok` と表示されない場合:

```bash
# Hubble Relay Pod の確認
kubectl get pods -n kube-system -l k8s-app=hubble-relay

# port-forward の再起動
cilium hubble port-forward &
```

### テストが期待と異なる結果になる

Cilium のポリシー適用状態を確認する（NetworkPolicy の汎用的なデバッグ方法は [patterns/README.md](../README.md) を参照）:

```bash
cilium policy get -n cilium-hubble-demo
```

## クリーンアップ

```bash
./scripts/teardown.sh
```
