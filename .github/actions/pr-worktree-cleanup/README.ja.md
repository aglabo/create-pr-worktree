# PR Worktree Cleanup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length -->

`pr-worktree-setup` で作成した git worktree を安全に削除する composite action。

## Overview

このアクションは、git worktree の安全かつ冪等なクリーンアップを提供します。`pr-worktree-setup` アクションと対になり、完全な worktree ライフサイクル管理を提供します。

**Key Features**:

- worktree の削除前に存在を検証
- ディレクトリが実際に git worktree であることを確認
- 冪等な動作 (複数回実行しても安全)
- すでに削除済みの worktree を適切に処理
- クリーンアップ操作の詳細なステータスレポート
- `if: always()` と組み合わせて確実なクリーンアップを実現

## Prerequisites

**Minimal Requirements**:

- Git 2.30+
- worktree は git で管理されている必要があります (`git worktree add` で作成)

**Recommended Usage**:

`pr-worktree-setup` アクションと組み合わせて完全なワークフローを構築:

```yaml
- name: worktree を初期化
  id: init-worktree
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

# ... worktree 内で作業 ...

- name: worktree をクリーンアップ
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

## Inputs

| Input          | Required | Default | Description                                                         |
| -------------- | -------- | ------- | ------------------------------------------------------------------- |
| `worktree-dir` | No       | -       | 削除する worktree のディレクトリパス (指定しない場合は自動検出)     |
| `base-branch`  | No       | -       | クリーンアップから除外するベースブランチ (指定しない場合は自動検出) |
| `force`        | No       | `false` | コミットされていない変更がある場合でも強制的に削除                  |

## Outputs

| Output         | Description                                              |
| -------------- | -------------------------------------------------------- |
| `status`       | クリーンアップ操作のステータス (success, skipped, error) |
| `message`      | クリーンアップ操作の詳細メッセージ                       |
| `removed-path` | 削除された worktree のパス                               |

## Usage

### Basic Usage with if: always()

```yaml
- name: worktree をクリーンアップ
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ runner.temp }}/my-worktree
```

`if: always()` 条件により、前のステップが失敗した場合でもクリーンアップが実行されます。

### Integration with pr-worktree-setup

```yaml
name: 署名付き PR の作成

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - name: リポジトリをチェックアウト
        uses: actions/checkout@v4

      - name: gitsign で worktree を初期化
        id: init-worktree
        uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
        with:
          branch-name: feature/my-feature
          worktree-dir: ${{ runner.temp }}/pr-worktree

      - name: 変更を加える
        run: |
          cd ${{ steps.init-worktree.outputs.worktree-path }}
          echo "# New Feature" > feature.md
          git add feature.md
          git commit -m "feat: add new feature"
          git push origin feature/my-feature

      - name: PR を作成
        run: |
          gh pr create --title "Add new feature" --body "..."

      - name: worktree をクリーンアップ
        if: always()
        uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
        with:
          worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

### Force Removal

```yaml
- name: worktree を強制的にクリーンアップ
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: true
```

`force: true` を指定すると、worktree にコミットされていない変更がある場合でも削除されます。CI/CD 環境で一時的な worktree を確実にクリーンアップする場合に有効です。

デフォルトは `force: false` で、コミットされていない変更がある場合は `error` ステータスで削除を中止します。これにより、意図しない作業の喪失を防ぎます。

### Auto-Detection Mode

```yaml
- name: worktree をクリーンアップ (自動検出)
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
```

入力を指定しない場合、アクションは自動的に以下を実行します。

1. 現在のブランチをベースブランチとして検出
2. `git worktree list --porcelain` でベースブランチではない worktree を正確に検出
3. worktree 数を確認:
   - 0 個: `skipped` ステータスを返す
   - 複数個: `skipped` ステータスを返し、`worktree-dir` の明示的な指定を推奨
   - 1 個: 検出された worktree を削除

worktree が 1 つしかなく、自動クリーンアップしたい場合に便利です。`--porcelain` 形式を使用することで、branch 名の部分一致による誤検出を防ぎます。複数の worktree がある場合は、安全のため `worktree-dir` を明示的に指定します。

### Handling Cleanup Status

```yaml
- name: worktree をクリーンアップ
  id: cleanup
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ runner.temp }}/worktree

- name: クリーンアップステータスを確認
  if: always()
  run: |
    echo "Cleanup status: ${{ steps.cleanup.outputs.status }}"
    echo "Cleanup message: ${{ steps.cleanup.outputs.message }}"
    if [ "${{ steps.cleanup.outputs.status }}" = "error" ]; then
      echo "::warning::Worktree cleanup failed, may need manual cleanup"
    fi
```

## How It Works

1. Get Worktree Path:
   - `worktree-dir` が指定されている場合: 直接使用
   - 指定されていない場合: worktree を自動検出
     - `base-branch` 入力または現在のブランチからベースブランチを検出
     - `git worktree list --porcelain` でベースブランチではない worktree を正確に検出
     - worktree 数を確認:
       - 0 個: `skipped` (メッセージ: "No worktrees found")
       - 複数個: `skipped` (メッセージ: "Multiple worktrees found, specify worktree-dir explicitly")
       - 1 個: worktree-path を設定
2. Validate Worktree: worktree の事前チェック
   - worktree-path が指定されているか確認
   - ディレクトリが存在するか確認
   - ディレクトリが有効な git worktree か確認 (`.git` ファイルの存在)
   - `force: false` の場合: コミットされていない変更を確認
     - 変更がある場合: `error` ステータスで削除を中止（作業内容の喪失を防ぐ）
     - 変更がない場合: 削除を続行
   - 検証失敗時: `error` または `skipped` ステータスを返す
3. Cleanup Worktree: worktree の削除
   - `git worktree remove` を実行
   - `force: true` の場合は `--force` フラグを使用
4. Output Status: ステータス (success, skipped, または error) とメッセージを返す

## Status Meanings

| Status    | Description                                            | Exit Code |
| --------- | ------------------------------------------------------ | --------- |
| `success` | worktree が正常に削除されました                        | 0         |
| `skipped` | worktree が存在しません (すでにクリーンアップ済み)     | 0         |
| `error`   | 削除が失敗しました (例: worktree ではない、git エラー) | 0         |

すべてのステータスで Exit Code は 0 です。caller 側は `status` と `message` の outputs で結果を判断してください。

このアクションは冪等になるように設計されています。同じ worktree に対して複数回実行しても安全です。worktree がすでに削除されている場合は、`skipped` ステータスを返しますが、失敗しません。

## Error Handling

### Worktree Already Removed

**Behavior**: `skipped` ステータスを返し、失敗しません。

```bash
status=skipped
message=No worktrees found to clean up (excluding base branch: main)
```

クリーンアップが複数回実行された場合や、worktree が手動で削除された場合、これは正常な動作です。

### Directory Exists But Not a Worktree

**Behavior**: `error` ステータスを返して失敗。

```bash
EXIT_STATUS=error:Directory is not a valid git worktree
```

**Solution**: パスが `git worktree add` で作成されたディレクトリを指していることを確認してください。

### Uncommitted Changes with force: false

**Behavior**: `error` ステータスを返して削除を中止。

```bash
status=error
message=Cannot remove worktree with uncommitted changes (force=false): /path/to/worktree
```

**Solution**:

- 作業内容を保存したい場合: worktree 内で変更をコミットまたはスタッシュ
- 削除を強制する場合: `force: true` を設定

### Git Worktree Remove Failed

**Behavior**: `error` ステータスを返して失敗。

**Common Causes**:

- worktree が別のプロセスでロックされている
- パーミッションの問題
- worktree が破損している

**Solution**: ログの git エラーメッセージを確認し、手動で調査してください。

## Troubleshooting

### Cleanup Always Shows Skipped

**Cause**: クリーンアップ実行時に worktree が見つからない。

**Possible Reasons**:

- クリーンアップが複数回実行されている
- worktree の作成が正常に完了しなかった
- worktree が手動または別のステップで削除された

**Solution**: ワークフローログで worktree の作成が成功したことを確認してください。`pr-worktree-setup` の output を使用している場合、ステップ ID が一致していることを確認してください。

### Cleanup Fails with "Not a Valid Git Worktree"

**Cause**: ディレクトリは存在しますが、`git worktree add` で作成されていない。

**Solution**: `pr-worktree-setup` から正しいパスを渡していることを確認してください。任意のディレクトリを渡さないでください。

### Permission Denied

**Cause**: Git またはファイルシステムのパーミッション問題。

**Solution**: ワークフローで Git 操作／ファイル操作のためのパーミッションが設定済みで、worktree が別のプロセスでロックされていないことを確認してください。

## Design Decisions

### Why Default force: false?

デフォルトの `force: false` は、安全性を優先した設計です。コミットされていない変更がある場合、削除を失敗させることで、意図しない作業の喪失を防ぎます。

CI/CD 環境で worktree が一時的であり、強制削除が必要な場合は、明示的に `force: true` を設定してください。`force: false` の場合でも、コミットされていない変更があると警告が表示されます。

### Why Skipped Instead of Error for Missing Worktree?

worktree が存在しない場合に `error` ではなく `skipped` ステータスを返すことで、アクションが冪等になります。
これは以下の場合に有効です。

- `if: always()` ブロックでクリーンアップを複数回実行する可能性がある
- 別のステップがすでに worktree を削除している
- worktree の作成が失敗したがクリーンアップは実行される

`skipped` ステータスは明示的に「対象なし」を表し、caller 側で分岐しやすくなります。CI/CD パイプラインでの誤検出による失敗を防ぎます。

### Why Validate It's a Git Worktree?

検証により、任意のディレクトリに対して誤って `git worktree remove` を実行することを防ぎ、予期しない動作の発生を回避します。
`.git` ファイル (worktree マーカー) をチェックすることで、アクションは正当な git worktree に対してのみ動作します。

## Pairing with pr-worktree-setup

このアクションは `pr-worktree-setup` と対になるように設計されています。

```yaml
# 初期化
- name: worktree を初期化
  id: init-worktree
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

# ... 作業 ...

# クリーンアップ (常に実行)
- name: worktree をクリーンアップ
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

**Key Points**:

- 初期化から `worktree-path` output を使用 (絶対パス)
- クリーンアップを確実に実行するため、常に `if: always()` を使用
- クリーンアップステップをジョブの最後に配置

## Security Considerations

**Safe Defaults**:

- git worktree のみを削除 (`.git` ファイルの存在を検証)
- 任意のディレクトリは削除しない
- 情報を提供するエラーメッセージで適切に失敗

**Force Flag**:

- `force: true` はコミットされていない変更がある場合でも worktree を削除
- `force: false` はコミットされていない変更を保持し、存在する場合は失敗
- ワークフローの要件に基づいて選択

## License

MIT License - リポジトリの LICENSE ファイルを参照。

## References

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [PR Worktree Setup Action](../pr-worktree-setup/README.md)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
