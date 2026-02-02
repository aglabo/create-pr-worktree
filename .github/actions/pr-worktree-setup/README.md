# PR Worktree Setup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

A Composite Action that creates a git worktree for keyless signed commits using Sigstore and configures gitsign.

## Overview

This action simplifies the process of creating a git worktree configured with gitsign for commit signing. It consolidates worktree creation, gitsign installation, and configuration into a single reusable step.

**Key Features:**

- Worktree creation
- Gitsign installation
- Automatic configuration for signed commits with gitsign

**Important Notice:**

This action creates a git worktree but does not change the working directory
of subsequent steps.
Callers MUST cd into the worktree directory or use working-directory.

## Prerequisites

**Required Workflow Setup:**

- Repository must be checked out using `actions/checkout` before this action
- Base branch must be checked out (worktree will be created from current branch)
- Working directory must be the repository root

**Required Permissions:**

```yaml
permissions:
  id-token: write # Required for OIDC token access (gitsign keyless signing)
  contents: write # Required for Git operations
```

**Runner Requirements:**

- Linux runner (amd64) - ubuntu-latest recommended
- Git 2.30+ recommended (for worktree stability)

## Inputs

<!-- markdownlint-disable table-column-style -->

| Input             | Required | Default                                        | Description                     |
| ----------------- | -------- | ---------------------------------------------- | ------------------------------- |
| `branch-name`     | Yes      | -                                              | Branch name for the worktree    |
| `worktree-dir`    | Yes      | -                                              | Directory path for the worktree |
| `gitsign-version` | No       | `v0.14.0`                                      | Gitsign version to install      |
| `user-name`       | No       | `github-actions[bot]`                          | Git user name for commits       |
| `user-email`      | No       | `github-actions[bot]@users.noreply.github.com` | Git email address for commits   |

<!-- markdownlint-enable table-column-style -->

## Outputs

| Output          | Description                                                                                                            |
| --------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `gitsign-path`  | Absolute path to the installed gitsign binary                                                                          |
| `worktree-path` | Absolute path to the created worktree                                                                                  |
| `status`        | Overall setup status: `success`=all 6 steps completed (worktree creation and signature setup), `error`=any step failed |
| `message`       | Detailed status message                                                                                                |

## Usage

### Basic Usage

```yaml
- name: Initialize worktree with gitsign
  uses: ./.github/actions/pr-worktree-setup
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
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Initialize worktree with gitsign
        uses: ./.github/actions/pr-worktree-setup
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

      - name: Clean up worktree
        if: always()
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

### Custom Gitsign Version

```yaml
- name: Initialize worktree with specific gitsign version
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    gitsign-version: v0.13.0
```

### Custom User Configuration

```yaml
- name: Initialize worktree with custom user
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

## How It Works

1. **Install Gitsign**: Downloads and installs the gitsign binary from the official Sigstore releases
2. **Validate Installation**: Verifies that gitsign is installed and OIDC environment is available
3. **Create Worktree**: Creates a git worktree with the specified branch
4. **Configure Gitsign**: Sets up git configuration for signed commits using x509 format
5. **Set User Config**: Configures git user name and email address

## Git Configuration

This action automatically configures the worktree with the following settings:

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
git config --local user.name "github-actions[bot]"
git config --local user.email "github-actions[bot]@users.noreply.github.com"
```

## Verification

To verify that commits are signed, run the following commands:

```bash
# Display signature information
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

**Cause**: Missing `id-token: write` permission.

**Solution**: Add the permission to your workflow:

```yaml
permissions:
  id-token: write
```

### Error: "gitsign is not installed or not in PATH"

**Cause**: Installation step failed or binary is not accessible.

**Solution**: Check workflow logs for installation errors. Ensure the runner has network access to download from GitHub releases.

### Error: "Failed to download gitsign binary"

**Cause**: Network issues or invalid version.

**Solution**:

- Check network connectivity
- Verify gitsign-version is valid (see [releases](https://github.com/sigstore/gitsign/releases))
- Try the default version first

### Commits Not Signed

**Cause**: Configuration issue or OIDC token issue.

**Solution**:

- Ensure `id-token: write` permission is set
- Check validation output in action logs
- Verify commits are made within the worktree directory

## Security Considerations

**No Long-Lived Secrets:**

- Uses GitHub Actions OIDC for ephemeral certificates
- No GPG keys to manage or store
- Certificates are short-lived and tied to workflow execution

**Required Permissions:**

- `id-token: write` - OIDC token access only
- `contents: write` - Git operations only

**Transparency:**

- All signatures are recorded in Rekor transparency log
- Publicly auditable signing events

## Internal ABI Contract

This action guarantees the following contract between internal scripts:

### install-gitsign.sh

**MUST provide outputs:**

- `gitsign-path`: Absolute path to the gitsign binary

**Contract validation:**

`validate-gitsign.sh` receives `gitsign-path` as an argument and validates:

1. Output is not empty
2. Binary exists at the specified path
3. Binary is executable

**Breaking this contract:**

If `install-gitsign.sh` does not write `gitsign-path` to `$GITHUB_OUTPUT`, the `validate-gitsign` step will fail-fast immediately.

### validate-gitsign.sh

**Input contract:**

- `$1`: gitsign-path (required argument)

**MUST validate:**

1. Argument is not empty (output contract check)
2. gitsign binary existence
3. gitsign binary execution permissions
4. OIDC environment variable settings
5. gitsign version command executability

**Success guarantee:**

If `validate-gitsign.outcome == 'success'`, gitsign is ready for use.

### Design Principle

- Fail-fast: Detect contract violations as early as possible
- Explicit over implicit: Explicit validation instead of implicit assumptions
- Executable contract: Contract guaranteed by code, not just documentation

## Maintenance

### Updating Gitsign Version

When a new gitsign version is released, follow these steps:

1. Test in a feature branch first
2. Update the default version in `action.yml`
3. Verify with test workflows

### Compatibility

- OS: Linux only (ubuntu-latest recommended)
- Git: 2.30+ recommended
- Gitsign: 0.13.0+ supported

## License

MIT License - See the LICENSE file in the repository.

## References

- [Gitsign Documentation](https://github.com/sigstore/gitsign)
- [Sigstore](https://www.sigstore.dev/)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
