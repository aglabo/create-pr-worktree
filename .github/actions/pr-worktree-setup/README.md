# PR Worktree Setup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

A composite action that creates a `worktree` for pull request creation and configures `gitsign` for signing commits.

## Overview

This action creates a `worktree` for pull request creation.
It also installs and configures `gitsign` to sign commits made in the `worktree`.

> Note:
> This action is paired with the `pr-worktree-cleanup` action.
> The created `worktree` should be removed using the `pr-worktree-cleanup` action.

**Key Features**:

- `worktree` creation
- `gitsign` installation
- Automatic `gitsign` configuration for signed commits

## Prerequisites

**Required Workflow Setup:**

- Repository must be checked out using `actions/checkout` before this action
- Base branch must be checked out (worktree will be created from current branch)
- Working directory must be the repository root

**Required Permissions**:

```yaml
permissions:
  id-token: write # Required for OIDC token access (gitsign keyless signing)
  contents: write # Required for Git operations
  id-token: write # Required for OIDC token access (gitsign keyless signing)
  contents: write # Required for Git operations
```

**Runner Requirements**:

- `Linux` runner (`ubuntu-latest` recommended)
- `Git` 2.30+

## Inputs

<!-- markdownlint-disable table-column-style -->

| Input             | Required | Default                                        | Description                        |
| ----------------- | -------- | ---------------------------------------------- | ---------------------------------- |
| `branch-name`     | Yes      | -                                              | Branch name for PR (newly created) |
| `worktree-dir`    | Yes      | -                                              | Directory path for `worktree`      |
| `gitsign-version` | No       | `v0.14.0`                                      | Version of `gitsign` to install    |
| `user-name`       | No       | `github-actions[bot]`                          | `Git` user name for commits        |
| `user-email`      | No       | `github-actions[bot]@users.noreply.github.com` | `Git` email address for commits    |

<!-- markdownlint-enable table-column-style -->

## Outputs

| Output               | Description                                      |
| -------------------- | ------------------------------------------------ |
| `worktree-path`      | Absolute path of the created `worktree`          |
| `validation-status`  | `gitsign` validation status (ok, error, warning) |
| `validation-message` | Validation status message                        |

### Validation Status Details

The validation output provides the results of `gitsign` configuration verification.

- ok: All validations passed. `gitsign` is correctly installed, `OIDC` environment is available, and signed commits can be created.

- warning: Validation passed with warnings. `gitsign` is operational, but check `validation-message` for details.

- error: Validation failed. There is a problem with `gitsign` setup. Check `validation-message` for specific failure reasons.

**Note**: Validation always exits with exit code 0. Validation results are returned as `validation-status` and `validation-message` outputs. Even with `error` status, the workflow continues, but signed commits may not work correctly.

## Usage

### Basic Usage

```yaml
- name: Initialize worktree with gitsign
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/my-worktree
```

### Full Example with Signed Commits

```yaml
name: Create Signed Commits

permissions:
  id-token: write
  contents: write

jobs:
  create-commit:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize worktree with gitsign
        uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
        id: init
        with:
          branch-name: feature/my-branch
          worktree-dir: ${{ runner.temp }}/worktree

      - name: Make changes and commit
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          echo "Hello, World!" > hello.txt
          git add hello.txt
          git commit -m "feat: add hello world"
          git push origin feature/my-branch

      - name: Verify signed commit
      - name: Verify signed commit
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          git log -1 --show-signature

      - name: Cleanup worktree
        if: always()
        uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
        with:
          worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

### Custom Gitsign Version

```yaml
- name: Initialize worktree with specific gitsign version
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    gitsign-version: v0.13.0
```

### Custom User Configuration

```yaml
- name: Initialize worktree with custom user
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

### Validation Status Check

```yaml
- name: Initialize worktree with gitsign
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-setup@v0.0.1
  id: init
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

- name: Check validation result
  if: steps.init.outputs.validation-status != 'ok'
  run: |
    echo "gitsign validation failed: ${{ steps.init.outputs.validation-message }}"
    exit 1
```

## How It Works

1. **Install Gitsign**: Download and install `gitsign` binary from official `Sigstore` releases
2. **Validate Installation**: Verify that `gitsign` is installed and `OIDC` environment is available
3. **Create Worktree**: Create `git worktree` with the specified branch (branch is newly created)
4. **Configure Gitsign**: Configure `git` for signed commits using `x509` format
5. **Set User Config**: Set `git` user name and email address

## Git Configuration

This action automatically configures the `worktree` with the following settings.

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
git config --local user.name "github-actions[bot]"
git config --local user.email "github-actions[bot]@users.noreply.github.com"
```

## Verification

To verify that commits are signed, run the following commands.

```bash
# Display signature information
git log -1 --show-signature

# Verify commit signature
git verify-commit HEAD
```

Expected output includes:

<!-- cspell:words Fulcio Rekor -->

- `Fulcio` certificate information
- `Rekor` transparency log entry
- `GitHub Actions` `OIDC` issuer information

## Troubleshooting

### Error: "ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"

**Cause**: Missing `id-token: write` permission.
**Cause**: Missing `id-token: write` permission.

**Solution**: Add the permission to your workflow.

```yaml
permissions:
  id-token: write
```

### Error: "gitsign is not installed or not in PATH"

**Cause**: Installation step failed or binary is not accessible.
**Cause**: Installation step failed or binary is not accessible.

**Solution**: Check workflow logs for installation errors. Ensure the runner has network access to download from `GitHub` releases.

### Error: "Failed to download gitsign binary"

**Cause**: Network issues or invalid version.

**Solution**:

- Check network connectivity
- Verify that `gitsign-version` is valid (see [releases](https://github.com/sigstore/gitsign/releases))
- Try the default version first

### Commits Not Signed

**Cause**: Configuration issue or `OIDC` token problem.

**Solution**:

- Verify that `id-token: write` permission is set
- Check validation output in action logs
- Ensure commits are made within the `worktree` directory

## Security Considerations

**No Long-Lived Secrets**:

- Uses `GitHub Actions` `OIDC` for temporary certificates
- No `GPG` keys to manage or store
- Certificates are short-lived and bound to workflow execution

**Required Permissions**:

- `id-token: write` - `OIDC` token access only
- `contents: write` - `Git` operations only

**Transparency**:

- All signatures are recorded in the `Rekor` transparency log
- Publicly auditable signing events

### Worktree Cleanup

**GitHub-hosted runners**: Cleanup is not strictly required. Runners are ephemeral environments that are automatically destroyed after job completion.

**Self-hosted runners**: Strongly recommended to use the `pr-worktree-cleanup` action. Not cleaning up can cause the following issues:

- Disk space accumulation from abandoned `worktree`
- Branch reference leaks in the repository
- Conflicts with future `worktree` operations

**Best Practice**: Use cleanup with `if: always()` to ensure `worktree` is removed even if previous steps fail.

```yaml
- name: Cleanup worktree
  if: always()
  uses: aglabo/create-pr-sandbox/.github/actions/pr-worktree-cleanup@v0.0.1
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

## Maintenance

### Updating Gitsign Version

When a new `gitsign` version is released, follow these steps:

1. Test in a feature branch first
2. Update the default version in `action.yml`
3. Validate with test workflows

### Compatibility

- OS: `Linux` only (`ubuntu-latest` recommended)
- `Git`: 2.30+ recommended
- `gitsign`: 0.13.0+ supported

## License

MIT License - See the LICENSE file in the repository.
MIT License - See the LICENSE file in the repository.

## References

- [Gitsign Documentation](https://github.com/sigstore/gitsign)
- [Sigstore](https://www.sigstore.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
