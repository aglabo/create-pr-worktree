# PR Worktree Cleanup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length no-duplicate-heading -->

Composite action to safely and idempotently remove git worktrees.

## TL;DR

- Always specify `worktree-dir` explicitly in production (auto-detection is fallback, less reliable)
- Use `if: always() && steps.init.outcome == 'success'` as base pattern (ensures rerun safety)
- Use `reason` output to distinguish all 12 result patterns (success/skipped/error all have reasons)

---

## Overview

### What This Action Does

Safely removes git worktrees created by `pr-worktree-setup`. Key features:

- Safety: Multi-layer validation prevents accidental deletion
- Idempotency: Safe to run multiple times (rerun-safe)
- Transparency: Detailed reason codes explain results
- Fail-fast: Validation errors fail immediately (CLAUDE.md compliant)

### Main Features

- Worktree existence and git registration validation
- Uncommitted changes detection (controlled by force option)
- Safe skip when multiple worktrees exist
- Rich outputs (status + 12 reason codes)
- Guaranteed cleanup with `if: always()`

---

## Quick Start (Recommended Pattern)

Most safe and recommended usage:

```yaml
- name: Initialize worktree
  id: init-worktree
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

# ... do work in worktree ...

- name: Cleanup worktree
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

## Inputs

| Input          | Required | Default | Description                                                              |
| -------------- | -------- | ------- | ------------------------------------------------------------------------ |
| `worktree-dir` | No       | -       | Directory path of the worktree to remove (auto-detected if not provided) |
| `base-branch`  | No       | -       | Base branch to exclude from cleanup (auto-detected if not provided)      |
| `force`        | No       | `false` | Force removal even if worktree has uncommitted changes                   |

## Outputs

| Output         | Description                                           |
| -------------- | ----------------------------------------------------- |
| `status`       | Status of cleanup operation (success, skipped, error) |
| `message`      | Detailed message about the cleanup operation          |
| `removed-path` | Path of the removed worktree                          |

## Usage

### Basic Usage with if: always()

```yaml
- name: Cleanup worktree
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/my-worktree
```

The `if: always()` condition ensures cleanup runs even if previous steps fail.

### Integration with pr-worktree-setup

```yaml
name: Create Signed PR

permissions:
  contents: write

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Initialize worktree
      - name: Initialize worktree
        id: init
        uses: ./.github/actions/pr-worktree-setup
        with:
          branch-name: feature/my-feature
          worktree-dir: ${{ runner.temp }}/pr-worktree

      # Do work
      - name: Make changes
        run: |
          cd ${{ steps.init.outputs.worktree-path }}
          # ... work ...

      # Cleanup (always runs)
      - name: Cleanup worktree
        if: always() && steps.init.outcome == 'success'
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.init.outputs.worktree-path }} # Explicit path
```

Key points:

1. Always specify `worktree-dir`: Auto-detection is fallback (see below)
2. Use `if: always() && steps.init.outcome == 'success'`: Ensures rerun safety
3. Pass `worktree-path` output: Direct pass from initialization step

---

## Prerequisites (REQUIRED)

### Required Preconditions

Before using this action, you MUST satisfy:

| Precondition         | Description                                                      |
| -------------------- | ---------------------------------------------------------------- |
| Repository checkout  | Checked out with `actions/checkout@v4` or equivalent             |
| Worktree creation    | Created by `pr-worktree-setup` or `git worktree add`             |
| Same job execution   | Must run in the same job where worktree was created              |
| Linux runner         | ubuntu-latest recommended (Windows/macOS not supported)          |
| Git repository       | `.git` directory must exist                                      |
| Base branch checkout | Only required for auto-detection (not needed with explicit path) |

### NOT Supported

Following scenarios are NOT supported and will fail or behave unexpectedly:

| Scenario                                | Reason                                                         |
| --------------------------------------- | -------------------------------------------------------------- |
| Cleanup worktree from different job     | Filesystem not shared between jobs                             |
| Job rerun with worktree already removed | Use `if: steps.init.outcome == 'success'` to avoid             |
| Windows/macOS runners                   | Not tested, no guarantees                                      |
| Non-git directories                     | Not registered as git worktree                                 |
| Manual removal before action            | Will safely skip with `status=skipped, reason=already-removed` |

### Required Permissions and Runner

Workflow permissions:

```yaml
permissions:
  contents: write # Required for git operations
```

Runner requirements:

- OS: Linux (amd64) - ubuntu-latest recommended
- Git: 2.30+ recommended (for worktree stability)

---

## Inputs and Outputs

### Inputs

| Input          | Required | Default | Description                                                                                       |
| -------------- | -------- | ------- | ------------------------------------------------------------------------------------------------- |
| `worktree-dir` | No       | -       | [Strongly Recommended] Path to worktree to remove. Explicit specification recommended (see below) |
| `base-branch`  | No       | -       | Base branch to exclude from auto-detection (fallback: GITHUB_BASE_REF → main)                     |
| `force`        | No       | `false` | Force removal even with uncommitted changes                                                       |

#### Importance of worktree-dir

Always specify explicitly in production:

| Specification | Benefits                      | Drawbacks                     |
| ------------- | ----------------------------- | ----------------------------- |
| Explicit      | Rerun-safe, debuggable, clear | None (recommended)            |
| Auto-detect   | Less code                     | Rerun fails, complex, fragile |

Auto-detection limitations:

- Fails on job reruns (worktree already removed)
- Skips with `reason=multiple` when multiple worktrees exist
- Requires base branch checkout
- Difficult to debug

Recommended pattern:

```yaml
# Recommended
- id: init
  uses: ./.github/actions/pr-worktree-setup
  with:
    worktree-dir: ${{ runner.temp }}/pr-worktree

- uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }}

# Not recommended (fallback acceptable)
- uses: ./.github/actions/pr-worktree-cleanup
  # worktree-dir not specified = auto-detection
```

### Force Removal

```yaml
- name: Force cleanup worktree
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: true
```

With `force: true`, the worktree will be removed even if uncommitted changes exist. This is useful for CI/CD environments where temporary worktrees need to be cleaned up reliably.

The default is `force: false`, which aborts removal with `error` status if uncommitted changes exist. This prevents unintended work loss.

### Force Removal: force=true

```yaml
- name: Force cleanup
  uses: ./.github/actions/pr-worktree-cleanup
```

When no inputs are provided, the action automatically:

1. Detects the current branch as the base branch
2. Uses `git worktree list --porcelain` to accurately find worktrees that are NOT the base branch
3. Validates worktree count:
   - 0 worktrees: Returns `skipped` status
   - Multiple worktrees: Returns `skipped` status and recommends explicit `worktree-dir` specification
   - 1 worktree: Removes the detected worktree

This is useful when you have a single worktree and want automatic cleanup without tracking worktree paths. Using `--porcelain` format prevents false matches from partial branch name matching. When multiple worktrees exist, explicit `worktree-dir` specification is required for safety.

### Advanced: Reason Code Branching

```yaml
- name: Cleanup worktree
  id: cleanup
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree

- name: Handle results
  if: always()
  run: |
    echo "Cleanup status: ${{ steps.cleanup.outputs.status }}"
    echo "Cleanup message: ${{ steps.cleanup.outputs.message }}"
    if [ "${{ steps.cleanup.outputs.status }}" = "error" ]; then
      echo "::warning::Worktree cleanup failed, may need manual cleanup"
    fi
```

## How It Works

1. **Get Worktree Path**:
   - If `worktree-dir` is provided: Use it directly
   - If not provided: Auto-detect worktree
     - Detect base branch from `base-branch` input or current branch
     - Use `git worktree list --porcelain` to accurately find worktrees that are NOT the base branch
     - Validate worktree count:
       - 0 worktrees: `skipped` (message: "No worktrees found")
       - Multiple worktrees: `skipped` (message: "Multiple worktrees found, specify worktree-dir explicitly")
       - 1 worktree: Set worktree-path
2. **Validate Worktree**: Pre-flight checks for worktree
   - Verify worktree-path is specified
   - Check if directory exists
   - Validate it's a valid git worktree (check for `.git` file)
   - If `force: false`: Check for uncommitted changes
     - If changes exist: Returns `error` status and aborts removal (prevents work loss)
     - If no changes: Proceeds with removal
   - On validation failure: Returns `error` or `skipped` status
3. **Cleanup Worktree**: Remove the worktree
   - Execute `git worktree remove`
   - Use `--force` flag if `force: true`
4. **Output Status**: Returns status (success, skipped, or error) and message

## Status Meanings

| Status    | Description                                      | Exit Code |
| --------- | ------------------------------------------------ | --------- |
| `success` | Worktree removed successfully                    | 0         |
| `skipped` | Worktree doesn't exist (already cleaned)         | 0         |
| `error`   | Removal failed (e.g., not a worktree, git error) | 0         |

**Important**: All statuses exit with code 0. Callers should check the `status` and `message` outputs to determine the result. The action is designed to be idempotent - running it multiple times on the same worktree is safe. If the worktree is already removed, it returns a `skipped` status but doesn't fail.

## Error Handling

### Worktree Already Removed

**Behavior**: Returns `skipped` status, doesn't fail

```bash
status=skipped
message=No worktrees found to clean up (excluding base branch: main)
```

This is normal and expected if cleanup runs multiple times or if the worktree was manually removed.

### Directory Exists But Not a Worktree

**Behavior**: Returns `error` status and fails

```bash
EXIT_STATUS=error:Directory is not a valid git worktree
```

**Solution**: Ensure the path points to a directory created with `git worktree add`.

### Uncommitted Changes with force: false

**Behavior**: Returns `error` status and aborts removal

```bash
status=error
message=Cannot remove worktree with uncommitted changes (force=false): /path/to/worktree
```

**Solution**:

- To preserve work: Commit or stash changes in the worktree
- To force removal: Set `force: true`

### Git Worktree Remove Failed

**Behavior**: Returns `error` status and fails

**Common Causes**:

- Worktree is locked by another process
- Permission issues
- Worktree is corrupted

**Solution**: Check git error message in logs and manually investigate.

## Troubleshooting

### Cleanup Always Shows Skipped

**Cause**: Worktree not found when cleanup runs

**Possible Reasons**:

- Cleanup is running multiple times
- Worktree was never created successfully
- Worktree was removed manually or by another step

**Solution**: Check workflow logs to verify worktree creation succeeded. If using output from `pr-worktree-setup`, ensure the step ID matches.

### Rerun Issues

Problem: Cleanup fails on job rerun

Cause: First run already removed worktree, auto-detection returns `reason=no-worktrees`

Solution:

```yaml
- name: Cleanup worktree
  if: always() && steps.init.outcome == 'success' # Only if init succeeded
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }} # Explicit path
```

### Permission Denied

**Cause**: Git or filesystem permission issues

**Solution**: Ensure the workflow has appropriate permissions and the worktree isn't locked by another process.

## Design Decisions

<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->

### Why Default force: false?

The default `force: false` prioritizes safety. If uncommitted changes exist, the removal fails to prevent unintended work loss.

For CI/CD environments where the worktree is temporary and forced removal is needed, explicitly set `force: true`. Even with `force: false`, a warning is displayed when uncommitted changes exist.

### Why Skipped Instead of Error for Missing Worktree?

Returning a `skipped` status instead of `error` when the worktree doesn't exist makes the action idempotent. This is useful when:

- Cleanup runs in `if: always()` blocks that may execute multiple times
- Another step already removed the worktree
- Worktree creation failed but cleanup still runs

The `skipped` status explicitly indicates "no target" and makes it easier for callers to branch logic. This design prevents false-positive failures in CI/CD pipelines.

### Why Validate It's a Git Worktree?

The validation prevents accidentally running `git worktree remove` on arbitrary directories, which could cause unexpected behavior. By checking for the `.git` file (worktree marker), we ensure the action only operates on legitimate git worktrees.

<!-- textlint-enable ja-technical-writing/no-exclamation-question-mark -->

## Pairing with pr-worktree-setup

This action is designed to pair with `pr-worktree-setup`:

```yaml
# Complete workflow example
- name: Initialize worktree
  id: init
  uses: ./.github/actions/pr-worktree-setup
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

- name: Do work
  run: |
    cd ${{ steps.init.outputs.worktree-path }}
    # ... changes ...

- name: Cleanup worktree
  if: always() && steps.init.outcome == 'success'
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init.outputs.worktree-path }}
```

### Security Considerations

Safe defaults:

- Only removes git worktrees (validates `.git` file exists)
- Won't remove arbitrary directories
- Informative error messages ensure transparency

Force flag:

- `force: true`: Removes uncommitted changes (`reason=removed-dirty`)
- `force: false`: Protects uncommitted changes (errors with `reason=uncommitted`)
- Choose based on workflow requirements

### License

MIT License - See repository LICENSE file

### Further Reading

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [CLAUDE.md - AI Collaboration Guide](../../../CLAUDE.md)

---

Last Updated: 2026-02-04
Version: 2.0 (Unified Reason Field)
