#!/usr/bin/env bash
# src: ./.github/actions/create-pr-from-worktree/scripts/validate-branches.sh
# @(#) : Validate branch existence for create-pr-from-worktree action
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file validate-branches.sh
# @brief Validate branch existence on remote repository
# @description
#   Validates that both base and PR branches exist on the remote repository
#   and are different from each other. This script should be called after
#   validate-environ.sh to ensure branches are ready for PR creation.
#
#   **Required Arguments:**
#   - $1: Base branch name (target branch for PR)
#   - $2: PR branch name (branch with changes to be merged)
#
#   **Checks:**
#   1. Base branch exists on remote repository
#   2. PR branch exists on remote repository
#   3. Base and PR branches are different
#
# @example
#   ./validate-branches.sh main feature-branch
#
# @exitcode 0 Always exits with 0 (validation result is output to stdout)
#
# @output EXIT_STATUS=<status>:<message>
#   - ok: All validations passed
#   - fail: Validation failed (see message for details)
#
# @author   atsushifx
# @version  1.0.0
# @license  MIT

set -uo pipefail
# Note: -e is removed to continue execution even on errors

# Validation status flags
VALIDATION_FAILED=0
FAILURE_MESSAGE=""

echo "=== Branch Validation for create-pr-from-worktree ==="
echo ""

# ============================================================================
# Argument Validation
# ============================================================================
BASE_BRANCH="${1:-}"
PR_BRANCH="${2:-}"

# Validate arguments provided
if [ -z "$BASE_BRANCH" ] || [ -z "$PR_BRANCH" ]; then
  echo "::error::Branch names not provided to validation script"
  echo "::error::Usage: validate-branches.sh <base-branch> <pr-branch>"
  echo "EXIT_STATUS=fail:Branch names not provided"
  exit 0
fi

echo "Base branch: $BASE_BRANCH"
echo "PR branch: $PR_BRANCH"
echo ""

# ============================================================================
# Base Branch Validation
# ============================================================================
echo "Checking base branch existence on remote..."

if ! git ls-remote --heads origin "$BASE_BRANCH" | grep -q "$BASE_BRANCH"; then
  echo "::error::Base branch '$BASE_BRANCH' does not exist on remote"
  echo "::error::Please push the base branch first or check the branch name"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="Base branch '${BASE_BRANCH}' does not exist on remote"
else
  echo "✓ Base branch '$BASE_BRANCH' exists on remote"
fi
echo ""

# ============================================================================
# PR Branch Validation
# ============================================================================
echo "Checking PR branch existence on remote..."

if ! git ls-remote --heads origin "$PR_BRANCH" | grep -q "$PR_BRANCH"; then
  echo "::error::PR branch '$PR_BRANCH' does not exist on remote"
  echo "::error::Please push the PR branch first: git push origin $PR_BRANCH"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="PR branch '${PR_BRANCH}' does not exist on remote"
else
  echo "✓ PR branch '$PR_BRANCH' exists on remote"
fi
echo ""

# ============================================================================
# Branch Difference Validation
# ============================================================================
echo "Checking branch difference..."

if [ "$BASE_BRANCH" = "$PR_BRANCH" ]; then
  echo "::error::Base and PR branches cannot be the same: $BASE_BRANCH"
  echo "::error::A pull request must be between different branches"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="Base and PR branches cannot be the same (${BASE_BRANCH})"
else
  echo "✓ Base and PR branches are different"
fi

echo ""

# ============================================================================
# Output Validation Result
# ============================================================================
if [ "$VALIDATION_FAILED" -eq 1 ]; then
  echo "EXIT_STATUS=fail:${FAILURE_MESSAGE}"
  echo "=== Branch validation failed ==="
else
  echo "EXIT_STATUS=ok:Branch validation passed"
  echo "=== All branch validations passed ==="
fi

exit 0
