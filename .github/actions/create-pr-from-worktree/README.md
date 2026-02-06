# Create PR from Worktree Action

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length -->

## Overview

A set of 3 composite actions for safely creating PRs on worktrees.

### TL;DR (5-line summary)

- What it does: Create PR branches in isolated worktree environments, keeping main clean
- 3-action set: setup (create worktree) → create-pr (this action) → cleanup (remove worktree)
- Requirements: Linux runner, execute all 3 in same job, pr-worktree-setup prerequisite
- Guarantees: Sigstore signing, base branch auto-detection, fail-safe (safe-on-failure) design, reliable cleanup
- Does NOT guarantee: Full safety without worktree strategy, worktree sharing across jobs

### 3 Action Roles

```bash
1. pr-worktree-setup        → Create worktree + configure Sigstore signing
2. create-pr-from-worktree  → Create/update PR (this action)
3. pr-worktree-cleanup      → Remove worktree (if: always())
```

### Why Use Worktree Strategy

- Protect main branch: PR work doesn't affect main
- Verifiable signatures: Keyless signing with Sigstore gitsign
- Parallel execution safety: Multiple PRs don't interfere
- Clean environment: Reliable cleanup after work

---

## Quick Start

```yaml
name: Auto PR with Worktree
on: push

permissions:
  id-token: write # Sigstore signing
  contents: write # Git operations + label creation
  pull-requests: write # PR operations

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      # Note: Steps without working-directory run in the base directory
      - uses: actions/checkout@v4

      # 1. Setup worktree
      - name: Setup PR worktree
        id: setup
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: auto-fix/${{ github.ref_name }}
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # 2. Work in worktree
      - name: Make changes in worktree
        working-directory: ${{ steps.setup.outputs.worktree-path }}
        run: |
          echo "fix" > fix.txt
          git add fix.txt
          git commit -m "fix: Apply auto-fix"
          git push origin auto-fix/${{ github.ref_name }}

      # 3. Create PR (this action)
      - name: Create PR
        uses: ./.github/actions/create-pr-from-worktree
        with:
          pr-branch: auto-fix/${{ github.ref_name }}
          pr-title: "fix: Apply auto-fix"
          pr-body: "Auto-generated PR"
          labels: "automated,fix"
          merge-method: "squash"

      # 4. Cleanup (always run)
      - name: Cleanup worktree
        if: always() && steps.setup.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.setup.outputs.worktree-path }}
```

**Key Points**:

1. Execute 3 actions in order (setup → create-pr → cleanup)
2. Return to main after working in worktree
3. Guarantee cleanup with `if: always()`

---

## Prerequisites

### Worktree Strategy Requirements

| Requirement             | Description                                                        |
| ----------------------- | ------------------------------------------------------------------ |
| `pr-worktree-setup` run | Worktree must be created                                           |
| PR branch pushed        | Commit and push completed in worktree                              |
| Main branch checked out | Return to main before running `create-pr-from-worktree`            |
| Linux runner            | ubuntu-latest / ubuntu-22.04 / ubuntu-20.04                        |
| Same job execution      | All 3 actions in same job (worktrees cannot be shared across jobs) |

### Required Permissions

```yaml
permissions:
  id-token: write # Required for Sigstore signing in pr-worktree-setup
  contents: write # Required for PR operations + label creation
  pull-requests: write # Required for PR operations
```

> Note:
> With only `contents: write`, label creation may fail but PR creation will succeed (best-effort).

### Required Tools

- GitHub CLI (`gh`) version 2.0+
- jq (JSON processor)

※ Pre-installed on GitHub-hosted runners by default.

---

## Inputs

| Input          | Required | Default  | Description                                           |
| -------------- | -------- | -------- | ----------------------------------------------------- |
| `pr-branch`    | Yes      | -        | PR branch name (head branch)                          |
| `pr-title`     | Yes      | -        | Pull request title                                    |
| `pr-body`      | Yes      | -        | Pull request body/description                         |
| `labels`       | No       | `''`     | Comma-separated labels (e.g., `"automated,fix"`)      |
| `merge-method` | No       | `squash` | Auto-merge method (`merge`/`squash`/`rebase`/`never`) |

**Input Validation**: `merge-method` is whitelist-validated. Typos result in immediate errors.

---

## Outputs

| Output               | Description                                                           |
| -------------------- | --------------------------------------------------------------------- |
| `validation-status`  | Validation result (`ok`, `fail`, `error`, `warning`)                  |
| `validation-message` | Validation status message                                             |
| `pr-number`          | Created/updated PR number (empty on validation failure)               |
| `pr-url`             | Pull request URL (empty on validation failure)                        |
| `pr-operation`       | Operation performed (`created`, `updated`, `update-failed`, or empty) |
| `automerge-status`   | Auto-merge status (`enabled`, `failed`, `timeout`, or empty)          |

※ Recommended: Use `validation-status == 'ok'` for success determination.

**Validation Status**:

- `ok`: All successful
- `fail`: User-correctable (e.g., branch not found)
- `error`: System error (e.g., API failure)
- `warning`: PR created/updated successfully, but additional operations (labels / auto-merge) failed

**Operation Values**:

- `created`: New PR created
- `updated`: Existing PR updated successfully
- `update-failed`: PR exists but update failed (PR number and URL still returned)
- Empty: Validation failed

**Usage Example**:

```yaml
- name: Notify on PR creation
  if: steps.create-pr.outputs.pr-number != ''
  run: echo "PR created: ${{ steps.create-pr.outputs.pr-url }}"
```

---

## Core Concepts

### Worktree Strategy Architecture

```text
┌─────────────────────────────────────────────┐
│ Main Repository (main - always clean)       │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-setup
┌─────────────────────────────────────────────┐
│ Worktree (isolated environment)             │
│ - Checked out to PR branch                  │
│ - Sigstore gitsign configured               │
│ - Work: git commit → git push               │
│   (using working-directory)                 │
└─────────────────────────────────────────────┘
              ↓ create-pr-from-worktree (base directory)
┌─────────────────────────────────────────────┐
│ Main Repository (still in main)             │
│ - Run create-pr-from-worktree               │
│ - Auto-detect base branch (main)            │
└─────────────────────────────────────────────┘
              ↓ pr-worktree-cleanup (base directory)
┌─────────────────────────────────────────────┐
│ Cleanup complete - Worktree removed, main clean │
└─────────────────────────────────────────────┘
```

### Base Branch Auto-Detection

- Auto-detects currently checked-out branch as base
- Retrieved via `git symbolic-ref --short HEAD`
- **Steps run in base directory by default** (unless working-directory is specified)

※ This action treats the "currently checked-out branch" as the base branch.

※ No input option to specify base branch is provided. This design responsibility belongs to the caller workflow.

### Fail-Open Strategy

When PR existence check (`gh pr list`) fails:

1. Treat failure as "PR does not exist"
2. Attempt to create new PR
3. GitHub API rejects duplicate PRs (safety net)

**Reason**: Prioritize availability. Temporary API failures should not prevent PR creation.

※ Final rejection of duplicate PRs is guaranteed by the GitHub API. This action prioritizes availability and does not abort PR creation attempts.

This action does not relax consistency guarantees; PR uniqueness is enforced by the GitHub API.

### Validation Architecture

```text
1. Base Branch Detection → 2. API Rate Limit Check
  → 3. Branch Validation → 4. PR Creation/Update
  → 5. ABI Contract Validation → 6. Labels (best-effort)
  → 7. Auto-Merge (merge-method != 'never')
```

**Fail-First Design**: Does not proceed to PR creation until all validations reach `ok` / `success`.

---

## Label & Auto-Merge

### Labels (Best-Effort)

- Label creation/application is **non-blocking**
- Continues with warning on failure, PR creation succeeds
- Requires `contents: write` permission

### Auto-Merge

- `squash` (default) / `merge` / `rebase` / `never`
- Auto-merge must be enabled in repository
- PR creation succeeds even on failure (`automerge-status=failed`)

---

## Troubleshooting

### Worktree-Related

**"Failed to detect current branch name"**
→ Forgot to return to main. Run `git checkout main` before execution.

**"Branch does not exist on remote"**
→ Forgot to `git push` in worktree. Push before creating PR.

**Worktree cleanup not running**
→ Add `if: always() && steps.setup.outcome == 'success'`.

### Common Issues

**Auto-merge not working**
→ Check repository settings, branch protection, status checks, and approvals.

**Labels not created**
→ Verify `contents: write` permission.

**Timeout detection failed**
→ Use Linux runner (macOS/Windows not supported).

---

## FAQ

### Why are there 3 separate actions?

For separation of concerns and reusability. Each action can be independently verified and tested.

### Can I use it without worktree?

Technically possible, but risks polluting the main branch and Sigstore signing is unavailable. Strongly recommend using the worktree strategy.

### Why not support macOS/Windows?

Depends on GNU `timeout` exit code 124 contract. BSD timeout (macOS) has different exit codes, and Windows lacks a timeout command.

---

## Reference

### Related Actions

- [pr-worktree-setup](../pr-worktree-setup/README.md) - Create worktree and configure Sigstore signing
- [pr-worktree-cleanup](../pr-worktree-cleanup/README.md) - Safely remove worktree

### Documentation

- [GitHub CLI Manual](https://cli.github.com/manual/)
- [GitHub Auto-Merge](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)
- [Composite Actions](https://docs.github.com/en/actions/creating-actions/creating-a-composite-action)
- [Git Worktree](https://git-scm.com/docs/git-worktree)
- [Sigstore Gitsign](https://github.com/sigstore/gitsign)

### Limitations

- Worktree strategy required (3-action set)
- Linux runners only (GNU coreutils timeout required)
- Same job execution (worktrees cannot be shared across jobs)
- Pre-pushed branches required
- Main branch checkout required

---

## License

MIT License - Copyright (c) 2025 atsushifx
