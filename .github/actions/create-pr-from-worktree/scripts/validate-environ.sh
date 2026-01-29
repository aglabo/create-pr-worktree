#!/usr/bin/env bash
# src: ./.github/actions/create-pr-from-worktree/scripts/validate-environ.sh
# @(#) : Validate environment for create-pr-from-worktree action
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file validate-environ.sh
# @brief Validate OS and GitHub CLI environment for PR creation
# @description
#   Validates the execution environment for create-pr-from-worktree action:
#   - OS compatibility (Linux only)
#   - GitHub CLI (gh) installation and authentication
#   - GitHub API rate limit availability
#
#   **Required Environment Variables:**
#   - RUNNER_OS: OS identifier from GitHub Actions
#   - GH_TOKEN or GITHUB_TOKEN: GitHub authentication token
#
#   **Checks:**
#   1. Runner OS is Linux
#   2. gh command is installed
#   3. gh is authenticated with provided token
#   4. GitHub API rate limit has sufficient remaining calls (>10)
#
# @example
#   RUNNER_OS=Linux GH_TOKEN=${{ secrets.GITHUB_TOKEN }} ./validate-environ.sh
#
# @exitcode 0 Always exits with 0 (validation result is output to stdout)
#
# @output EXIT_STATUS=<status>:<message>
#   - ok: All validations passed
#   - error: Validation failed (see message for details)
#   - warning: Validation passed with warnings
#
# @author   atsushifx
# @version  1.0.0
# @license  MIT

set -uo pipefail
# Note: -e is removed to continue execution even on errors

# Validation status flags
VALIDATION_FAILED=0
FAILURE_MESSAGE=""
VALIDATION_WARNING=0
WARNING_MESSAGE=""

echo "=== Environment Validation for create-pr-from-worktree ==="
echo ""

# ============================================================================
# OS Validation
# ============================================================================
echo "Checking OS compatibility..."

if [[ "${RUNNER_OS}" != "Linux" ]]; then
  echo "::error::This action only supports Linux runners"
  echo "::error::Current OS: ${RUNNER_OS}"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="This action only supports Linux runners (current: ${RUNNER_OS})"
else
  echo "✓ OS validation passed (Linux)"
fi
echo ""

# ============================================================================
# GitHub CLI Installation Check
# ============================================================================
echo "Checking GitHub CLI installation..."

if ! command -v gh &> /dev/null; then
  echo "::error::GitHub CLI (gh) is not installed"
  echo "::error::Please ensure 'gh' is available in the runner environment"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="GitHub CLI (gh) is not installed"
else
  echo "✓ GitHub CLI (gh) is installed"
  gh --version | head -1
fi
echo ""

# ============================================================================
# GitHub CLI Authentication Check
# ============================================================================
echo "Checking GitHub CLI authentication..."

if ! gh auth status &> /dev/null; then
  echo "::error::GitHub CLI is not authenticated"
  echo "::error::Please set GH_TOKEN or GITHUB_TOKEN environment variable"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="GitHub CLI authentication failed"
else
  echo "✓ GitHub CLI is authenticated"
fi
echo ""

# ============================================================================
# GitHub API Rate Limit Check
# ============================================================================
echo "Checking GitHub API rate limit..."

if ! RATE_LIMIT_JSON=$(gh api rate_limit 2>&1); then
  echo "::error::Failed to check GitHub API rate limit"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="GitHub API rate limit check failed"
else
  REMAINING=$(echo "$RATE_LIMIT_JSON" | jq -r '.rate.remaining')
  LIMIT=$(echo "$RATE_LIMIT_JSON" | jq -r '.rate.limit')
  RESET_TIME=$(echo "$RATE_LIMIT_JSON" | jq -r '.rate.reset')

  echo "GitHub API rate limit: $REMAINING / $LIMIT remaining"

  # Warn if rate limit is low (less than 10 requests remaining)
  if [ "$REMAINING" -lt 10 ]; then
    RESET_DATE=$(date -d "@$RESET_TIME" 2>/dev/null || date -r "$RESET_TIME" 2>/dev/null || echo "unknown")
    echo "::warning::GitHub API rate limit is low: $REMAINING / $LIMIT remaining"
    echo "::warning::Rate limit resets at: $RESET_DATE"

    # Mark as failed if completely exhausted
    if [ "$REMAINING" -eq 0 ]; then
      echo "::error::GitHub API rate limit exhausted. Please wait for reset."
      VALIDATION_FAILED=1
      FAILURE_MESSAGE="GitHub API rate limit exhausted"
    else
      # Set warning status for low but non-zero rate limit
      VALIDATION_WARNING=1
      WARNING_MESSAGE="GitHub API rate limit low (${REMAINING}/${LIMIT} remaining)"
    fi
  else
    echo "✓ GitHub API rate limit check passed"
  fi
fi

echo ""

# ============================================================================
# Output Validation Result
# ============================================================================
if [ "$VALIDATION_FAILED" -eq 1 ]; then
  echo "EXIT_STATUS=error:${FAILURE_MESSAGE}"
  echo "=== Environment validation failed ==="
elif [ "${VALIDATION_WARNING:-0}" -eq 1 ]; then
  echo "EXIT_STATUS=warning:${WARNING_MESSAGE}"
  echo "=== Environment validated with warnings ==="
else
  echo "EXIT_STATUS=ok:Environment validated successfully"
  echo "=== All environment validations passed ==="
fi

exit 0
