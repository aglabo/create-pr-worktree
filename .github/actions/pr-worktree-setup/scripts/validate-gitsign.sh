#!/usr/bin/env bash
# src: ./.github/actions/pr-worktree-initialize/scripts/validate-gitsign.sh
# @(#) : Validate gitsign installation and OIDC environment
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file validate-gitsign.sh
# @brief Validate gitsign installation and GitHub Actions OIDC environment
# @description
#   Validates the environment for gitsign keyless signing:
#   - gitsign binary is installed and accessible
#   - gitsign binary is executable
#   - OIDC environment variables are available
#   - gitsign version command works
#
#   **Required Environment Variables:**
#   - ACTIONS_ID_TOKEN_REQUEST_TOKEN: GitHub Actions OIDC token request token
#   - ACTIONS_ID_TOKEN_REQUEST_URL: GitHub Actions OIDC token request URL
#
#   **Checks:**
#   1. gitsign command is in PATH
#   2. gitsign binary is executable
#   3. OIDC environment variables are set
#   4. gitsign version command succeeds
#
# @example
#   ./validate-gitsign.sh
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

echo "=== Gitsign Environment Validation ==="
echo ""

# ============================================================================
# Gitsign Binary Installation Check
# ============================================================================
echo "Checking gitsign installation..."

if ! command -v gitsign &> /dev/null; then
  echo "::error::gitsign is not installed or not in PATH"
  echo "::error::Please ensure gitsign binary is installed and accessible"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="gitsign is not installed or not in PATH"
else
  echo "✓ gitsign is installed"
  GITSIGN_PATH=$(command -v gitsign)
  echo "  Location: ${GITSIGN_PATH}"
fi
echo ""

# ============================================================================
# Gitsign Executable Check
# ============================================================================
if [ "$VALIDATION_FAILED" -eq 0 ]; then
  echo "Checking gitsign executable permissions..."

  if [ ! -x "$(command -v gitsign)" ]; then
    echo "::error::gitsign binary is not executable"
    VALIDATION_FAILED=1
    FAILURE_MESSAGE="gitsign binary is not executable"
  else
    echo "✓ gitsign is executable"
  fi
  echo ""
fi

# ============================================================================
# OIDC Environment Variables Check
# ============================================================================
echo "Checking GitHub Actions OIDC environment..."

OIDC_VARS_OK=1

# Check ACTIONS_ID_TOKEN_REQUEST_TOKEN
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:-}" ]; then
  echo "::error::ACTIONS_ID_TOKEN_REQUEST_TOKEN is not set"
  echo "::error::Please ensure 'id-token: write' permission is granted in workflow"
  OIDC_VARS_OK=0
else
  echo "✓ ACTIONS_ID_TOKEN_REQUEST_TOKEN is set"
fi

# Check ACTIONS_ID_TOKEN_REQUEST_URL
if [ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]; then
  echo "::error::ACTIONS_ID_TOKEN_REQUEST_URL is not set"
  echo "::error::Please ensure 'id-token: write' permission is granted in workflow"
  OIDC_VARS_OK=0
else
  echo "✓ ACTIONS_ID_TOKEN_REQUEST_URL is set"
fi

if [ "$OIDC_VARS_OK" -eq 0 ]; then
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="GitHub Actions OIDC environment variables are not set (missing id-token: write permission?)"
else
  echo "✓ OIDC environment validated"
fi
echo ""

# ============================================================================
# Gitsign Version Check
# ============================================================================
if [ "$VALIDATION_FAILED" -eq 0 ]; then
  echo "Checking gitsign version..."

  if ! GITSIGN_VERSION=$(gitsign version 2>&1); then
    echo "::error::Failed to execute 'gitsign version'"
    echo "::error::gitsign may not be properly installed"
    VALIDATION_FAILED=1
    FAILURE_MESSAGE="Failed to execute 'gitsign version'"
  else
    echo "✓ gitsign version check passed"
    echo "${GITSIGN_VERSION}" | head -3
  fi
  echo ""
fi

# ============================================================================
# Output Validation Result
# ============================================================================
if [ "$VALIDATION_FAILED" -eq 1 ]; then
  echo "EXIT_STATUS=error:${FAILURE_MESSAGE}"
  echo "=== Gitsign environment validation failed ==="
elif [ "${VALIDATION_WARNING:-0}" -eq 1 ]; then
  echo "EXIT_STATUS=warning:${WARNING_MESSAGE}"
  echo "=== Gitsign environment validated with warnings ==="
else
  echo "EXIT_STATUS=ok:Gitsign environment validated successfully"
  echo "=== All gitsign validations passed ==="
fi

exit 0
