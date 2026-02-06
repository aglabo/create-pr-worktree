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
#   - gitsign-path output contract (binary path is set and valid)
#   - gitsign binary exists at the specified path
#   - gitsign binary is executable
#   - OIDC environment variables are available
#   - gitsign version command works
#
#   **Required Arguments:**
#   - $1: gitsign-path (absolute path to gitsign binary from install-gitsign step)
#
#   **Required Environment Variables:**
#   - ACTIONS_ID_TOKEN_REQUEST_TOKEN: GitHub Actions OIDC token request token
#   - ACTIONS_ID_TOKEN_REQUEST_URL: GitHub Actions OIDC token request URL
#
#   **Checks:**
#   1. gitsign-path output is not empty (contract validation)
#   2. gitsign binary exists at the specified path
#   3. gitsign binary is executable
#   4. OIDC environment variables are set
#   5. gitsign version command succeeds
#
# @example
#   ./validate-gitsign.sh "/path/to/gitsign"
#
# @exitcode 1 Validation failed (fail-fast pattern)
# @exitcode 0 Validation succeeded
#
# @output status=success|error to $GITHUB_OUTPUT
# @output message=<details> to $GITHUB_OUTPUT
#
# @author   atsushifx
# @version  2.0.0
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
# Argument Validation (Output Contract Check)
# ============================================================================
GITSIGN_PATH="${1:-}"

echo "Validating gitsign-path output contract..."

if [ -z "${GITSIGN_PATH}" ]; then
  echo "::error::Contract violation: gitsign-path output is empty"
  echo "::error::This indicates a bug in install-gitsign.sh script"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Contract violation: gitsign-path output is empty" >> $GITHUB_OUTPUT
  exit 1
fi

echo "✓ gitsign-path output is set: ${GITSIGN_PATH}"
echo ""

# ============================================================================
# Gitsign Binary Existence Check
# ============================================================================
echo "Checking gitsign binary existence..."

if [ ! -f "${GITSIGN_PATH}" ]; then
  echo "::error::Contract violation: gitsign binary not found at: ${GITSIGN_PATH}"
  echo "::error::This indicates install-gitsign.sh reported incorrect path"
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=Contract violation: gitsign binary not found at ${GITSIGN_PATH}" >> $GITHUB_OUTPUT
  exit 1
fi

echo "✓ gitsign binary exists at: ${GITSIGN_PATH}"
echo ""

# ============================================================================
# Gitsign Executable Check
# ============================================================================
echo "Checking gitsign executable permissions..."

if [ ! -x "${GITSIGN_PATH}" ]; then
  echo "::error::gitsign binary is not executable: ${GITSIGN_PATH}"
  VALIDATION_FAILED=1
  FAILURE_MESSAGE="gitsign binary is not executable"
else
  echo "✓ gitsign is executable"
fi
echo ""

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

  if ! GITSIGN_VERSION=$("${GITSIGN_PATH}" version 2>&1); then
    echo "::error::Failed to execute '${GITSIGN_PATH} version'"
    echo "::error::gitsign may not be properly installed or configured"
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
  echo "status=error" >> $GITHUB_OUTPUT
  echo "message=${FAILURE_MESSAGE}" >> $GITHUB_OUTPUT
  echo "=== Gitsign environment validation failed ==="
  exit 1
elif [ "${VALIDATION_WARNING:-0}" -eq 1 ]; then
  echo "status=warning" >> $GITHUB_OUTPUT
  echo "message=${WARNING_MESSAGE}" >> $GITHUB_OUTPUT
  echo "=== Gitsign environment validated with warnings ==="
  exit 0
else
  echo "status=success" >> $GITHUB_OUTPUT
  echo "message=Gitsign environment validated successfully" >> $GITHUB_OUTPUT
  echo "=== All gitsign validations passed ==="
  exit 0
fi
