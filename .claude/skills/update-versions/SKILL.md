---
name: update-versions
description: docs/versions.md の Helm チャートバージョンとコンテナイメージタグを最新に更新する
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, AskUserQuestion, WebFetch
---

## 概要

`docs/versions.md` に記載されている Helm チャートバージョンおよびコンテナイメージタグを最新に更新する。

## 手順

### 1. バージョン情報の読み込み

`docs/versions.md` を読み込み、以下のセクションから各コンポーネントの情報を取得する:
- **Helm チャート** セクション
- **コンテナイメージ（アプリケーション）** セクション
- **コンテナイメージ（ユーティリティ / テスト）** セクション

### 2. Helm チャートの最新バージョン確認

各チャートについて最新バージョンを確認する:
- 通常のリポジトリ（https://〜）の場合: `helm repo add` → `helm repo update` → `helm search repo <chart> --versions | head -2` で最新バージョンを取得
- OCI リポジトリ（oci://〜）の場合: `helm show chart oci://<registry>/<chart>` で最新バージョンを取得

### 3. コンテナイメージの最新タグ確認

各イメージについてレジストリ API で最新タグを確認する:
- **GitHub Releases がある場合** (ghcr.io, minio, oauth2-proxy 等): `curl -s "https://api.github.com/repos/<owner>/<repo>/releases/latest"` で取得
- **Quay.io**: `curl -s "https://quay.io/api/v1/repository/<namespace>/<repo>/tag/?limit=50&onlyActiveTags=true"` で取得
- **Docker Hub (library/)**: `curl -s "https://hub.docker.com/v2/repositories/library/<image>/tags/?page_size=100"` で取得
- **Docker Hub (org/)**: `curl -s "https://hub.docker.com/v2/repositories/<org>/<image>/tags/?page_size=100"` で取得
- **latest タグのみのイメージ** (nicolaka/netshoot 等): スキップ

タグのフィルタリングは現在のバージョンパターンに合わせる:
- セマンティックバージョン (v1.2.3, 1.2.3): 同一メジャーバージョン内の最新を取得
- マイナーバージョン指定 (16.6, 1.29): 同一メジャーバージョン内の最新マイナーを取得
- 日付ベース (RELEASE.2024-...): 最新の RELEASE タグを取得

### 4. 差分表示とユーザー確認

現在のバージョンと最新バージョンを比較し、差分があるものを一覧表示する。
メジャーバージョンアップがある場合は破壊的変更の可能性を明記する。
ユーザーに更新内容を確認してから次のステップに進む。

### 5. ファイルの更新

- `docs/versions.md` のバージョン表を書き換える
- `Grep` で対象イメージタグ / `--version` 指定を含むマニフェスト・スクリプトを検索し、同時に更新する
  - `scripts/setup.sh` 内の `--version` 指定
  - `manifests/**/*.yaml` 内の `image:` タグ

### 6. 更新がない場合

「すべて最新です」と報告して終了する。

## 注意事項

- helm repo 名はチャート名のスラッシュより前の部分を使う（例: `grafana/loki` → repo 名は `grafana`）
- リポジトリ URL は `docs/versions.md` に記載されているものを使う
- 並列実行できるバージョンチェックは並列で実行し、効率化する
- Docker Hub API の `ordering` パラメータは信頼性が低いため、Python でソートする
