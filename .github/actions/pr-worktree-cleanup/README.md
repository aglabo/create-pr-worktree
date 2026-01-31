# PR Worktree Cleanup

<!-- textlint-disable ja-technical-writing/sentence-length -->
<!-- markdownlint-disable line-length -->

Composite action to safely remove a git worktree created by pr-worktree-initialize.

## Overview

This action provides safe and idempotent cleanup of git worktrees. It pairs with the `pr-worktree-initialize` action to provide complete worktree lifecycle management.

**Key Features:**

- Validates worktree exists before attempting removal
- Verifies directory is actually a git worktree
- Idempotent behavior (safe to run multiple times)
- Graceful handling of already-removed worktrees
- Detailed status reporting for cleanup operations
- Designed to work with `if: always()` for guaranteed cleanup

## Prerequisites

**Minimal Requirements:**

- Git 2.30+
- Worktree must be managed by git (created with `git worktree add`)

**Recommended Usage:**

Use with `pr-worktree-initialize` action for complete workflow:

```yaml
- name: Initialize worktree
  id: init-worktree
  uses: ./.github/actions/pr-worktree-initialize
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

| Input          | Required | Default | Description                                                 |
| -------------- | -------- | ------- | ----------------------------------------------------------- |
| `worktree-dir` | Yes      | -       | Directory path of the worktree to remove                    |
| `force`        | No       | `true`  | Force removal even if worktree has uncommitted changes      |

## Outputs

| Output           | Description                                    |
| ---------------- | ---------------------------------------------- |
| `cleanup-status` | Status of cleanup operation (success, warning, error) |
| `removed-path`   | Path of the removed worktree                   |

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

### Integration with pr-worktree-initialize

```yaml
name: Create Signed PR

permissions:
  id-token: write
  contents: write
  pull-requests: write

jobs:
  create-pr:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Initialize worktree with gitsign
        id: init-worktree
        uses: ./.github/actions/pr-worktree-initialize
        with:
          branch-name: feature/my-feature
          worktree-dir: ${{ runner.temp }}/pr-worktree

      - name: Make changes
        run: |
          cd ${{ steps.init-worktree.outputs.worktree-path }}
          echo "# New Feature" > feature.md
          git add feature.md
          git commit -m "feat: add new feature"
          git push origin feature/my-feature

      - name: Create PR
        run: |
          gh pr create --title "Add new feature" --body "..."

      - name: Cleanup worktree
        if: always()
        uses: ./.github/actions/pr-worktree-cleanup
        with:
          worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

### Safe Removal (No Force)

```yaml
- name: Cleanup worktree safely
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree
    force: false
```

With `force: false`, removal will fail if the worktree has uncommitted changes. This is useful when you want to ensure no work is lost.

### Handling Cleanup Status

```yaml
- name: Cleanup worktree
  id: cleanup
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ runner.temp }}/worktree

- name: Check cleanup status
  if: always()
  run: |
    echo "Cleanup status: ${{ steps.cleanup.outputs.cleanup-status }}"
    if [ "${{ steps.cleanup.outputs.cleanup-status }}" = "error" ]; then
      echo "::warning::Worktree cleanup failed, may need manual cleanup"
    fi
```

## How It Works

1. **Validate Inputs**: Checks that `worktree-dir` is provided
2. **Check Directory Exists**: Verifies worktree directory exists
   - If not found: Returns `warning` status (idempotent behavior)
3. **Validate Worktree**: Confirms directory is a valid git worktree
   - Checks for `.git` file (worktree marker)
4. **Remove Worktree**: Executes `git worktree remove` with appropriate flags
   - Uses `--force` flag if `force: true` (default)
5. **Verify Removal**: Confirms directory was removed
6. **Output Status**: Returns status (success, warning, or error)

## Status Meanings

| Status    | Description                                      | Exit Code |
| --------- | ------------------------------------------------ | --------- |
| `success` | Worktree removed successfully                    | 0         |
| `warning` | Worktree doesn't exist (already cleaned)         | 0         |
| `error`   | Removal failed (e.g., not a worktree, git error) | 1         |

The action is designed to be idempotent - running it multiple times on the same worktree is safe. If the worktree is already removed, it returns a `warning` status but doesn't fail.

## Error Handling

### Worktree Already Removed

**Behavior**: Returns `warning` status, doesn't fail

```
EXIT_STATUS=warning:Worktree directory does not exist (already cleaned)
```

This is normal and expected if cleanup runs multiple times or if the worktree was manually removed.

### Directory Exists But Not a Worktree

**Behavior**: Returns `error` status and fails

```
EXIT_STATUS=error:Directory is not a valid git worktree
```

**Solution**: Ensure the path points to a directory created with `git worktree add`.

### Git Worktree Remove Failed

**Behavior**: Returns `error` status and fails

**Common Causes**:

- Worktree has uncommitted changes (when `force: false`)
- Worktree is locked by another process
- Permission issues

**Solution**: Check git error message in logs, consider using `force: true`, or manually investigate.

## Troubleshooting

### Cleanup Always Shows Warning

**Cause**: Worktree directory doesn't exist when cleanup runs

**Possible Reasons**:

- Cleanup is running multiple times
- Worktree was never created successfully
- Worktree was removed manually or by another step

**Solution**: Check workflow logs to verify worktree creation succeeded. If using output from `pr-worktree-initialize`, ensure the step ID matches.

### Cleanup Fails with "Not a Valid Git Worktree"

**Cause**: The directory exists but wasn't created with `git worktree add`

**Solution**: Ensure you're passing the correct path from `pr-worktree-initialize`. Don't pass arbitrary directories.

### Permission Denied

**Cause**: Git or filesystem permission issues

**Solution**: Ensure the workflow has appropriate permissions and the worktree isn't locked by another process.

## Design Decisions

### Why Default force: true?

The default `force: true` matches the common pattern of using `git worktree remove --force` in cleanup steps. This ensures cleanup succeeds even if uncommitted changes exist, which is typically desired in CI/CD environments where the worktree is temporary.

For workflows where preserving uncommitted changes matters, explicitly set `force: false`.

### Why Warning Instead of Error for Missing Worktree?

Returning a `warning` status instead of `error` when the worktree doesn't exist makes the action idempotent. This is useful when:

- Cleanup runs in `if: always()` blocks that may execute multiple times
- Another step already removed the worktree
- Worktree creation failed but cleanup still runs

This design prevents false-positive failures in CI/CD pipelines.

### Why Validate It's a Git Worktree?

The validation prevents accidentally running `git worktree remove` on arbitrary directories, which could cause unexpected behavior. By checking for the `.git` file (worktree marker), we ensure the action only operates on legitimate git worktrees.

## Pairing with pr-worktree-initialize

This action is designed to pair with `pr-worktree-initialize`:

```yaml
# Initialize
- name: Initialize worktree
  id: init-worktree
  uses: ./.github/actions/pr-worktree-initialize
  with:
    branch-name: feature/my-branch
    worktree-dir: ${{ runner.temp }}/worktree

# ... do work ...

# Cleanup (always runs)
- name: Cleanup worktree
  if: always()
  uses: ./.github/actions/pr-worktree-cleanup
  with:
    worktree-dir: ${{ steps.init-worktree.outputs.worktree-path }}
```

**Key Points**:

- Use `worktree-path` output from initialization (absolute path)
- Always use `if: always()` to ensure cleanup runs
- Place cleanup step at the end of the job

## Security Considerations

**Safe Defaults:**

- Only removes git worktrees (validates `.git` file exists)
- Won't remove arbitrary directories
- Fails gracefully with informative errors

**Force Flag:**

- `force: true` removes worktree even with uncommitted changes
- `force: false` preserves uncommitted changes and fails if they exist
- Choose based on your workflow requirements

## License

MIT License - See repository LICENSE file

## References

- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree)
- [PR Worktree Initialize Action](../pr-worktree-initialize/README.md)
- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
