# PR Worktree Cleanup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- textlint-disable ja-technical-writing/no-exclamation-question-mark -->
<!-- markdownlint-disable line-length -->

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
name: PR Automation Workflow

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

### Outputs

| Output           | Type   | Description                                                 |
| ---------------- | ------ | ----------------------------------------------------------- |
| `status`         | string | Cleanup status (`success`/`skipped`/`error`)                |
| `reason`         | string | Unified reason code explaining result (12 types, see below) |
| `message`        | string | Human-readable detailed message                             |
| `removed-path`   | string | Path of removed worktree (empty if not removed)             |
| `worktree-count` | number | Number of worktrees found in auto-detection (0 if explicit) |
| `worktree-list`  | string | Newline-separated worktree paths from auto-detection        |

#### Complete Reason Code Reference

Single `reason` field explains all situations (12 types):

| status    | reason             | Meaning                                                     |
| --------- | ------------------ | ----------------------------------------------------------- |
| `success` | `removed`          | Clean worktree removed successfully                         |
| `success` | `removed-dirty`    | Worktree with uncommitted changes removed (force=true)      |
| `skipped` | `no-path`          | No worktree-dir specified and auto-detection not applicable |
| `skipped` | `already-removed`  | Directory doesn't exist (idempotent - already cleaned)      |
| `skipped` | `multiple`         | Multiple worktrees found in auto-detection                  |
| `skipped` | `no-worktrees`     | No worktrees found in auto-detection                        |
| `error`   | `not-registered`   | Path exists but not registered as git worktree              |
| `error`   | `missing-marker`   | `.git` file missing (corrupted)                             |
| `error`   | `invalid-worktree` | Not a valid git working tree                                |
| `error`   | `uncommitted`      | Uncommitted changes exist with force=false                  |
| `error`   | `git-failed`       | Git command execution failed                                |
| `error`   | `removal-failed`   | `git worktree remove` command failed                        |

#### Reason Code Usage Examples

Check if worktree was actually removed:

```yaml
- if: steps.cleanup.outputs.reason == 'removed' || steps.cleanup.outputs.reason == 'removed-dirty'
  run: echo "Worktree was removed"
```

Detect uncommitted changes scenarios:

```yaml
# Force removed
- if: steps.cleanup.outputs.reason == 'removed-dirty'
  run: echo "::warning::Uncommitted changes were force-removed"

# Rejected by force=false
- if: steps.cleanup.outputs.reason == 'uncommitted'
  run: echo "::error::Cleanup failed due to uncommitted changes"
```

Handle auto-detection issues:

```yaml
- if: steps.cleanup.outputs.reason == 'multiple'
  run: |
    echo "::warning::Multiple worktrees detected"
    echo "Count: ${{ steps.cleanup.outputs.worktree-count }}"
    echo "List: ${{ steps.cleanup.outputs.worktree-list }}"
```

---

## Usage Patterns

### Basic Pattern: with if: always()

```yaml
- name: Cleanup worktree
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/my-worktree
```

`if: always()` ensures cleanup runs even if previous steps fail.

### Safe Pattern: force=false (default)

```yaml
- name: Safe cleanup
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: false # Default, can be explicit
```

Fails with `reason=uncommitted` if uncommitted changes exist.

### Force Removal: force=true

```yaml
- name: Force cleanup
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: true # Also removes uncommitted changes
```

Succeeds with `reason=removed-dirty` if uncommitted changes exist.

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
    case "${{ steps.cleanup.outputs.reason }}" in
      removed)
        echo "Success: Clean removal"
        ;;
      removed-dirty)
        echo "Warning: Removed with uncommitted changes (force=true)"
        ;;
      already-removed)
        echo "Skip: Already removed (idempotent)"
        ;;
      uncommitted)
        echo "Error: Uncommitted changes prevent removal (force=false)"
        exit 1
        ;;
      multiple)
        echo "Skip: Multiple worktrees detected, explicit specification needed"
        echo "Count: ${{ steps.cleanup.outputs.worktree-count }}"
        ;;
      *)
        echo "Other: ${{ steps.cleanup.outputs.message }}"
        ;;
    esac

- name: Warn on force removal
  if: always() && steps.cleanup.outputs.reason == 'removed-dirty'
  run: |
    echo "::warning::Uncommitted changes were removed"
    echo "Path: ${{ steps.cleanup.outputs.removed-path }}"

- name: Handle errors
  if: always() && steps.cleanup.outputs.status == 'error'
  run: |
    echo "::error::Cleanup failed (reason: ${{ steps.cleanup.outputs.reason }})"
    echo "::error::${{ steps.cleanup.outputs.message }}"
    exit 1
```

### Auto-Detection Mode (Not Recommended, Fallback)

Warning: Auto-detection is a fallback feature. Do not use in production.

```yaml
- name: Auto-detect cleanup
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  # No worktree-dir = auto-detection
```

How auto-detection works:

1. Detect base branch (priority: input → GITHUB_BASE_REF → detection → "main")
2. Search for worktrees other than base branch
3. If exactly 1 found: Remove it, otherwise `status=skipped`

Limitations:

- Fails on job reruns
- Skips with `reason=multiple` when multiple worktrees exist
- Difficult to debug

Acceptable use cases:

- Simple single-worktree workflows
- Testing and experimentation
- Workflows that never rerun

---

## How It Works

### Processing Flow

```bash
1. Get base branch (auto-detection only)
   ├─ Priority 1: inputs.base-branch
   ├─ Priority 2: GITHUB_BASE_REF
   ├─ Priority 3: git symbolic-ref (continues on failure)
   └─ Fallback: "main"

2. Get worktree path
   ├─ If inputs.worktree-dir provided: Use it
   └─ Otherwise: Auto-detect
      ├─ Search with git worktree list (exclude base branch)
      ├─ 0 found → reason=no-worktrees, skipped
      ├─ 1 found → Continue
      └─ 2+ found → reason=multiple, skipped

3. Validation (3 layers)
   ├─ Directory existence check
   │  └─ Not exist → reason=already-removed, skipped
   ├─ Git worktree registration check
   │  └─ Not registered → reason=not-registered, error
   ├─ .git marker check
   │  └─ Missing → reason=missing-marker, error
   ├─ Git work-tree validity check
   │  └─ Invalid → reason=invalid-worktree, error
   └─ Uncommitted changes check
      ├─ Found + force=false → reason=uncommitted, error
      └─ Found + force=true → Continue (reason=removed-dirty)

4. Execute removal
   ├─ git worktree remove [--force]
   ├─ Success → reason=removed or removed-dirty, success
   └─ Failure → reason=removal-failed, error
```

### Step Details

| Step                | Responsibility                         | Conditional Execution                    |
| ------------------- | -------------------------------------- | ---------------------------------------- |
| `get-base-branch`   | Determine base branch                  | `inputs.worktree-dir == ''`              |
| `get-worktree`      | Get or auto-detect worktree path       | Always                                   |
| `validate-worktree` | 3-layer validation + uncommitted check | `get-worktree.outcome == 'success'`      |
| `cleanup-worktree`  | Execute `git worktree remove`          | `validate-worktree.outcome == 'success'` |
| `output-results`    | Display final results                  | `always()`                               |

---

## Troubleshooting

### Common Errors and Reason Codes

#### reason=already-removed (skipped)

Situation: Directory doesn't exist

```bash
status=skipped
reason=already-removed
```

Causes:

- Cleanup ran multiple times
- Manually removed
- Worktree creation failed

Solution: Normal behavior (idempotency). Check logs to verify worktree creation succeeded.

#### reason=not-registered (error)

Situation: Directory exists but not registered as git worktree

```bash
::error::Path is not a registered git worktree
status=error
reason=not-registered
```

Causes:

- Directory not created with `git worktree add`
- Wrong path specified
- Worktree removed by other means, leaving remnants

Solution: Check with `git worktree list`. Specify correct path.

#### reason=uncommitted (error)

Situation: Uncommitted changes with force=false

```bash
::error::Cannot remove worktree with uncommitted changes (force=false)
::error::Changes found:
M  file.txt
status=error
reason=uncommitted
```

Causes:

- Work in progress not committed
- Files not added to git

Solution:

1. Commit and push changes
2. Or use `force: true` (results in `reason=removed-dirty`)

#### reason=multiple (skipped)

Situation: Multiple worktrees detected in auto-detection

```bash
::notice::Multiple worktrees found (3), skipping auto-detection
status=skipped
reason=multiple
```

Causes:

- Multiple worktrees exist besides base branch
- Auto-detection cannot decide

Solution: Specify `worktree-dir` explicitly (recommended pattern).

#### reason=invalid-worktree (error)

Situation: Not a valid git working tree

```bash
::error::Path is not a valid git working tree
status=error
reason=invalid-worktree
```

Causes:

- Worktree corruption
- `.git` file content invalid

Solution: Check with `git worktree list`. Use `git worktree prune` if needed.

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

Problem: Git or filesystem permission errors

Solution:

- Verify workflow has `contents: write` permission
- Check worktree not locked by another process
- Use runner temp directory (`${{ runner.temp }}`)

---

## Design Philosophy

### Why Strict Mode (force=false) as Default?

Reason: Safety first

- Prevent data loss: Protect uncommitted changes
- Explicit intent: User must explicitly choose `force: true`
- CI/CD alignment: Temporary worktrees should be clean

Usage:

- force=false (default): Production workflows, data protection
- force=true: CI/CD temporary environments, uncommitted changes acceptable

### Why Unified Reason Field?

Previous design (complex):

```yaml
outputs:
  removed: true/false
  was-dirty: true/false
  skip-reason: no-path/multiple/...
  # error-reason didn't exist
```

Problems:

- Must combine multiple fields
- Error reasons unclear
- Complex conditionals

New design (simple):

```yaml
outputs:
  reason: removed/removed-dirty/uncommitted/multiple/...
  # Single field covers all 12 patterns
```

Benefits:

1. Simple conditionals: `if: reason == 'removed-dirty'`
2. Complete coverage: All success/skipped/error have reasons
3. Self-documenting: Reason codes readable by humans and machines
4. Extensible: New reasons don't break existing logic

### Why Auto-detect is Fallback?

Auto-detect problems:

- Fails on job reruns (worktree already removed)
- Cannot decide with multiple worktrees
- Requires base branch checkout
- Difficult to debug

Design priorities:

1. Reliability > Convenience
2. Explicitness > Magic
3. Rerun safety > Automation

Recommendation: Always specify `worktree-dir` explicitly, passing initialization step output.

### Fail-fast vs Idempotent (CLAUDE.md Compliant)

This action follows [CLAUDE.md](../../../CLAUDE.md) fail-fast validation pattern.

#### What is Fail-fast?

Fail-fast (immediate failure): Strategy to immediately fail with `exit 1` when validation error detected.

Purpose:

- Early error detection
- Prevent continuation in problematic state
- Clear success/failure signals

CLAUDE.md principles:

```yaml
# REQUIRED: Fail-Fast Validation
if: steps.previous_step.outcome == 'success'

# Validation errors fail immediately with exit 1
if [ "$ERROR_CONDITION" ]; then
  echo "::error::Validation failed: reason"
  exit 1
fi
```

#### This Action's Implementation

| Scenario            | Behavior         | Exit Code | Reason                        |
| ------------------- | ---------------- | --------- | ----------------------------- |
| Validation error    | `status=error`   | 1         | Immediate failure (fail-fast) |
| Idempotent scenario | `status=skipped` | 0         | OK (idempotent)               |
| Successful removal  | `status=success` | 0         | Normal completion             |

Important design decisions:

- `status=error` + `exit 0` combination does not exist
- Validation errors always `exit 1` (fail-fast)
- Idempotent cases (already removed, etc.) `exit 0` (normal)

Exception: "Already removed" is `reason=already-removed, status=skipped, exit 0` (ensures idempotency)

---

## References

### Related Actions

- [PR Worktree Setup](../pr-worktree-setup/README.md) - Use as pair for worktree creation
- [Create PR from Worktree](../create-pr-from-worktree/README.md) - Commit and create PR in worktree

### Pairing Example

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
