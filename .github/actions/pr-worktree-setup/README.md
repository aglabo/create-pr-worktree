# PR Worktree Setup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

Sigstore を使用したキーレス署名付きコミットのための git worktree を作成し、gitsign を設定する Composite Action。

## Overview

このアクションは、コミット署名用に gitsign が設定された git worktree を作成するプロセスを簡素化します。worktree の作成、gitsign のインストール、および設定を単一の再利用可能なステップにまとめます。

**Key Features:**

- Worktree 作成
- Gitsign のインストール
- Gitsign による署名付きコミット自動設定

## Prerequisites

**Required Permissions:**

```yaml
permissions:
  id-token: write # OIDC トークンアクセスに必要 (gitsign keyless signing)
  contents: write # Git 操作に必要
```

**Runner Requirements:**

- Linux runner (ubuntu-latest 推奨)
- Git 2.30+

## Inputs

<!-- markdownlint-disable table-column-style -->

| Input             | Required | Default                                        | Description                           |
| ----------------- | -------- | ---------------------------------------------- | ------------------------------------- |
| `branch-name`     | Yes      | -                                              | Worktree 用のブランチ名               |
| `worktree-dir`    | Yes      | -                                              | Worktree のディレクトリパス           |
| `gitsign-version` | No       | `v0.14.0`                                      | インストールする Gitsign のバージョン |
| `user-name`       | No       | `github-actions[bot]`                          | コミット用の Git ユーザー名           |
| `user-email`      | No       | `github-actions[bot]@users.noreply.github.com` | コミット用の Git メールアドレス       |

<!-- markdownlint-enable -->

## Outputs

| Output          | Description                                                      |
| --------------- | ---------------------------------------------------------------- |
| `worktree-path` | 作成された worktree の絶対パス                                   |
| `status`        | セットアップステータス (success, failed, warning, skipped)       |
| `message`       | ステータスの詳細メッセージ                                       |

## Usage

### Basic Usage

```yaml
- name: gitsign で worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/my-worktree
```

### Full Example with Signed Commits

```yaml
name: 署名付きコミットの作成

permissions:
  id-token: write
  contents: write

jobs:
  create-commit:
    runs-on: ubuntu-latest
    steps:
      - name: リポジトリをチェックアウト
        uses: actions/checkout@v4

      - name: gitsign で worktree を初期化
        uses: ./.github/actions/pr-worktree-setup
        id: init
        with:
          branch-name: feature/my-branch
          worktree-dir: ${{ runner.temp }}/worktree

      - name: 変更を加えてコミット
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          echo "Hello, World!" > hello.txt
          git add hello.txt
          git commit -m "feat: add hello world"
          git push origin feature/my-branch

      - name: 署名付きコミットを検証
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          git log -1 --show-signature

      - name: worktree をクリーンアップ
        if: always()
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

### Custom Gitsign Version

```yaml
- name: 特定の gitsign バージョンで worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    gitsign-version: v0.13.0
```

### Custom User Configuration

```yaml
- name: カスタムユーザーで worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

## How It Works

1. **Install Gitsign**: 公式 Sigstore リリースから gitsign バイナリをダウンロードしてインストール
2. **Validate Installation**: gitsign がインストールされ、OIDC 環境が利用可能であることを確認
3. **Create Worktree**: 指定されたブランチで git worktree を作成
4. **Configure Gitsign**: x509 形式を使用した署名付きコミット用の git 設定
5. **Set User Config**: git ユーザー名とメールアドレスを設定

## Git Configuration

このアクションは、worktree を以下の設定で自動的に構成します。

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
git config --local user.name "github-actions[bot]"
git config --local user.email "github-actions[bot]@users.noreply.github.com"
```

## Verification

コミットが署名されていることを確認するには、次のコマンドを実行します。

```bash
# 署名情報を表示
git log -1 --show-signature

# コミット署名を検証
git verify-commit HEAD
```

期待される出力には以下が含まれます。

<!-- cspell:words Fulcio Rekor -->

- Fulcio 証明書情報
- Rekor 透明性ログエントリ
- GitHub Actions OIDC 発行者情報

## Troubleshooting

### Error: "ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"

**Cause**: `id-token: write` パーミッションが不足。

**Solution**: ワークフローにパーミッションを追加してください。

```yaml
permissions:
  id-token: write
```

### Error: "gitsign is not installed or not in PATH"

**Cause**: インストールステップが失敗したか、バイナリにアクセスできない。

**Solution**: インストールエラーのワークフローログを確認してください。ランナーが GitHub リリースからダウンロードするためのネットワークアクセスを持っていることを確認してください。

### Error: "Failed to download gitsign binary"

**Cause**: ネットワークの問題または無効なバージョン。

**Solution**:

- ネットワーク接続を確認
- gitsign-version が有効であることを確認 ([リリース](https://github.com/sigstore/gitsign/releases)を参照)
- まずデフォルトバージョンを試す

### Commits Not Signed

**Cause**: 設定の問題または OIDC トークンの問題。

**Solution**:

- `id-token: write` パーミッションが設定されていることを確認
- アクションログで検証出力を確認
- コミットが worktree ディレクトリ内で行われていることを確認

## Security Considerations

**No Long-Lived Secrets:**

- 一時証明書には GitHub Actions OIDC を使用
- 管理または保存する GPG キーなし
- 証明書は短期間で、ワークフロー実行に紐付けられる

**Required Permissions:**

- `id-token: write` - OIDC トークンアクセスのみ
- `contents: write` - Git 操作のみ

**Transparency:**

- すべての署名は Rekor 透明性ログに記録される
- 公開監査可能な署名イベント

## Maintenance

### Updating Gitsign Version

新しい gitsign バージョンがリリースされた場合の手順は次のとおりです。

1. まず機能ブランチでテスト
2. `action.yml` のデフォルトバージョンを更新
3. テストワークフローで検証

### Compatibility

- OS: Linux のみ (ubuntu-latest 推奨)
- Git: 2.30+ 推奨
- Gitsign: 0.13.0+ サポート

## License

MIT License - リポジトリの LICENSE ファイルを参照。

## References

- [Gitsign Documentation](https://github.com/sigstore/gitsign)
- [Sigstore](https://www.sigstore.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
