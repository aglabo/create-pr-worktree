#!/usr/bin/env bash
# @file validate-branches.sh
# @brief Validate branch existence and configuration for PR creation
# @description
#   This script validates that both base and PR branches exist on the remote
#   repository and are different from each other. It is organized in three layers:
#   Data Fetching (pure functions), Validation Logic (pure functions), and
#   Main I/O (all input/output and exit handling).
#
#   **IMPORTANT PREREQUISITE:**
#   This script assumes that environment validation has been completed successfully
#   by a prior validation step (e.g., validate-environment action). The following
#   tools MUST be available:
#
#   - git: Git command-line tool
#
#   **Recommended Workflow:**
#   ```yaml
#   - name: Validate runner environment (REQUIRED FIRST)
#     uses: atsushifx/.github-aglabo/.github/actions/validate-environment@v1
#
#   - name: Validate branches (this script)
#     run: ./validate-branches.sh "$BASE_BRANCH" "$PR_BRANCH"
#   ```
#
# @arg $1 string Base branch name (target branch for PR)
# @arg $2 string PR branch name (branch with changes to be merged)
#
# @env GITHUB_OUTPUT Path to GitHub Actions output file (required)
#
# @exitcode 0 All validations passed
# @exitcode 1 Validation failed (branches missing, invalid arguments, or same branch)
#
# @stdout Validation progress messages and GitHub Actions annotations
#
# @see https://git-scm.com/docs/git-ls-remote
#
# @example
#   GITHUB_OUTPUT="${GITHUB_OUTPUT}" ./validate-branches.sh main feature-branch
#
# @note Branch validation logic:
#   - Both base and PR branches must exist on remote (origin)
#   - Branches must be different (prevents self-merging)
#   - Branch names are validated as-is (no normalization)
#
# @author atsushifx
# @version 2.1.1
# @license MIT
# @copyright Copyright (c) 2026- aglabo <https://github.com/aglabo>

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1

# ============================================================================
# LAYER 1: Data Fetching (Pure Functions)
# ============================================================================

# @description Check if a branch exists on remote repository.
#   This is a pure function that queries git to check branch existence.
#   It returns success/failure via exit code without side effects.
#
#   Uses exact matching with refs/heads/ prefix to avoid false positives
#   (e.g., "feature" matching "feature-x"). This approach is safe for
#   shallow clones and ensures reliable branch detection.
#
# @arg $1 string Branch name to check
#
# @exitcode 0 Branch exists on remote
# @exitcode 1 Branch does not exist on remote
#
# @example
#   if check_remote_branch_exists "main"; then
#     echo "Branch exists"
#   fi
#
# @note Implementation uses grep -Fxq for exact matching:
#   -F: Fixed string (no regex interpretation)
#   -x: Exact line match (prevents "feature" matching "feature-x")
#   -q: Quiet mode (exit code only)
check_remote_branch_exists() {
  local branch_name="$1"

  if git ls-remote --heads origin \
    | awk '{print $2}' \
    | grep -Fxq "refs/heads/$branch_name"; then
    return "$EXIT_SUCCESS"
  else
    return "$EXIT_ERROR"
  fi
}

# ============================================================================
# LAYER 2: Validation Logic (Pure Functions)
# ============================================================================

# @description Validate that base branch exists on remote.
#   This is a pure validation function that checks base branch existence.
#
# @arg $1 string Base branch name
#
# @exitcode 0 Base branch exists
# @exitcode 1 Base branch does not exist
#
# @example
#   if validate_base_branch_exists "main"; then
#     echo "Base branch is valid"
#   fi
validate_base_branch_exists() {
  local base_branch="$1"

  if check_remote_branch_exists "$base_branch"; then
    return "$EXIT_SUCCESS"
  else
    return "$EXIT_ERROR"
  fi
}

# @description Validate that PR branch exists on remote.
#   This is a pure validation function that checks PR branch existence.
#
# @arg $1 string PR branch name
#
# @exitcode 0 PR branch exists
# @exitcode 1 PR branch does not exist
#
# @example
#   if validate_pr_branch_exists "feature-branch"; then
#     echo "PR branch is valid"
#   fi
validate_pr_branch_exists() {
  local pr_branch="$1"

  if check_remote_branch_exists "$pr_branch"; then
    return "$EXIT_SUCCESS"
  else
    return "$EXIT_ERROR"
  fi
}

# @description Validate that base and PR branches are different.
#   This is a pure validation function that compares branch names.
#
# @arg $1 string Base branch name
# @arg $2 string PR branch name
#
# @exitcode 0 Branches are different
# @exitcode 1 Branches are the same
#
# @example
#   if validate_branches_different "main" "feature"; then
#     echo "Branches are different"
#   fi
validate_branches_different() {
  local base_branch="$1"
  local pr_branch="$2"

  if [ "$base_branch" = "$pr_branch" ]; then
    return "$EXIT_ERROR"
  else
    return "$EXIT_SUCCESS"
  fi
}

# ============================================================================
# Main: Validation & I/O (Modularized)
# ============================================================================

# @description Handle argument validation errors.
#   This function is called when required arguments are missing. It outputs
#   error messages, writes to GITHUB_OUTPUT, and exits with error code.
#
# @noargs
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
handle_argument_error() {
  local message

  echo "::error::Branch names not provided to validation script"
  echo "::error::Usage: validate-branches.sh <base-branch> <pr-branch>"
  message="Branch names not provided"

  # Write to GITHUB_OUTPUT
  {
    echo "status=fail"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=fail, message=${message}"
  echo ""
  echo "=== Branch validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Handle base branch validation errors.
#   This function is called when the base branch does not exist on remote.
#
# @arg $1 string Base branch name
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
handle_base_branch_error() {
  local base_branch="$1"
  local message

  echo "::error::Base branch '$base_branch' does not exist on remote"
  echo "::error::Please push the base branch first or check the branch name"
  message="Base branch '${base_branch}' does not exist on remote"

  # Write to GITHUB_OUTPUT
  {
    echo "status=fail"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=fail, message=${message}"
  echo ""
  echo "=== Branch validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Handle PR branch validation errors.
#   This function is called when the PR branch does not exist on remote.
#
# @arg $1 string PR branch name
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
handle_pr_branch_error() {
  local pr_branch="$1"
  local message

  echo "::error::PR branch '$pr_branch' does not exist on remote"
  echo "::error::Please push the PR branch first: git push origin $pr_branch"
  message="PR branch '${pr_branch}' does not exist on remote"

  # Write to GITHUB_OUTPUT
  {
    echo "status=fail"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=fail, message=${message}"
  echo ""
  echo "=== Branch validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Handle branch difference validation errors.
#   This function is called when base and PR branches are the same.
#
# @arg $1 string Branch name (same for both base and PR)
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
handle_branch_same_error() {
  local branch_name="$1"
  local message

  echo "::error::Base and PR branches cannot be the same: $branch_name"
  echo "::error::A pull request must be between different branches"
  message="Base and PR branches cannot be the same (${branch_name})"

  # Write to GITHUB_OUTPUT
  {
    echo "status=fail"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=fail, message=${message}"
  echo ""
  echo "=== Branch validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Output validation success and exit.
#   This function writes success status to GITHUB_OUTPUT and exits with
#   success code.
#
# @noargs
#
# @noreturn This function always exits with EXIT_SUCCESS
#
# @set GITHUB_OUTPUT Appends status and message
#
# @stdout Success messages
write_success_and_exit() {
  local message="Branch validation passed"

  # Write to GITHUB_OUTPUT
  {
    echo "status=ok"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=ok, message=${message}"
  echo ""
  echo "=== All branch validations passed ==="
  exit "$EXIT_SUCCESS"
}

# @description Main validation workflow (orchestration).
#   This function orchestrates the validation process by calling modularized
#   functions in sequence:
#   1. Validate arguments (or handle error)
#   2. Validate base branch existence (or handle error)
#   3. Validate PR branch existence (or handle error)
#   4. Validate branches are different (or handle error)
#   5. Write success and exit
#
#   This orchestration approach keeps the main function clean and readable,
#   with all complex logic delegated to specialized functions.
#
# @arg $1 string Base branch name
# @arg $2 string PR branch name
#
# @noreturn This function delegates to handler functions which always exit
#
# @set GITHUB_OUTPUT Appends status and message (via delegated functions)
#
# @stdout Validation progress, messages, and GitHub Actions annotations
#
# @example
#   main "$@"
main() {
  local base_branch="${1:-}"
  local pr_branch="${2:-}"

  echo "=== Branch Validation for create-pr-from-worktree ==="
  echo ""

  # ========================================
  # Argument Validation
  # ========================================

  if [ -z "$base_branch" ] || [ -z "$pr_branch" ]; then
    handle_argument_error
  fi

  echo "Base branch: $base_branch"
  echo "PR branch: $pr_branch"
  echo ""

  # ========================================
  # Base Branch Validation
  # ========================================

  echo "Checking base branch existence on remote..."

  if ! validate_base_branch_exists "$base_branch"; then
    handle_base_branch_error "$base_branch"
  fi

  echo "✓ Base branch '$base_branch' exists on remote"
  echo ""

  # ========================================
  # PR Branch Validation
  # ========================================

  echo "Checking PR branch existence on remote..."

  if ! validate_pr_branch_exists "$pr_branch"; then
    handle_pr_branch_error "$pr_branch"
  fi

  echo "✓ PR branch '$pr_branch' exists on remote"
  echo ""

  # ========================================
  # Branch Difference Validation
  # ========================================

  echo "Checking branch difference..."

  if ! validate_branches_different "$base_branch" "$pr_branch"; then
    handle_branch_same_error "$base_branch"
  fi

  echo "✓ Base and PR branches are different"
  echo ""

  # ========================================
  # Success
  # ========================================

  write_success_and_exit
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
