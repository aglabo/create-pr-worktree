# PR Worktree セットアップ

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

Sigstore を使用したキーレス署名付きコミットのための git worktree を作成し、gitsign を設定する Composite Action。

## 概要

このアクションは、コミット署名用に gitsign が設定された git worktree を作成するプロセスを簡素化します。worktree の作成、gitsign のインストール、および設定を単一の再利用可能なステップにまとめます。

**主要機能:**

- Worktree 作成
- Gitsign のインストール
- Gitsign による署名付きコミット自動設定

**重要な注意事項:**

このアクションは git worktree を作成しますが、後続のステップの作業ディレクトリは変更しません。
呼び出し元は worktree ディレクトリに cd するか、working-directory の使用が必要です。

## 前提条件

### 必須要件

以下は pr-worktree-setup を使用するために**必須**です。

**ワークフロー設定:**

- このアクションの前に `actions/checkout` を使用してリポジトリをチェックアウト
- 作業ディレクトリはリポジトリルート

**必要なパーミッション:**

```yaml
permissions:
  id-token: write # OIDC トークンアクセスに必要 (gitsign keyless signing)
  contents: write # Git 操作に必要
```

**ランナー要件:**

- Linux ランナー (amd64) - ubuntu-latest, ubuntu-22.04, または ubuntu-20.04
- Git 2.0+（GitHub-hosted runners に標準装備）

### 推奨要件

**Git バージョン:**

- Git 2.30+ 推奨 (worktree 安定性のため)
- Git 2.0+ で動作しますが、2.30 未満では機能制限の可能性があります

**ベースブランチ:**

- Worktree 作成前にベースブランチをチェックアウト推奨
- 指定しない場合、現在のブランチから worktree が作成されます

### 単体使用時の要件

pr-worktree-setup を他のアクション（create-pr-from-worktree、pr-worktree-cleanup）なしで単体で使用する場合の最低要件。

- Linux runner (ubuntu-latest 推奨)
- Git 2.0+（GitHub-hosted runners に標準装備）
- 上記の必須パーミッション（id-token: write, contents: write）

> 補足:
> このアクションは単体で Worktree 作成と Sigstore 署名設定を完了します。
> create-pr-from-worktree と組み合わせる場合、追加のパーミッション（`pull-requests: write`）および GitHub CLI (`gh`) が必要です。

## 入力

<!-- markdownlint-disable table-column-style -->

| 入力              | 必須   | デフォルト                                     | 説明                                  |
| ----------------- | ------ | ---------------------------------------------- | ------------------------------------- |
| `branch-name`     | はい   | -                                              | Worktree 用のブランチ名               |
| `worktree-dir`    | はい   | -                                              | Worktree のディレクトリパス           |
| `gitsign-version` | いいえ | `v0.14.0`                                      | インストールする Gitsign のバージョン |
| `user-name`       | いいえ | `github-actions[bot]`                          | コミット用の Git ユーザー名           |
| `user-email`      | いいえ | `github-actions[bot]@users.noreply.github.com` | コミット用の Git メールアドレス       |

## 出力

| 出力            | 説明                                                                                                                 |
| --------------- | -------------------------------------------------------------------------------------------------------------------- |
| `gitsign-path`  | インストールされた gitsign バイナリへの絶対パス                                                                      |
| `worktree-path` | 作成された worktree の絶対パス                                                                                       |
| `status`        | 全体のセットアップステータス: `success`=worktree作成と署名設定まで全完了 (6ステップ), `error`=いずれかのステップ失敗 |
| `message`       | ステータスの詳細メッセージ                                                                                           |

<!-- markdownlint-enable table-column-style -->

## 使用方法

### 基本的な使用方法

```yaml
- name: gitsign で worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/my-worktree
```

### 署名付きコミットの完全な例

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

### カスタム Gitsign バージョン

```yaml
- name: 特定の gitsign バージョンで worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    gitsign-version: v0.13.0
```

### カスタムユーザー設定

```yaml
- name: カスタムユーザーで worktree を初期化
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

## 動作の仕組み

1. **Gitsign のインストール**: 公式 Sigstore リリースから gitsign バイナリをダウンロードしてインストール
2. **インストールの検証**: gitsign がインストールされ、OIDC 環境が利用可能であることを確認
3. **Worktree の作成**: 指定されたブランチで git worktree を作成
4. **Gitsign の設定**: x509 形式を使用した署名付きコミット用の git 設定
5. **ユーザー設定**: git ユーザー名とメールアドレスを設定

## Git 設定

このアクションは、worktree を以下の設定で自動的に構成します。

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
git config --local user.name "github-actions[bot]"
git config --local user.email "github-actions[bot]@users.noreply.github.com"
```

## 検証

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

## トラブルシューティング

### エラー: "ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"

**原因**: `id-token: write` パーミッションが不足。

**解決方法**: ワークフローにパーミッションを追加してください。

```yaml
permissions:
  id-token: write
```

### エラー: "gitsign is not installed or not in PATH"

**原因**: インストールステップが失敗したか、バイナリにアクセスできない。

**解決方法**: インストールエラーのワークフローログを確認してください。ランナーが GitHub リリースからダウンロードするためのネットワークアクセスを持っていることを確認してください。

### エラー: "Failed to download gitsign binary"

**原因**: ネットワークの問題または無効なバージョン。

**解決方法**:

- ネットワーク接続を確認
- gitsign-version が有効であることを確認 ([リリース](https://github.com/sigstore/gitsign/releases)を参照)
- まずデフォルトバージョンを試す

### コミットが署名されない

**原因**: 設定の問題または OIDC トークンの問題。

**解決方法**:

- `id-token: write` パーミッションが設定されていることを確認
- アクションログで検証出力を確認
- コミットが worktree ディレクトリ内で行われていることを確認

## FAQ

### 動作環境の検証について

このアクション単体でも動作しますが、動作環境を保証するために [validate-environment](https://github.com/aglabo/.github/tree/main/.github/actions/validate-environment) アクションの使用を推奨します。

事前の環境検証により、以下を確認できます。

- Linux runner の確認
- Git バージョンの確認
- 必要なツールの存在確認

使用例:

```yaml
- name: Validate environment
  uses: aglabo/.github/.github/actions/validate-environment@r1.2.0
  with:
    additional_apps: "gh|gh|regex:version ([0-9.]+)|2.0"

- name: Setup PR worktree
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
```

環境検証により、セットアップ失敗を早期に検出し、明確なエラーメッセージを提供できます。

## セキュリティ上の考慮事項

**長期シークレットなし:**

- 一時証明書には GitHub Actions OIDC を使用
- 管理または保存する GPG キーなし
- 証明書は短期間で、ワークフロー実行に紐付けられる

**必要なパーミッション:**

- `id-token: write` - OIDC トークンアクセスのみ
- `contents: write` - Git 操作のみ

**透明性:**

- すべての署名は Rekor 透明性ログに記録される
- 公開監査可能な署名イベント

## 内部 ABI 契約

このアクションは内部スクリプト間で以下の契約を保証します。

### install-gitsign.sh

**提供する必要がある出力:**

- `gitsign-path`: gitsign バイナリへの絶対パス

**契約の検証:**

`validate-gitsign.sh` が引数として `gitsign-path` を受け取り、以下を検証します。

1. output が空でないこと
2. 指定されたパスにバイナリが存在すること
3. バイナリが実行可能であること

**契約違反:**

もし `install-gitsign.sh` が `gitsign-path` を `$GITHUB_OUTPUT` に書き込まない場合、`validate-gitsign` ステップが fail-fast で即座に失敗します。

### validate-gitsign.sh

**入力契約:**

- `$1`: gitsign-path (必須引数)

**検証する必要があるもの:**

1. 引数が空でないこと (output contract check)
2. gitsign バイナリの存在
3. gitsign バイナリの実行権限
4. OIDC 環境変数の設定
5. gitsign version コマンドの実行可否

**成功保証:**

`validate-gitsign.outcome == 'success'` なら、gitsign は正常に使用可能です。

### 設計原則

- Fail-fast: 契約違反は可能な限り早期に検出
- Explicit over implicit: 暗黙の仮定ではなく、明示的な検証
- Executable contract: ドキュメントだけでなく、コードで契約を保証

## メンテナンス

### Gitsign バージョンの更新

新しい gitsign バージョンがリリースされた場合の手順は次のとおりです。

1. まず機能ブランチでテスト
2. `action.yml` のデフォルトバージョンを更新
3. テストワークフローで検証

### 互換性

- OS: Linux のみ (ubuntu-latest 推奨)
- Git: 2.30+ 推奨
- Gitsign: 0.13.0+ サポート

## ライセンス

MIT License - リポジトリの LICENSE ファイルを参照。

## 参考文献

- [Gitsign ドキュメント](https://github.com/sigstore/gitsign)
- [Sigstore](https://www.sigstore.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
