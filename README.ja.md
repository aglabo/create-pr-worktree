---
title: create-pr-worktree
description:Worktree-based GitHub Actions toolkit for creating pull requests safely and reproducibly
---

[![CI Status](https://github.com/atsushifx/create-pr-worktree/workflows/CI/badge.svg)](https://github.com/atsushifx/create-pr-worktree/actions)
[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/atsushifx/create-pr-worktree/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

Git Worktree を活用した安全で透明性の高い PR 自動化のための Composite Actions セット。

## 特徴

**安全な作業環境の分離**: Git Worktree 戦略により、main ブランチを汚さずに PR 作業できます。

**検証可能なコミット署名**: Sigstore gitsign による OIDC ベースのキーレス署名で、透明性を確保します。

**3つのComposite Actions**: セットアップ、PR 作成、クリーンアップを独立したアクションとして提供し、再利用性を高めます。

## クイックスタート

以下は、最小構成で動作するワークフロー例です。コピー&ペーストで使用できます。

```yaml
name: Auto PR with Worktree
on: push

permissions:
  id-token: write # Sigstore署名に必要
  contents: write # Gitオペレーションとラベル作成に必要
  pull-requests: write # PR作成に必要

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      # 注: working-directoryを指定しないステップは、ベースディレクトリで実行されます

      # リポジトリのチェックアウト
      - uses: actions/checkout@v4

      # 環境検証 (推奨: なくても動作しますが、動作環境を保証するために推奨)
      - name: Validate environment
        uses: aglabo/.github/.github/actions/validate-environment@r1.2.0
        with:
          additional_apps: "gh|gh|regex:version ([0-9.]+)|2.0"

      # 1. Worktree作成とgitsign設定
      - name: Setup PR worktree
        id: setup
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: auto-fix/${{ github.ref_name }}
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # 2. Worktree内で作業
      - name: Make changes in worktree
        working-directory: ${{ steps.setup.outputs.worktree-path }}
        run: |
          echo "fix" > fix.txt
          git add fix.txt
          git commit -m "fix: Apply auto-fix"
          git push origin auto-fix/${{ github.ref_name }}

      # 3. PR作成
      - name: Create PR
        uses: ./.github/actions/create-pr-from-worktree
        with:
          pr-branch: auto-fix/${{ github.ref_name }}
          pr-title: "fix: Apply auto-fix"
          pr-body: "Auto-generated PR"
          labels: "automated,fix"

      # 4. Worktreeクリーンアップ (常に実行)
      - name: Cleanup worktree
        if: always() && steps.setup.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

**期待される結果**: このワークフローを実行すると、自動的に PR が作成され、Sigstore で署名されたコミットが含まれます。

**重要な注意点**:

- PR 作成ステップには`working-directory`を指定していません。GitHub Actions の仕様上、ステップごとに作業ディレクトリはリセットされ、ベースディレクトリで実行されます。
- `steps.setup.outputs.worktree-path`は、Worktree 内で作業するステップの`working-directory`にのみ使用してください。

## 3つのComposite Actions

このプロジェクトは、以下の 3つの Composite Actions で構成されています。

```text
1. pr-worktree-setup → 2. create-pr-from-worktree → 3. pr-worktree-cleanup
```

### 1. pr-worktree-setup

Worktree の作成と Sigstore gitsign の設定をします。
新しいブランチの Worktree を作成し、コミット署名用の gitsign を自動設定します。

主要な出力 (契約)

| 名前            | 意味                           | 使用方法                                                     |
| --------------- | ------------------------------ | ------------------------------------------------------------ |
| `worktree-path` | 作成された Worktree の絶対パス | Worktree 内で作業するステップの`working-directory`にのみ使用 |

[詳細はpr-worktree-setupのREADMEを参照](./.github/actions/pr-worktree-setup/README.md)

### 2. create-pr-from-worktree

Worktree 内で作業したコミットから PR を作成または更新します。
ベースブランチの自動検出、ラベル付け、自動マージ設定をサポートします。

⚠ **重要な制約**:
このアクションは、ベースディレクトリで実行されることを前提とします。
このステップに`working-directory`を指定しないでください。ベースブランチの誤検出の原因となります。

[詳細はcreate-pr-from-worktreeのREADMEを参照](./.github/actions/create-pr-from-worktree/README.md)

### 3. pr-worktree-cleanup

作業完了後に Worktree を安全に削除します。
コミットされていない変更の検出や、複数の Worktree が存在する場合のスキップ機能を備えています。

[詳細はpr-worktree-cleanupのREADMEを参照](./.github/actions/pr-worktree-cleanup/README.md)

**なぜ3つに分けたか**: 関心の分離と再利用性を重視した設計です。各アクションを独立して検証・テストでき、組み合わせを変更できます。

## アーキテクチャ

### Worktree戦略

```text
┌─────────────────────────────────────────────┐
│ Main Repository (main - 常にクリーン)       │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-setup
┌─────────────────────────────────────────────┐
│ Worktree (分離された作業環境)               │
│ - PRブランチにチェックアウト                │
│ - Sigstore gitsign設定済み                  │
│ - 作業: git commit → git push               │
│   (working-directory指定)                   │
└─────────────────────────────────────────────┘
              ↓ create-pr-from-worktree (ベースディレクトリ)
┌─────────────────────────────────────────────┐
│ Main Repository (mainのまま)                │
│ - create-pr-from-worktree実行               │
│ - ベースブランチ自動検出 (main)             │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-cleanup (ベースディレクトリ)
┌─────────────────────────────────────────────┐
│ クリーンアップ完了 - mainはクリーンなまま   │
└─────────────────────────────────────────────┘
```

**mainブランチが汚れない理由**: Worktree 内で作業するため、main ブランチには一切影響しません。PR 作業が失敗しても、main は常にクリーンな状態を保ちます。

**ベースブランチ自動検出の仕組み**: `git symbolic-ref --short HEAD`でチェックアウト中のブランチを取得します。各ステップはデフォルトでベースディレクトリにて実行されるため、main が自動的にベースブランチとして検出されます。

## セキュリティ機能

### OIDCベースキーレス署名

GitHub Actions の OIDC トークンを使用した一時的な証明書による署名。GPG キーの管理が不要で、証明書はワークフロー実行ごとに短命です。

### Rekor透明性ログ

すべての署名が Rekor に記録され、公開監査が可能です。署名イベントの透明性を確保します。

### Git設定

Worktree 内で自動的に以下の設定が適用されます。

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
```

## 使用例

### 基本パターン

3つのアクションをすべて使用する標準的なワークフローです。

```yaml
# 注: working-directoryを指定しないステップは、ベースディレクトリで実行されます

# 環境検証 (推奨: なくても動作しますが、動作環境を保証するために推奨)
- uses: aglabo/.github/.github/actions/validate-environment@r1.2.0
  with:
    additional_apps: "gh|gh|regex:version ([0-9.]+)|2.0"

- uses: ./.github/actions/pr-worktree-setup
  id: setup
  with:
    branch-name: feature/my-feature
    worktree-dir: ${{ runner.temp }}/worktree

# Worktree内で作業
- working-directory: ${{ steps.setup.outputs.worktree-path }}
  run: |
    # 変更を加える
    git add .
    git commit -m "feat: Add new feature"
    git push origin feature/my-feature

# PR作成 (stepが変わったためベースディレクトリで実行される)
- uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description of changes"

# クリーンアップ (常に実行)
- if: always() && steps.setup.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

### ラベルと自動マージの設定

```yaml
- uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description of changes"
    labels: "enhancement,automated" # カンマ区切りでラベル指定
    merge-method: "squash" # squash/merge/rebase/never
```

### カスタムユーザー設定

デフォルトの`github-actions[bot]`以外のユーザー名とメールアドレスを使用できます。

```yaml
- uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-feature
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

### ❌ やってはいけない例

以下は、ベースブランチの誤検出を引き起こす誤った使用例です。

```yaml
# ❌ 悪い例: PR作成にworking-directoryを指定している
- name: Create PR
  working-directory: ${{ steps.setup.outputs.worktree-path }}
  uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description"
```

**問題点**: `create-pr-from-worktree`は現在チェックアウトされているブランチをベースブランチとして検出します。Worktree 内で実行すると、PR ブランチ自体がベースとして誤検出されます。

**正しい例**: `working-directory`を指定せず、ベースディレクトリで実行します。

```yaml
# ✅ 正しい例: working-directoryを指定しない
- name: Create PR
  uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description"
```

## トラブルシューティング

### Worktreeクリーンアップが実行されない

**原因**: `if: always()`条件が欠けているか、setup step が失敗している。

**解決策**: 以下のように設定します。

```yaml
- if: always() && steps.setup.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
```

### コミットが署名されない

**原因**: `id-token: write`パーミッションが欠けている。

**解決策**: ワークフローに以下のパーミッションを追加します。

```yaml
permissions:
  id-token: write
```

### 自動マージが動作しない

**原因**: リポジトリ設定、ブランチ保護ルール、ステータスチェック、承認要件を確認します。

**解決策**: リポジトリ設定で自動マージが有効化されているか、ブランチ保護ルールが適切に設定されているか確認します。

詳細なトラブルシューティングは各 Action の README を参照してください。

## 開発環境

### セットアップ

```bash
# 依存関係のインストールと開発環境のセットアップ
pnpm install
```

### ローカル検証

```bash
# GitHub Actions構文検証
actionlint -config-file ./configs/actionlint.yaml .github/workflows/*.yml

# セキュリティベストプラクティス検証
ghalint run --config ./configs/ghalint.yaml

# シークレット漏洩検出
gitleaks detect --source . --verbose

# 日本語ドキュメント校正
pnpm run lint:text

# フォーマット
dprint fmt
```

### コミットフロー

lefthook により以下が自動実行されます。

- pre-commit - dprint/prettier + actionlint + ghalint + textlint
- commit-msg - AI 生成メッセージ + commitlint 検証
- pre-push - gitleaks スキャン

詳細は[CONTRIBUTING.ja.md](./CONTRIBUTING.ja.md)を参照してください。

## リンク集

### アクションのドキュメント

- [pr-worktree-setup README](./.github/actions/pr-worktree-setup/README.md)
- [create-pr-from-worktree README](./.github/actions/create-pr-from-worktree/README.md)
- [pr-worktree-cleanup README](./.github/actions/pr-worktree-cleanup/README.md)
- [validate-environment](https://github.com/aglabo/.github/tree/main/.github/actions/validate-environment) - 環境検証アクション (推奨: なくても動作しますが、動作環境を保証するために推奨)

### プロジェクトドキュメント

- [CONTRIBUTING.ja.md](./CONTRIBUTING.ja.md) - コントリビューションガイドライン
- [.github/SECURITY.md](./.github/SECURITY.md) - セキュリティポリシー

### 外部リソース

- [Sigstore](https://www.sigstore.dev/) - 署名と Verification
- [Gitsign](https://github.com/sigstore/gitsign) - Git コミット署名
- [Git Worktree](https://git-scm.com/docs/git-worktree) - Worktree ドキュメント
- [GitHub Actions](https://docs.github.com/en/actions) - GitHub Actions 公式ドキュメント

## ライセンス

MIT License - Copyright (c) 2026- atsushifx
