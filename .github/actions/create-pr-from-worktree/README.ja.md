# Create PR from Worktree Action

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/max-comma -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length -->

## Overview

Worktree 上で安全に PR を作成する 3つの composite action セット。

### TL;DR（5行でわかる要約）

- 何をする: Worktree 隔離環境で PR branch を作成し、main を汚さず安全に PR 作成
- 3つのセット: setup（worktree 作成）→ create-pr（この action）→ cleanup（削除）
- 必須要件: Linux runner、3つを同一 job で実行、pr-worktree-setup が前提
- 保証する: Sigstore 署名、base branch 自動検出、fail-safe 設計、確実な cleanup
- 保証しない: Worktree 戦略なしでの完全な安全性、job 間での worktree 共有

### 3つの Action の役割

```bash
1. pr-worktree-setup        → Worktree 作成 + Sigstore 署名設定
2. create-pr-from-worktree  → PR 作成/更新（このaction）
3. pr-worktree-cleanup      → Worktree 削除（if: always()）
```

### Worktree 戦略を使う理由

- Main ブランチを保護: PR 作業が main に影響しない
- 検証可能な署名: Sigstore gitsign による keyless 署名
- 並列実行の安全性: 複数 PR が干渉しない
- クリーンな環境: 作業後は確実にクリーンアップ

---

## Quick Start

```yaml
name: Auto PR with Worktree
on: push

permissions:
  id-token: write # Sigstore 署名
  contents: write # Git操作 + Label作成
  pull-requests: write # PR操作

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # 1. Worktree セットアップ
      - name: Setup PR worktree
        id: setup
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: auto-fix/${{ github.ref_name }}
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # 2. Worktree 内で作業
      - name: Make changes in worktree
        working-directory: ${{ steps.setup.outputs.worktree-path }}
        run: |
          echo "fix" > fix.txt
          git add fix.txt
          git commit -m "fix: Apply auto-fix"
          git push origin auto-fix/${{ github.ref_name }}

      # 3. Main に戻る（重要！）
      - name: Return to main
        run: git checkout ${{ github.ref_name }}

      # 4. PR 作成（このaction）
      - name: Create PR
        uses: ./.github/actions/create-pr-from-worktree
        with:
          pr-branch: auto-fix/${{ github.ref_name }}
          pr-title: "fix: Apply auto-fix"
          pr-body: "Auto-generated PR"
          labels: "automated,fix"
          merge-method: "squash"

      # 5. クリーンアップ（必ず実行）
      - name: Cleanup worktree
        if: always() && steps.setup.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

**重要なポイント**:

1. 3つの action を順番に実行（setup → create-pr → cleanup）
2. Worktree 内で作業後、必ず main に戻る
3. `if: always()` でクリーンアップを保証

---

## Prerequisites

### Worktree 戦略の前提条件

| 前提条件                | 説明                                                           |
| ----------------------- | -------------------------------------------------------------- |
| `pr-worktree-setup`実行 | Worktree が作成済み                                            |
| PR branch が push 済み  | Worktree 内でコミット・push 完了                               |
| Main branch に checkout | `create-pr-from-worktree` 実行時は main に戻る                 |
| Linux runner            | ubuntu-latest / ubuntu-22.04 / ubuntu-20.04                    |
| Same job execution      | 3つのactionは同一 job 内で実行（worktree は job 間で共有不可） |

### Required Permissions

```yaml
permissions:
  id-token: write # pr-worktree-setup で Sigstore 署名に必要
  contents: write # PR操作 + Label作成に必要
  pull-requests: write # PR操作に必要
```

> 注意:
> `contents: write` のみの場合、label 作成が失敗しますが PR 作成は成功します（best-effort）。

### Required Tools

- GitHub CLI (`gh`) version 2.0+
- jq (JSON processor)

※ GitHub-hosted runners にはデフォルトでインストール済み。

---

## Inputs

| Input          | Required | Default  | Description                                          |
| -------------- | -------- | -------- | ---------------------------------------------------- |
| `pr-branch`    | Yes      | -        | PR branch 名（head branch）                          |
| `pr-title`     | Yes      | -        | Pull Request のタイトル                              |
| `pr-body`      | Yes      | -        | Pull Request の本文                                  |
| `labels`       | No       | `''`     | カンマ区切りの label（例: `"automated,fix"`）        |
| `merge-method` | No       | `squash` | Auto-merge 方式（`merge`/`squash`/`rebase`/`never`） |

**Input Validation**: `merge-method` は whitelist 検証されます。typo は即エラー。

---

## Outputs

| Output               | Description                                                 |
| -------------------- | ----------------------------------------------------------- |
| `validation-status`  | 検証結果（`ok`, `fail`, `error`, `warning`）                |
| `validation-message` | 検証ステータスメッセージ                                    |
| `pr-number`          | 作成/更新された PR 番号（検証失敗時は空）                   |
| `pr-url`             | Pull Request の URL（検証失敗時は空）                       |
| `pr-operation`       | 実行された操作（`created`, `updated`, `update-failed`, 空） |
| `automerge-status`   | Auto-merge ステータス（`enabled`, `failed`, `timeout`, 空） |

**Validation Status**:

- `ok`: すべて成功
- `fail`: ユーザー修正可能（branch 不在など）
- `error`: システムエラー（API 障害など）
- `warning`: PR は作成/更新済み。追加操作（labels / auto-merge）のみ失敗

**Operation Values**:

- `created`: 新規 PR 作成
- `updated`: 既存 PR 更新成功
- `update-failed`: PR 存在するが更新失敗（PR 番号と URL は返る）
- 空: 検証失敗

**Usage Example**:

```yaml
- name: Notify on PR creation
  if: steps.create-pr.outputs.pr-number != ''
  run: echo "PR created: ${{ steps.create-pr.outputs.pr-url }}"
```

※ 推奨: 成功判定には `validation-status == 'ok'` を使用してください。

---

## Core Concepts

### Worktree Strategy Architecture

```text
┌─────────────────────────────────────────────┐
│ Main Repository (main - 常にクリーン)       │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-setup
┌─────────────────────────────────────────────┐
│ Worktree (隔離環境)                         │
│ - PR branch に checkout                     │
│ - Sigstore gitsign 設定済み                 │
│ - 作業: git commit → git push               │
└─────────────────────────────────────────────┘
              ↓ git checkout main (重要！)
┌─────────────────────────────────────────────┐
│ Main Repository (main に戻る)               │
│ - create-pr-from-worktree を実行            │
│ - Base branch (main) を自動検出             │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-cleanup
┌─────────────────────────────────────────────┐
│ Cleanup完了 - Worktree 削除、Main はクリーン│
└─────────────────────────────────────────────┘
```

### Base Branch Auto-Detection

- 現在 checkout している branch を base として自動検出
- `git symbolic-ref --short HEAD` で取得
- Worktree 内で作業後、**必ず main に戻ってから実行**

※ この action は「現在 checkout されている branch」を base branch として扱うため、worktree 内にいる状態では正しい base を検出できません。

※ base branch を input で指定する機能は提供しません。設計上の責務は caller workflow にあります。

### Fail-Open Strategy

PR 存在確認（`gh pr list`）が失敗した場合。

1. 失敗を「PR が存在しない」として扱う
2. 新規 PR 作成を試みる
3. GitHub API が重複 PR を拒否（安全網）

**理由**: 可用性重視。一時的な API 障害が PR 作成を妨げるべきではない。

※ 重複 PR の最終拒否は GitHub API 側が保証します。本 action は可用性を優先し、PR 作成の試行を中断しません。

### Validation Architecture

```text
1. Base Branch Detection → 2. API Rate Limit Check
  → 3. Branch Validation → 4. PR Creation/Update
  → 5. ABI Contract Validation → 6. Labels (best-effort)
  → 7. Auto-Merge (merge-method != 'never')
```

**Fail-First 設計**: すべての検証が `ok` / `success` まで PR 作成に進まない。

---

## Label & Auto-Merge

### Labels（Best-Effort）

- Label 作成/適用は**非ブロッキング**
- 失敗しても warning で継続、PR 作成は成功
- `contents: write` 権限が必要

### Auto-Merge

- `squash`（デフォルト）/ `merge` / `rebase` / `never`
- Repository で auto-merge 有効化が必要
- 失敗しても PR 作成は成功（`automerge-status=failed`）

---

## Troubleshooting

### Worktree 関連

**"Failed to detect current branch name"**
→ Main に戻り忘れ。`git checkout main` してから実行。

**"Branch does not exist on remote"**
→ Worktree 内で `git push` 忘れ。push してから PR 作成。

**Worktree cleanup not running**
→ `if: always() && steps.setup.outcome == 'success'` を追加。

### 一般的な問題

**Auto-merge not working**
→ Repository 設定、branch protection、status check、approval を確認。

**Labels not created**
→ `contents: write` 権限を確認。

**Timeout detection failed**
→ Linux runner を使用（macOS/Windows は非対応）。

---

## FAQ

### なぜ3つのactionに分かれているのか？

責務の分離と再利用性のため。各 action が独立して検証・テスト可能。

### Worktree を使わずに使えるか？

技術的には可能ですが、main ブランチを汚すリスクがあり、Sigstore 署名も使えません。Worktree 戦略の使用を強く推奨します。

### macOS/Windows をサポートしない理由は？

GNU `timeout` の exit code 124 契約に依存しています。BSD timeout（macOS）は異なる exit code、Windows には timeout コマンドがありません。

### なぜ `job.defaults.run.working-directory` を使わないのか？

`job.defaults.run.working-directory` は step outputs を参照できないため、`worktree-path` のような動的パスには使用できません。

各ステップで明示的に `working-directory` を指定します。

例:

```yaml
- name: Make changes in worktree
  working-directory: ${{ steps.setup.outputs.worktree-path }} # 動的パス
  run: |
    echo "fix" > fix.txt
    git add fix.txt
```

参考: GitHub Actions の job.defaults.run は静的な値のみサポートし、`${{ }}` 式の評価はサポートしていません。

---

## Reference

### Related Actions

- [pr-worktree-setup](../pr-worktree-setup/README.md) - Worktree 作成と Sigstore 署名設定
- [pr-worktree-cleanup](../pr-worktree-cleanup/README.md) - Worktree の安全な削除

### Documentation

- [GitHub CLI Manual](https://cli.github.com/manual/)
- [GitHub Auto-Merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)
- [Composite Actions](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [Git Worktree](https://git-scm.com/docs/git-worktree)
- [Sigstore Gitsign](https://github.com/sigstore/gitsign)

### Limitations

- Worktree 戦略必須（3つの action セット）
- Linux runners のみ（GNU coreutils timeout 必要）
- Same job execution（Worktree は job 間で共有不可）
- Pre-pushed branches 必須
- Main branch checkout 必須

---

## License

MIT License - Copyright (c) 2025 atsushifx
