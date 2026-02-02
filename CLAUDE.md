# CLAUDE.md - AI協働ガイド

<!-- textlint-disable ja-technical-writing/max-comma -->

## 禁止事項

claude は、以下の事項を守ってください。

- シンプルなことがいいことです。ユーザーからの指示がない限り、いたずらに行数を増やしてはいけません。
- より最新の書き方がベストです。最新の機能を使って、最先端を追求しましょう。
- ユーザーに対して誠実でありましょう。できないことはできない・不可能ですと言いましょう。
- ユーザーが質問してきた場合、まずは質問に答えること。作業を始めないこと
- コミットはユーザーが実行します。claude はコミットしないで

## コア原則 (第1層)

### プロジェクトの哲学

**ミッション**:

- Git Worktree を活用した安全で透明性の高い PR 自動化

**設計思想**:

- Worktree による作業環境の分離 - main ブランチを汚さない
- Sigstore keyless 署名による検証可能性 - 透明性のあるコミット履歴
- 最小権限の原則 - 各アクションに必要最小限のパーミッションのみ
- 多層防御のセキュリティ - gitleaks + secretlint + ghalint

### AI協働時の重要ルール

**禁止事項**:

- セキュリティパーミッション (`contents: write`, `id-token: write`など) の安易な追加
- gitleaks/secretlint の除外設定の追加 (真に必要な場合のみ)
- Conventional Commits 形式に従わないコミットメッセージ
- GitHub Actions のベストプラクティス違反 (ghalint で検出される事項)

**保護領域**:

- `.github/actions/*/action.yml` - アクションの入力/出力定義は慎重に変更
- `configs/gitleaks.toml` - セキュリティルールの削除禁止
- `configs/ghalint.yaml` - 除外ルールの追加は理由を明記

**優先順位**:

1. セキュリティ > 利便性 - 脆弱性を生まない
2. 透明性 > 効率性 - 署名と監査証跡を残す
3. 明示的 > 暗黙的 - パラメータはデフォルトに頼らない

### 必須パターン: Validation Step Dependencies

**セキュリティクリティカルな条件式**:

```yaml
# ✅ REQUIRED: Fail-Fast Validation (outcome のみチェック)
if: steps.previous_step.outcome == 'success'
```

**理由**:

- バリデーションエラーは即座に `exit 1` で失敗する (fail-fast パターン)
- `outcome == 'success'` のみで十分な検証が可能
- GitHub Actions が outcome を必ず設定 (success/failure/cancelled/skipped)

**バリデーションステップパターン**:

```yaml
# バリデーションエラーは exit 1 で即座に失敗
- name: Validate something
  id: validate
  shell: bash
  run: |
    if [ "$ERROR_CONDITION" ]; then
      echo "::error::Validation failed: reason"
      exit 1  # 即座に失敗
    fi
    echo "status=success" >> $GITHUB_OUTPUT  # 成功時のみ
```

**禁止パターン**:

```yaml
# ❌ NEVER: 空文字列でbypass可能
if: steps.previous_step.outputs.status != 'error'

# ❌ NEVER: エラー時に exit 0 (pr-worktree-cleanup の skip 処理を除く)
if [ "$ERROR" ]; then
  echo "status=error" >> $GITHUB_OUTPUT
  exit 0  # これは禁止
fi
```

**例外**:

- `status=skipped` + `exit 0` は許容 (pr-worktree-cleanup でワークツリーが見つからない場合)
- スクリプトベースのバリデーション (`validate-environ.sh`, `validate-branches.sh`) は `status` 出力を使用可能

## 技術コンテキスト (第2層)

### 技術スタック

```yaml
主要技術:
  - GitHub Actions (Composite Actions)
  - Git Worktree
  - Sigstore/gitsign (OIDCベースkeyless署名)

品質管理:
  - actionlint: GitHub Actions構文検証
  - ghalint: セキュリティベストプラクティス検証
  - gitleaks: シークレット漏洩検出
  - secretlint: 追加シークレットスキャン
  - textlint: 日本語ドキュメント校正 (preset-ja-technical-writing)

自動化:
  - lefthook: Gitフック管理
  - dprint: マルチフォーマッター (Markdown/JSON/YAML/TOML)
  - Claude/OpenAI CLI: コミットメッセージ自動生成
```

### アーキテクチャ概要

**3つの Composite Actions (実行順)**:

1. `pr-worktree-setup` - Worktree 作成 + gitsign 設定
2. `create-pr-from-worktree` - コミット + PR 作成/更新
3. `pr-worktree-cleanup` - Worktree 削除 + ブランチクリーンアップ

**ディレクトリ構造**:

```bash
.github/actions/       # 3つのComposite Actions
.github/workflows/     # CI (ci-scan-all.yml) + E2Eテスト (test-create-pr.yml)
configs/               # 10個の設定ファイル (commitlint, gitleaks, textlintなど)
scripts/               # setup-lefthook.sh, write-commit-message.sh
```

### 開発ワークフロー

**セットアップ**:

```bash
./scripts/setup-lefthook.sh  # lefthookインストール + Gitフック設定
```

**コミットフロー (lefthook 自動実行)**:

```bash
git add .
git commit
  → [pre-commit] dprint/prettier + actionlint + ghalint + textlint
  → [commit-msg] AI生成メッセージ + commitlint検証
  → [pre-push] gitleaks スキャン
```

**ブランチ戦略**:

- `main` - 安定版
- `releases` - リリース準備
- `feature/*`, `fix/*`, `docs/*`, `refactor/*`, `test/*`

**コミットメッセージ形式 (Conventional Commits)**:

```plaintext
<type>(<scope>): <subject>

<body>

<footer>
```

型: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

### 共通コマンド

```bash
# 開発環境セットアップ
./scripts/setup-lefthook.sh

# コミットメッセージ生成 (手動)
./scripts/write-commit-message.sh

# CI検証 (ローカル)
actionlint -config-file ./configs/actionlint.yaml .github/workflows/*.yml
ghalint run --config ./configs/ghalint.yaml
gitleaks detect --source . --verbose

# E2Eテスト (GitHub Actions)
# Actions UI から test-create-pr.yml を手動実行

# フォーマット
dprint fmt
```

### コードスタイル (ツール化できない部分のみ)

**アクション設計パターン**:

- 入力パラメータは明示的にデフォルト値を設定
- セキュリティ関連パーミッションは最小限
- エラーメッセージは具体的に (ユーザーが対処方法を理解できるように)

**YAML構造**:

- ワークフローには必ず`permissions`セクションを明記
- 依存関係のあるステップは`needs`で明示

**日本語ドキュメント**:

- 一文 100 文字以内 (textlint で検証)
- 技術用語は統一 (例：「ワークフロー」vs「Workflow」)

## ドキュメント参照 (第3層)

### アクション詳細

各アクションの完全な仕様とパラメータ:

- `.github/actions/pr-worktree-setup/README.md`
- `.github/actions/create-pr-from-worktree/README.md`
- `.github/actions/pr-worktree-cleanup/README.md`

### 包括的なプロジェクト情報

**Serenaメモリー** (`.serena/memories/`):

- `project-overview.md` - プロジェクト全体像、特徴、対象ユーザー
- `github-actions-architecture.md` - アクション詳細、ワークフロー、セキュリティ
- `development-workflow.md` - 環境構築、Git フック、AI 統合、ブランチ運用
- `configuration-files.md` - 10個の設定ファイル詳細、カスタマイズポイント

### コントリビューション

- `CONTRIBUTING.md` / `CONTRIBUTING.ja.md` - コントリビューションガイドライン
- `README.md` / `README.ja.md` - プロジェクト基本情報
- `.github/SECURITY.md` - セキュリティポリシー

### トラブルシューティング

**lefthook関連**:

```bash
lefthook uninstall && lefthook install  # フックが動作しない場合
```

**AI統合**:

- Claude CLI / OpenAI CLI のインストール確認
- `scripts/write-commit-message.sh`のデバッグ

**gitsign**:

- GitHub Actions: 自動的に OIDC トークン利用
- ローカル: 手動設定が必要 (通常は不要 - CI で署名)

---

**情報探索の優先順位**:

1. この CLAUDE.md (AI 協働ルール、禁止事項)
2. アクションの README (パラメータ仕様)
3. Serena メモリー (詳細な技術情報)
4. CONTRIBUTING (開発プロセス)
