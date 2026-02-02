# PR Worktree Cleanup - ワークツリークリーンアップアクション

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length -->

Git worktree を安全かつ冪等的に削除する Composite Action。

## TL;DR (結論)

- 本番では`worktree-dir`を必ず明示的に指定する (自動検出は fallback、信頼性低)
- `if: always() && steps.init.outcome == 'success'`が基本形 (再実行安全性確保)
- `reason`出力で全 12 パターンを判定可能 (success/skipped/error すべてに理由あり)

---

## 概要

### このアクションとは

`pr-worktree-setup`で作成した git worktree を安全に削除するためのアクションです。以下の特徴を持ちます。

- 安全性: 複数層のバリデーションで誤削除を防止
- 冪等性: 何度実行しても同じ結果 (再実行に安全)
- 透明性: 詳細な reason code で結果を明示
- fail-fast: バリデーションエラーは即座に失敗 (CLAUDE.md 準拠)

### 主な機能

- Worktree 存在確認と git 登録状態の検証
- Uncommitted changes の検出 (force オプションで制御)
- 複数の worktree が存在する場合の安全なスキップ
- 詳細な出力 (status + 12種類の reason code)
- `if: always()` との組み合わせで確実なクリーンアップ

---

## クイックスタート (推奨パターン)

最も安全で推奨される使い方:

```yaml
name: PR 自動作成ワークフロー

permissions:
  contents: write

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Worktree 作成
      - name: Worktree 初期化
        id: init
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: feature/my-feature
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # 作業実行
      - name: 変更を加える
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          # ... 作業 ...

      # クリーンアップ (必ず実行)
      - name: Worktree クリーンアップ
        if: always() && steps.init.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.init.outputs.worktree-path }} # 明示的に指定
```

重要なポイント:

1. `worktree-dir`を必ず指定: 自動検出は fallback 機能 (後述)
2. `if: always() && steps.init.outcome == 'success'`: 再実行時の安全性確保
3. `worktree-path`出力を使用: 初期化ステップの出力を直接渡す

---

## 前提条件 (必読)

### 必須の前提条件

このアクションを使用する前に、以下の条件を**必ず**満たす必要があります。

| 前提条件                         | 説明                                                             |
| -------------------------------- | ---------------------------------------------------------------- |
| **リポジトリのチェックアウト**   | `actions/checkout@v4` などで事前にチェックアウト済みであること   |
| **Worktree の作成**              | `pr-worktree-setup`または`git worktree add`で作成された worktree |
| **同一ジョブ内での実行**         | Worktree を作成したジョブと同じジョブ内で実行すること            |
| **Linux ランナー**               | ubuntu-latest 推奨 (Windows/macOS は非対応)                      |
| **Git リポジトリ内での実行**     | `.git`ディレクトリが存在すること                                 |
| **Base branch のチェックアウト** | 自動検出を使う場合のみ (明示的指定では不要)                      |

### サポートされない使用方法

以下のシナリオは**サポート外**であり、エラーまたは予期しない動作となります。

| シナリオ                               | 理由                                               |
| -------------------------------------- | -------------------------------------------------- |
| 別ジョブで作成した worktree の削除     | ジョブ間でファイルシステムが共有されない           |
| ジョブ再実行で worktree がすでに削除済 | `if: steps.init.outcome == 'success'`で回避可能    |
| Windows/macOS ランナー                 | テスト未実施、動作保証なし                         |
| Git 管理外のディレクトリ               | Git worktree として登録されていない                |
| 手動削除後のアクション実行             | `status=skipped, reason=already-removed`で安全終了 |

### 必要な権限とランナー要件

ワークフロー権限:

```yaml
permissions:
  contents: write # Git 操作に必要
```

ランナー要件:

- OS: Linux (amd64) - ubuntu-latest 推奨
- Git: 2.30+ 推奨 (worktree 安定性のため)

---

## 入出力仕様

### 入力パラメータ

| パラメータ     | 必須 | デフォルト | 説明                                                                  |
| -------------- | ---- | ---------- | --------------------------------------------------------------------- |
| `worktree-dir` | No   | -          | **[強く推奨]** 削除する worktree のパス。明示的指定を推奨 (後述)      |
| `base-branch`  | No   | -          | 自動検出時に除外するベースブランチ (fallback: GITHUB_BASE_REF → main) |
| `force`        | No   | `false`    | Uncommitted changes がある場合も強制削除するか                        |

#### worktree-dir の重要性

本番環境では必ず明示的に指定:

| 指定方法       | メリット                       | デメリット             |
| -------------- | ------------------------------ | ---------------------- |
| **明示的指定** | 再実行安全、デバッグ容易、明確 | なし (推奨)            |
| 自動検出       | コード量削減                   | 再実行失敗、複雑、脆弱 |

自動検出の制限事項:

- ジョブ再実行時に失敗する (worktree がすでに削除済み)
- 複数 worktree がある場合は`reason=multiple`でスキップ
- Base branch のチェックアウトが必要
- デバッグが困難

推奨パターン:

```yaml
# 推奨
- id: init
  uses: ./.github/actions/pr-worktree-setup
  with:
    worktree-dir: ${{ runner.temp }}/pr-worktree

- uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }}

# 非推奨 (fallback として許容)
- uses: ./.github/actions/pr-worktree-cleanup
  # worktree-dir 未指定 = 自動検出
```

### 出力

| 出力             | 型     | 説明                                                     |
| ---------------- | ------ | -------------------------------------------------------- |
| `status`         | string | クリーンアップのステータス (`success`/`skipped`/`error`) |
| `reason`         | string | 結果の理由を示す統一コード (全12種類、下記参照)          |
| `message`        | string | 人間が読める詳細メッセージ                               |
| `removed-path`   | string | 削除された worktree のパス (削除されなかった場合は空)    |
| `worktree-count` | number | 自動検出で見つかった worktree 数 (明示的指定時は0)       |
| `worktree-list`  | string | 自動検出で見つかった worktree パスの改行区切りリスト     |

#### Reason Code 完全リファレンス

単一の`reason`フィールドですべての状況を説明 (12種類):

| status    | reason             | 意味                                               |
| --------- | ------------------ | -------------------------------------------------- |
| `success` | `removed`          | クリーンな worktree を正常に削除                   |
| `success` | `removed-dirty`    | Uncommitted changes ありで削除 (force=true)        |
| `skipped` | `no-path`          | worktree-dir 未指定かつ自動検出不可                |
| `skipped` | `already-removed`  | ディレクトリがすでに存在しない (冪等性)            |
| `skipped` | `multiple`         | 複数 worktree 検出 (明示的指定が必要)              |
| `skipped` | `no-worktrees`     | Worktree が見つからない (自動検出)                 |
| `error`   | `not-registered`   | ディレクトリは存在するが git worktree として未登録 |
| `error`   | `missing-marker`   | `.git`ファイルが欠落 (破損)                        |
| `error`   | `invalid-worktree` | 有効な git working tree ではない                   |
| `error`   | `uncommitted`      | Uncommitted changes あり + force=false             |
| `error`   | `git-failed`       | Git コマンドの実行失敗                             |
| `error`   | `removal-failed`   | `git worktree remove`コマンドの失敗                |

#### Reason Code の活用例

実際に削除されたか判定:

```yaml
- if: steps.cleanup.outputs.reason == 'removed' || steps.cleanup.outputs.reason == 'removed-dirty'
  run: echo "Worktree は削除されました"
```

Uncommitted changes のシナリオ検出:

```yaml
# Force 削除された場合
- if: steps.cleanup.outputs.reason == 'removed-dirty'
  run: echo "::warning::Uncommitted changes が force 削除されました"

# Force=false で拒否された場合
- if: steps.cleanup.outputs.reason == 'uncommitted'
  run: echo "::error::Uncommitted changes のため削除できませんでした"
```

自動検出の問題対応:

```yaml
- if: steps.cleanup.outputs.reason == 'multiple'
  run: |
    echo "::warning::複数の worktree が検出されました"
    echo "検出数: ${{ steps.cleanup.outputs.worktree-count }}"
    echo "パス一覧:"
    echo "${{ steps.cleanup.outputs.worktree-list }}"
```

---

## 使用パターン集

### 基本パターン: if: always() との組み合わせ

```yaml
- name: Worktree クリーンアップ
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/my-worktree
```

`if: always()`により、前のステップが失敗してもクリーンアップを実行します。

### 安全なパターン: force=false (デフォルト)

```yaml
- name: 安全なクリーンアップ
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: false # デフォルト、明示的に指定も可
```

Uncommitted changes がある場合は`reason=uncommitted`で失敗します。

### 強制削除パターン: force=true

```yaml
- name: 強制クリーンアップ
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: true # Uncommitted changes も削除
```

Uncommitted changes がある場合は`reason=removed-dirty`で成功します。

### 高度なパターン: Reason Code による分岐

```yaml
- name: Worktree クリーンアップ
  id: cleanup
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree

- name: 結果に応じた処理
  if: always()
  run: |
    case "${{ steps.cleanup.outputs.reason }}" in
      removed)
        echo "成功: クリーンな削除完了"
        ;;
      removed-dirty)
        echo "警告: 未コミット変更を含めて削除 (force=true) "
        ;;
      already-removed)
        echo "スキップ: 既に削除済み (冪等性) "
        ;;
      uncommitted)
        echo "エラー: 未コミット変更のため削除失敗 (force=false) "
        exit 1
        ;;
      multiple)
        echo "スキップ: 複数 worktree 検出、明示的指定が必要"
        echo "検出数: ${{ steps.cleanup.outputs.worktree-count }}"
        ;;
      *)
        echo "その他: ${{ steps.cleanup.outputs.message }}"
        ;;
    esac

- name: Force 削除時の警告
  if: always() && steps.cleanup.outputs.reason == 'removed-dirty'
  run: |
    echo "::warning::未コミット変更が削除されました"
    echo "パス: ${{ steps.cleanup.outputs.removed-path }}"

- name: エラー時の処理
  if: always() && steps.cleanup.outputs.status == 'error'
  run: |
    echo "::error::クリーンアップ失敗 (reason: ${{ steps.cleanup.outputs.reason }})"
    echo "::error::${{ steps.cleanup.outputs.message }}"
    exit 1
```

### 自動検出モード (非推奨、Fallback)

注意: 自動検出は fallback 機能です。本番環境では使用しないでください。

```yaml
- name: 自動検出によるクリーンアップ
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  # worktree-dir を指定しない = 自動検出
```

自動検出の動作:

1. Base branch を検出 (priority: input → GITHUB_BASE_REF → 検出 → "main")
2. Base branch 以外の worktree を検索
3. 1個だけ見つかれば削除、0個または複数個なら`status=skipped`

制限事項:

- ジョブ再実行で失敗
- 複数 worktree がある場合は`reason=multiple`でスキップ
- デバッグが困難

許容される使用例:

- 単純な単一 worktree ワークフロー
- 実験・テスト用途
- 再実行しないワークフロー

---

## 動作の仕組み

### 処理フロー

```bash
1. Base branch 取得 (自動検出時のみ)
   ├─ Priority 1: inputs.base-branch
   ├─ Priority 2: GITHUB_BASE_REF
   ├─ Priority 3: git symbolic-ref (失敗しても続行)
   └─ Fallback: "main"

2. Worktree パス取得
   ├─ inputs.worktree-dir があればそれを使用
   └─ なければ自動検出
      ├─ git worktree list で Base branch 以外を検索
      ├─ 0個 → reason=no-worktrees, skipped
      ├─ 1個 → 続行
      └─ 2個以上 → reason=multiple, skipped

3. バリデーション (3層)
   ├─ ディレクトリ存在確認
   │  └─ なし → reason=already-removed, skipped
   ├─ Git worktree 登録確認
   │  └─ 未登録 → reason=not-registered, error
   ├─ .git マーカー確認
   │  └─ なし → reason=missing-marker, error
   ├─ Git work-tree 有効性確認
   │  └─ 無効 → reason=invalid-worktree, error
   └─ Uncommitted changes 確認
      ├─ あり + force=false → reason=uncommitted, error
      └─ あり + force=true → 続行 (reason=removed-dirty)

4. 削除実行
   ├─ git worktree remove [--force]
   ├─ 成功 → reason=removed or removed-dirty, success
   └─ 失敗 → reason=removal-failed, error
```

### ステップ詳細

| ステップ            | 責務                                 | 条件付き実行                             |
| ------------------- | ------------------------------------ | ---------------------------------------- |
| `get-base-branch`   | Base branch の決定                   | `inputs.worktree-dir == ''`              |
| `get-worktree`      | Worktree パスの取得または自動検出    | 常に実行                                 |
| `validate-worktree` | 3層バリデーション + uncommitted 確認 | `get-worktree.outcome == 'success'`      |
| `cleanup-worktree`  | `git worktree remove`実行            | `validate-worktree.outcome == 'success'` |
| `output-results`    | 最終結果の表示                       | `always()`                               |

---

## トラブルシューティング

### よくあるエラーと Reason Code

#### reason=already-removed (skipped)

状況: ディレクトリがすでに存在しない。

```bash
status=skipped
reason=already-removed
```

原因:

- クリーンアップが複数回実行された
- 手動で削除済み
- Worktree の作成に失敗していた

対処: 正常動作 (冪等性) 。ログを確認して worktree 作成が成功しているか確認。

#### reason=not-registered (error)

状況: ディレクトリは存在するが git worktree として未登録。

```bash
::error::Path is not a registered git worktree
status=error
reason=not-registered
```

原因:

- `git worktree add`以外で作成されたディレクトリ
- パスの指定ミス
- Worktree が別の方法で削除された後の残骸

対処: `git worktree list`で登録状態を確認。正しいパスを指定する。

#### reason=uncommitted (error)

状況: Uncommitted changes あり + force=false。

```bash
::error::Cannot remove worktree with uncommitted changes (force=false)
::error::Changes found:
M  file.txt
status=error
reason=uncommitted
```

原因:

- 作業中の変更がコミットされていない
- Git add されていないファイルが存在

対処:

1. 変更をコミット・プッシュする
2. または`force: true`を指定 (`reason=removed-dirty`になる)

#### reason=multiple (skipped)

状況: 自動検出で複数 worktree 検出。

```bash
::notice::Multiple worktrees found (3), skipping auto-detection
status=skipped
reason=multiple
```

原因:

- Base branch 以外に複数の worktree が存在
- 自動検出では判断不可

対処: `worktree-dir`を明示的に指定する (推奨パターン) 。

#### reason=invalid-worktree (error)

状況: 有効な git working tree ではない。

```bash
::error::Path is not a valid git working tree
status=error
reason=invalid-worktree
```

原因:

- Worktree の破損
- `.git`ファイルの内容が不正

対処: `git worktree list`で状態確認。必要なら`git worktree prune`で整理。

### 再実行時の問題

問題: ジョブ再実行時にクリーンアップが失敗する。

原因: 最初の実行で worktree が削除済み、自動検出が`reason=no-worktrees`を返す。

解決策:

```yaml
- name: Worktree クリーンアップ
  if: always() && steps.init.outcome == 'success' # 初期化成功時のみ
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }} # 明示的指定
```

### Permission Denied

問題: Git または filesystem の権限エラー。

解決策:

- ワークフローに`contents: write`権限があるか確認
- Worktree が別プロセスでロックされていないか確認
- Runner の一時ディレクトリ (`${{ runner.temp }}`) を使用

---

## 設計思想

### なぜ Strict Mode (force=false) がデフォルトか？

理由: 安全性優先。

- データ損失防止: 未コミット変更を保護
- 明示的な意図: `force: true`で意図的に選択
- CI/CD との整合性: 一時 worktree はクリーンであるべき

使い分け:

- force=false (デフォルト): 本番ワークフロー、データ保護重視
- force=true: CI/CD の一時環境、未コミット変更を気にしない

### なぜ Unified Reason Field か？

以前の設計 (複雑):

```yaml
outputs:
  removed: true/false
  was-dirty: true/false
  skip-reason: no-path/multiple/...
  # error-reason は存在しない
```

問題点:

- 複数のフィールドを組み合わせる必要がある
- エラー時の理由が不明
- 条件分岐が複雑

新しい設計 (シンプル):

```yaml
outputs:
  reason: removed/removed-dirty/uncommitted/multiple/...
  # 単一フィールドで全12パターンをカバー
```

利点:

1. **シンプルな条件分岐**: `if: reason == 'removed-dirty'`
2. **完全な網羅性**: Success/Skipped/Error すべてに reason あり
3. **自己文書化**: Reason code が人間、機械の双方に読みやすい
4. **拡張性**: 新しい reason を追加しても既存ロジックに影響なし

### なぜ Auto-detect は Fallback か？

Auto-detect の問題:

- ジョブ再実行で失敗する (worktree がすでに削除済み)
- 複数 worktree がある場合は判断不可
- Base branch のチェックアウトが必要
- デバッグが困難

設計方針:

1. **信頼性 > 便利さ**
2. **明示性 > 魔法**
3. **再実行安全性 > 自動化**

推奨: 常に`worktree-dir`を明示的に指定し、初期化ステップの出力を渡す。

### Fail-fast vs Idempotent (CLAUDE.md 準拠)

このアクションは [CLAUDE.md](../../../CLAUDE.md) の fail-fast validation パターンに従います。

#### Fail-fast とは？

Fail-fast (即座に失敗): バリデーションエラーを検出した時点で即座に`exit 1`で失敗する戦略。

目的:

- エラーの早期発見
- 問題のある状態での続行を防ぐ
- 明確な成功/失敗シグナル

CLAUDE.md の原則:

```yaml
# REQUIRED: Fail-Fast Validation
if: steps.previous_step.outcome == 'success'

# バリデーションエラーは exit 1 で即座に失敗
if [ "$ERROR_CONDITION" ]; then
  echo "::error::Validation failed: reason"
  exit 1
fi
```

#### このアクションの実装

| シナリオ             | 動作             | Exit Code | 理由                   |
| -------------------- | ---------------- | --------- | ---------------------- |
| バリデーションエラー | `status=error`   | 1         | 即座に失敗 (fail-fast) |
| 冪等的なシナリオ     | `status=skipped` | 0         | 問題なし (idempotent)  |
| 削除成功             | `status=success` | 0         | 正常完了               |

重要な設計決定:

- `status=error` + `exit 0`の組み合わせは存在しない
- バリデーションエラーは必ず`exit 1` (fail-fast)
- 冪等的なケース (すでに削除済みなど) は`exit 0` (正常終了)

例外:「すでに削除済み」は`reason=already-removed, status=skipped, exit 0` (冪等性を保証)

---

## 参考情報

### 関連アクション

- [PR Worktree Setup](../pr-worktree-setup/README.ja.md) - Worktree 作成とペアで使用
- [Create PR from Worktree](../create-pr-from-worktree/README.ja.md) - Worktree 内でコミット・PR 作成

### ペアリング例

```yaml
# 完全なワークフロー例
- name: Worktree 初期化
  id: init
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

- name: 作業実行
  run: |
    cd ${{ steps.init.outputs.worktree-path }}
    # ... 変更 ...

- name: Worktree クリーンアップ
  if: always() && steps.init.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

### セキュリティ考慮事項

安全なデフォルト:

- Git worktree のみを削除 (`.git`ファイル存在確認)
- 任意のディレクトリを削除しない
- 情報豊富なエラーメッセージで透明性確保

Force フラグ:

- `force: true`: Uncommitted changes も削除 (`reason=removed-dirty`)
- `force: false`: Uncommitted changes を保護 (`reason=uncommitted`でエラー)
- ワークフローの要件に応じて選択

### ライセンス

MIT License - リポジトリの LICENSE ファイルを参照。

### 参照

- [Git Worktree ドキュメント](https://git-scm.com/docs/git-worktree)
- [GitHub Actions ワークフロー構文](https://docs.github.com/ja/actions/using-workflows/workflow-syntax-for-github-actions)
- [CLAUDE.md - AI 協働ガイド](../../../CLAUDE.md)

---

最終更新: 2026-02-04
バージョン: 2.0 (Unified Reason Field 対応)
