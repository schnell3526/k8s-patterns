---
name: update-helm-versions
description: docs/versions.md の Helm チャートバージョンを最新に更新する
allowed-tools: Bash, Read, Edit
---

## 手順

1. `docs/versions.md` を読み込み、Helm チャートセクションから各チャートの情報を取得する
2. 各チャートについて最新バージョンを確認する:
   - 通常のリポジトリ（https://〜）の場合: `helm repo add` → `helm repo update` → `helm search repo <chart> --versions | head -2` で最新バージョンを取得
   - OCI リポジトリ（oci://〜）の場合: `helm show chart oci://<registry>/<chart>` で最新バージョンを取得
3. 現在のバージョンと最新バージョンを比較し、差分があるものを一覧表示する
4. ユーザーに更新内容を確認してから `docs/versions.md` を書き換える
5. 対応する `scripts/setup.sh` 内の `--version` 指定も同時に更新する

## 注意事項

- helm repo 名はチャート名のスラッシュより前の部分を使う（例: `grafana/loki` → repo 名は `grafana`）
- リポジトリ URL は `docs/versions.md` に記載されているものを使う
- 更新がない場合は「すべて最新です」と報告して終了する
