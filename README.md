---
title: create-pr-worktree
description: Worktree-based GitHub Actions toolkit for creating pull requests safely and reproducibly
---

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

[![CI Status](https://github.com/atsushifx/create-pr-worktree/workflows/CI/badge.svg)](https://github.com/atsushifx/create-pr-worktree/actions)
[![Version](https://img.shields.io/badge/version-0.0.1-blue.svg)](https://github.com/atsushifx/create-pr-worktree/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)

A set of Composite Actions for safe and transparent PR automation using the Git Worktree strategy.

## Features

**Safe Work Environment Isolation**: The Git Worktree strategy allows you to work on PRs without contaminating the main branch.

**Verifiable Commit Signatures**: OIDC-based keyless signing with Sigstore gitsign ensures transparency.

**3 Composite Actions**: Setup and cleanup work as a pair to ensure safe Worktree lifecycle management, while PR creation can be used independently.

## Quick Start

Below is a minimal working workflow example. You can copy and paste it to use.

```yaml
name: Auto PR with Worktree
on: push

permissions:
  id-token: write # Required for Sigstore signature
  contents: write # Required for Git operations and label creation
  pull-requests: write # Required for PR creation

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      # Note: Steps without working-directory are executed in the base directory

      # Checkout repository
      - uses: actions/checkout@v4

      # Validate environment (recommended: works without it, but recommended to ensure operating environment)
      - name: Validate environment
        uses: aglabo/.github/.github/actions/validate-environment@r1.2.0
        with:
          additional_apps: "gh|gh|regex:version ([0-9.]+)|2.0"

      # 1. Create Worktree and set up gitsign
      - name: Setup PR worktree
        id: setup
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: auto-fix/${{ github.ref_name }}
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # 2. Work within the Worktree
      - name: Make changes in worktree
        working-directory: ${{ steps.setup.outputs.worktree-path }}
        run: |
          echo "fix" > fix.txt
          git add fix.txt
          git commit -m "fix: Apply auto-fix"
          git push origin auto-fix/${{ github.ref_name }}

      # 3. Create PR
      - name: Create PR
        uses: ./.github/actions/create-pr-from-worktree
        with:
          pr-branch: auto-fix/${{ github.ref_name }}
          pr-title: "fix: Apply auto-fix"
          pr-body: "Auto-generated PR"
          labels: "automated,fix"

      # 4. Cleanup Worktree (always executed)
      - name: Cleanup worktree
        if: always() && steps.setup.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

**Expected Result**: When you run this workflow, a PR is automatically created with commits signed by Sigstore.

**Important Notes**:

- The PR creation step does not specify `working-directory`. Due to GitHub Actions specifications, the working directory is reset for each step and runs in the base directory.
- `steps.setup.outputs.worktree-path` should only be used for the `working-directory` of steps that work within the Worktree.

## 3 Composite Actions

This project consists of the following 3 Composite Actions.

```text
1. pr-worktree-setup → 2. create-pr-from-worktree → 3. pr-worktree-cleanup
```

### 1. pr-worktree-setup

Creates a Worktree and sets up Sigstore gitsign.
Creates a new branch Worktree and automatically configures gitsign for commit signing.

Key Output (Contract)

| Name            | Meaning                           | Usage                                                                   |
| --------------- | --------------------------------- | ----------------------------------------------------------------------- |
| `worktree-path` | Absolute path to created Worktree | Use only for `working-directory` of steps that work within the Worktree |

[See pr-worktree-setup README for details](./.github/actions/pr-worktree-setup/README.md)

### 2. create-pr-from-worktree

Creates or updates a PR from commits worked in the Worktree.
Supports automatic base branch detection, labeling, and auto-merge settings.

⚠ **Important Constraint**:
This action assumes execution in the base directory.
Do not specify `working-directory` for this step. It will cause misdetection of the base branch.

[See create-pr-from-worktree README for details](./.github/actions/create-pr-from-worktree/README.md)

### 3. pr-worktree-cleanup

Safely deletes the Worktree after work is complete.
Features detection of uncommitted changes and skip functionality when multiple Worktrees exist.

[See pr-worktree-cleanup README for details](./.github/actions/pr-worktree-cleanup/README.md)

**Why split into 3**: Designed with separation of concerns and reusability in mind. `pr-worktree-setup` and `pr-worktree-cleanup` should always be used as a pair to manage Worktree lifecycle (cleanup is idempotent, so it can run standalone, but the correct pattern is setup → work → cleanup). `create-pr-from-worktree` can be used independently. Each action can be verified and tested independently.

## Architecture

### Worktree Strategy

```text
┌─────────────────────────────────────────────┐
│ Main Repository (main - always clean)       │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-setup
┌─────────────────────────────────────────────┐
│ Worktree (isolated work environment)        │
│ - Checked out to PR branch                  │
│ - Sigstore gitsign configured               │
│ - Work: git commit → git push               │
│   (with working-directory specified)        │
└─────────────────────────────────────────────┘
              ↓ create-pr-from-worktree (base directory)
┌─────────────────────────────────────────────┐
│ Main Repository (stays on main)             │
│ - Execute create-pr-from-worktree           │
│ - Auto-detect base branch (main)            │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-cleanup (base directory)
┌─────────────────────────────────────────────┐
│ Cleanup complete - main stays clean         │
└─────────────────────────────────────────────┘
```

**Why main branch doesn't get contaminated**: Since you work within the Worktree, there's no impact on the main branch. Even if PR work fails, main always maintains a clean state.

**Base branch auto-detection mechanism**: Gets the currently checked-out branch with `git symbolic-ref --short HEAD`. Since each step runs in the base directory by default, main is automatically detected as the base branch.

## Security Features

### OIDC-based Keyless Signing

Signing with temporary certificates using GitHub Actions OIDC tokens. No need to manage GPG keys, and certificates are short-lived per workflow execution.

### Rekor Transparency Log

All signatures are recorded in Rekor and are available for public audit. Ensures transparency of signing events.

### Git Configuration

The following configurations are automatically applied within the Worktree.

```bash
git config --local commit.gpgsign true
git config --local gpg.format x509
git config --local gpg.x509.program gitsign
```

## Usage Examples

### Basic Pattern

A standard workflow using all three actions.

```yaml
# Note: Steps without working-directory are executed in the base directory

# Validate environment (recommended: works without it, but recommended to ensure operating environment)
- uses: aglabo/.github/.github/actions/validate-environment@r1.2.0
  with:
    additional_apps: "gh|gh|regex:version ([0-9.]+)|2.0"

- uses: ./.github/actions/pr-worktree-setup
  id: setup
  with:
    branch-name: feature/my-feature
    worktree-dir: ${{ runner.temp }}/worktree

# Work within the Worktree
- working-directory: ${{ steps.setup.outputs.worktree-path }}
  run: |
    # Make changes
    git add .
    git commit -m "feat: Add new feature"
    git push origin feature/my-feature

# Create PR (executed in base directory as step has changed)
- uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description of changes"

# Cleanup (always executed)
- if: always() && steps.setup.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

### Setting Labels and Auto-merge

```yaml
- uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description of changes"
    labels: "enhancement,automated" # Specify labels separated by commas
    merge-method: "squash" # squash/merge/rebase/never
```

### Custom User Configuration

You can use a username and email address other than the default `github-actions[bot]`.

```yaml
- uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-feature
    worktree-dir: ${{ runner.temp }}/worktree
    user-name: "My Bot"
    user-email: "bot@example.com"
```

### ❌ Bad Example

Below is an incorrect usage example that causes misdetection of the base branch.

```yaml
# ❌ Bad Example: Specifying working-directory for PR creation
- name: Create PR
  working-directory: ${{ steps.setup.outputs.worktree-path }}
  uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description"
```

**Problem**: `create-pr-from-worktree` detects the currently checked-out branch as the base branch. If executed within the Worktree, the PR branch itself is misdetected as the base.

**Correct Example**: Do not specify `working-directory` and execute in the base directory.

```yaml
# ✅ Good Example: Not specifying working-directory
- name: Create PR
  uses: ./.github/actions/create-pr-from-worktree
  with:
    pr-branch: feature/my-feature
    pr-title: "feat: Add new feature"
    pr-body: "Description"
```

## Troubleshooting

### Worktree Cleanup Not Executing

**Cause**: The `if: always()` condition is missing, or the setup step has failed.

**Solution**: Configure as follows.

```yaml
- if: always() && steps.setup.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
```

### Commits Not Signed

**Cause**: The `id-token: write` permission is missing.

**Solution**: Add the following permission to the workflow.

```yaml
permissions:
  id-token: write
```

### Auto-merge Not Working

**Cause**: Check repository settings, branch protection rules, status checks, and approval requirements.

**Solution**: Verify that auto-merge is enabled in repository settings and that branch protection rules are configured properly.

See each Action's README for detailed troubleshooting.

## Development Environment

### Setup

```bash
# Install dependencies and set up development environment
pnpm install
```

### Local Validation

```bash
# GitHub Actions syntax validation
actionlint -config-file ./configs/actionlint.yaml .github/workflows/*.yml

# Security best practices validation
ghalint run --config ./configs/ghalint.yaml

# Secret leakage detection
gitleaks detect --source . --verbose

# Japanese documentation proofreading
pnpm run lint:text

# Formatting
dprint fmt
```

### Commit Flow

The following are automatically executed by lefthook.

- pre-commit - dprint/prettier + actionlint + ghalint + textlint
- commit-msg - AI-generated message + commitlint validation
- pre-push - gitleaks scan

See [CONTRIBUTING.ja.md](./CONTRIBUTING.ja.md) for details.

## Links

### Action Documentation

- [pr-worktree-setup README](./.github/actions/pr-worktree-setup/README.md)
- [create-pr-from-worktree README](./.github/actions/create-pr-from-worktree/README.md)
- [pr-worktree-cleanup README](./.github/actions/pr-worktree-cleanup/README.md)
- [validate-environment](https://github.com/aglabo/.github/tree/main/.github/actions/validate-environment) - Environment validation action (recommended: works without it, but recommended to ensure operating environment)

### Project Documentation

- [CONTRIBUTING.ja.md](./CONTRIBUTING.ja.md) - Contribution guidelines
- [.github/SECURITY.md](./.github/SECURITY.md) - Security policy

### External Resources

- [Sigstore](https://www.sigstore.dev/) - Signing and Verification
- [Gitsign](https://github.com/sigstore/gitsign) - Git commit signing
- [Git Worktree](https://git-scm.com/docs/git-worktree) - Worktree documentation
- [GitHub Actions](https://docs.github.com/en/actions) - GitHub Actions official documentation

## License

MIT License - Copyright (c) 2026- atsushifx
