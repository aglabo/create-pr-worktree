# PR Worktree Initialize

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

Composite action to create a git worktree and configure gitsign for keyless signed commits using Sigstore.

## Overview

This action simplifies the process of creating a git worktree with gitsign configured for signing commits. It combines worktree creation, gitsign installation, and configuration into a single reusable step.

**Key Features:**

- Installs gitsign from official Sigstore releases
- Verifies installation with checksum validation
- Creates git worktree for isolated branch work
- Configures gitsign for keyless signing with Sigstore
- Uses GitHub Actions OIDC for authentication (no secrets required)

## Prerequisites

**Required Permissions:**

```yaml
permissions:
  id-token: write # Required for OIDC token access (gitsign keyless signing)
  contents: write # Required for git operations
```

**Runner Requirements:**

- Linux runner (ubuntu-latest recommended)
- Git 2.30+

## Inputs

| Input             | Required | Default                                        | Description                     |
| ----------------- | -------- | ---------------------------------------------- | ------------------------------- |
| `branch-name`     | Yes      | -                                              | Branch name for the worktree    |
| `worktree-dir`    | Yes      | -                                              | Directory path for the worktree |
| `gitsign-version` | No       | `v0.14.0`                                      | Gitsign version to install      |
| `user-name`       | No       | `github-actions[bot]`                          | Git user name for commits       |
| `user-email`      | No       | `github-actions[bot]@users.noreply.github.com` | Git user email for commits      |

## Outputs

| Output               | Description                                    |
| -------------------- | ---------------------------------------------- |
| `worktree-path`      | Absolute path to the created worktree          |
| `validation-status`  | Gitsign validation status (ok, error, warning) |
| `validation-message` | Validation status message                      |
| `gitsign-version`    | Installed gitsign version                      |

## Usage

### Basic Usage

```yaml
- name: Initialize worktree with gitsign
  uses: ./.github/actions/pr-worktree-initialize
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/my-worktree
```

### Full Example with Signed Commits

```yaml
name: Create Signed Commit

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
        uses: ./.github/actions/pr-worktree-initialize
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
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          git log -1 --show-signature

      - name: Cleanup
        if: always()
        run: |
          git worktree remove ${{ steps.init.outputs.worktree-path }} --force
```

### Custom Gitsign Version

```yaml
- name: Initialize worktree with specific gitsign version
  uses: ./.github/actions/pr-worktree-initialize
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    gitsign-version: v0.13.0
```

### Custom User Configuration

```yaml
- name: Initialize worktree with custom user
  uses: ./.github/actions/pr-worktree-initialize
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

## How It Works

1. **Install Gitsign**: Downloads and installs gitsign binary from official Sigstore releases
2. **Validate Installation**: Verifies gitsign is installed and OIDC environment is available
3. **Create Worktree**: Creates git worktree with specified branch
4. **Configure Gitsign**: Sets git config for signed commits using x509 format
5. **Set User Config**: Configures git user name and email

## Git Configuration

The action automatically configures the worktree with:

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
git config --local user.name "github-actions[bot]"
git config --local user.email "github-actions[bot]@users.noreply.github.com"
```

## Verification

To verify that commits are signed:

```bash
# Show signature information
git log -1 --show-signature

# Verify commit signature
git verify-commit HEAD
```

Expected output includes:

<!-- cspell:words Fulcio Rekor -->

- Fulcio certificate information
- Rekor transparency log entry
- GitHub Actions OIDC issuer information

## Troubleshooting

### Error: "ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"

**Cause**: Missing `id-token: write` permission

**Solution**: Add permission to workflow:

```yaml
permissions:
  id-token: write
```

### Error: "gitsign is not installed or not in PATH"

**Cause**: Installation step failed or binary not accessible

**Solution**: Check workflow logs for installation errors. Ensure runner has network access to download from GitHub releases.

### Error: "Failed to download gitsign binary"

**Cause**: Network issue or invalid version

**Solution**:

- Check network connectivity
- Verify gitsign-version is valid (see [releases](https://github.com/sigstore/gitsign/releases))
- Try default version first

### Commits Not Signed

**Cause**: Configuration issue or OIDC token problem

**Solution**:

- Verify `id-token: write` permission is set
- Check validation output in action logs
- Ensure commits are made within the worktree directory

## Security Considerations

**No Long-Lived Secrets:**

- Uses GitHub Actions OIDC for temporary certificates
- No GPG keys to manage or store
- Certificates are short-lived and tied to workflow run

**Required Permissions:**

- `id-token: write` - Only for OIDC token access
- `contents: write` - Only for git operations

**Transparency:**

- All signatures are recorded in Rekor transparency log
- Publicly auditable signing events

## Maintenance

### Updating Gitsign Version

When a new gitsign version is released:

1. Test on a feature branch first
2. Update default version in `action.yml`
3. Verify with test workflow

### Compatibility

- OS: Linux only (ubuntu-latest recommended)
- Git: 2.30+ recommended
- Gitsign: 0.13.0+ supported

## License

MIT License - See repository LICENSE file

## References

- [Gitsign Documentation](https://github.com/sigstore/gitsign)
- [Sigstore](https://www.sigstore.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
