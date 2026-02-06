#!/usr/bin/env bash
# src: ./.github/actions/validate-environment/scripts/validate-git-runner.sh
# @(#) : Validate GitHub Actions runner environment
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file validate-git-runner.sh
# @brief Validate GitHub Actions runner environment comprehensively
# @description
#   Validates the execution environment for GitHub Actions workflows.
#   Ensures OS is Linux, architecture matches expectations (amd64|arm64),
#   and runner is GitHub-hosted with required environment variables.
#
#   **Checks:**
#   1. Operating System is Linux
#   2. Expected architecture input is valid (amd64 or arm64)
#   3. Detected architecture matches expected architecture
#   4. GitHub Actions environment (GITHUB_ACTIONS=true)
#   5. GitHub-hosted runner (RUNNER_ENVIRONMENT=github-hosted)
#   6. Required runtime variables (RUNNER_TEMP, GITHUB_OUTPUT, GITHUB_PATH)
#
# @exitcode 0 GitHub runner validation successful
# @exitcode 1 GitHub runner validation failed
#
# @author   atsushifx
# @version  1.2.0
# @license  MIT

set -euo pipefail

# Safe output file handling - fallback to /dev/null if not in GitHub Actions
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

# Global variables for validation results
EXPECTED_ARCH="${EXPECTED_ARCHITECTURE:-amd64}"
NORMALIZED_ARCH=""
DETECTED_OS=""
DETECTED_ARCH=""

# ============================================================================
# Helper Functions
# ============================================================================

# @description Normalize architecture to canonical form
# @arg $1 string Raw architecture name (e.g., "x86_64", "aarch64")
# @exitcode 0 Valid architecture, NORMALIZED_ARCH set to amd64 or arm64
# @exitcode 1 Unsupported architecture
# @set NORMALIZED_ARCH Canonical architecture (amd64|arm64)
normalize_architecture() {
  local raw_arch="$1"

  case "${raw_arch}" in
    x86_64|amd64|x64)
      NORMALIZED_ARCH="amd64"
      return 0
      ;;
    aarch64|arm64)
      NORMALIZED_ARCH="arm64"
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# @description Check environment variable existence and value
# @arg $1 string Variable name to check
# @arg $2 string Expected value (optional, checks existence only if omitted)
# @exitcode 0 Variable exists and matches expected value (if provided)
# @exitcode 1 Variable not set or value mismatch
check_env_var() {
  local var_name="$1"
  local expected_value="${2:-}"
  local var_value="${!var_name:-}"

  # Check if variable is set
  [ -n "$var_value" ] || return 1

  # If expected value provided, check if it matches
  [ -z "$expected_value" ] || [ "$var_value" = "$expected_value" ] || return 1

  return 0
}

# ============================================================================
# Validation Functions
# ============================================================================

# @description Validate operating system is Linux
# @exitcode 0 Operating system is Linux
# @exitcode 1 Operating system is not Linux
# @set DETECTED_OS Normalized OS name (lowercase)
validate_os() {
  DETECTED_OS=$(uname -s | tr '[:upper:]' '[:lower:]')

  if [ "${DETECTED_OS}" != "linux" ]; then
    return 1
  fi

  return 0
}

# @description Validate expected architecture input
# @exitcode 0 EXPECTED_ARCH is valid (amd64 or arm64)
# @exitcode 1 EXPECTED_ARCH is invalid
validate_expected_arch() {
  case "${EXPECTED_ARCH}" in
    amd64|arm64)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# @description Detect and normalize architecture
# @exitcode 0 Architecture detected and normalized successfully
# @exitcode 1 Unsupported architecture detected
# @set DETECTED_ARCH Raw architecture from uname -m
# @set NORMALIZED_ARCH Canonical architecture (amd64|arm64)
validate_detected_arch() {
  DETECTED_ARCH=$(uname -m)

  if ! normalize_architecture "${DETECTED_ARCH}"; then
    return 1
  fi

  return 0
}

# @description Validate architecture matches expected value
# @exitcode 0 EXPECTED_ARCH matches NORMALIZED_ARCH
# @exitcode 1 Architecture mismatch
validate_arch_match() {
  if [ "${EXPECTED_ARCH}" != "${NORMALIZED_ARCH}" ]; then
    return 1
  fi

  return 0
}

# @description Validate GitHub Actions environment
# @exitcode 0 GITHUB_ACTIONS environment variable is set to 'true'
# @exitcode 1 Not running in GitHub Actions environment
validate_github_actions_env() {
  if ! check_env_var "GITHUB_ACTIONS" "true"; then
    return 1
  fi

  return 0
}

# @description Validate GitHub-hosted runner
# @exitcode 0 RUNNER_ENVIRONMENT is set to 'github-hosted'
# @exitcode 1 Self-hosted runner or RUNNER_ENVIRONMENT not set correctly
validate_github_hosted_runner() {
  if ! check_env_var "RUNNER_ENVIRONMENT" "github-hosted"; then
    return 1
  fi

  return 0
}

# @description Validate required runtime variables
# @exitcode 0 All required variables (RUNNER_TEMP, GITHUB_OUTPUT, GITHUB_PATH) are set
# @exitcode 1 One or more required variables are missing
validate_runtime_variables() {
  for var in RUNNER_TEMP GITHUB_OUTPUT GITHUB_PATH; do
    if ! check_env_var "$var"; then
      return 1
    fi
  done

  return 0
}

# ============================================================================
# Main Orchestrator Function
# ============================================================================

# @description Main validation orchestrator
# @exitcode 0 All validations passed
# @exitcode 1 One or more validations failed
# @stdout Validation progress messages
# @stderr Error messages with ::error:: prefix
# @set GITHUB_OUTPUT Writes status=success|error and message=<details>
validate_git_runner() {
  echo "=== Validating GitHub Runner Environment ==="
  echo ""

  # Validate OS
  if ! validate_os; then
    echo "::error::Unsupported operating system: ${DETECTED_OS}" >&2
    echo "::error::This action requires Linux" >&2
    echo "::error::Please use a Linux runner (e.g., ubuntu-latest)" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Unsupported OS: ${DETECTED_OS} (Linux required)" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "Operating System: ${DETECTED_OS}"
  echo "✓ Operating system validated: Linux"
  echo ""

  # Validate expected architecture input
  if ! validate_expected_arch; then
    echo "::error::Invalid architecture input: ${EXPECTED_ARCH}" >&2
    echo "::error::Supported values: amd64, arm64" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Invalid architecture input: ${EXPECTED_ARCH}" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "Expected architecture: ${EXPECTED_ARCH}"

  # Detect and normalize architecture
  if ! validate_detected_arch; then
    echo "::error::Unsupported architecture: ${DETECTED_ARCH}" >&2
    echo "::error::Supported architectures: amd64 (x86_64), arm64 (aarch64)" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Unsupported architecture: ${DETECTED_ARCH}" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "Detected architecture: ${DETECTED_ARCH}"

  # Validate architecture match
  if ! validate_arch_match; then
    echo "::error::Architecture mismatch" >&2
    echo "::error::Expected: ${EXPECTED_ARCH}" >&2
    echo "::error::Detected: ${NORMALIZED_ARCH} (${DETECTED_ARCH})" >&2
    echo "::error::Please use a runner with ${EXPECTED_ARCH} architecture" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Architecture mismatch: expected ${EXPECTED_ARCH}, got ${NORMALIZED_ARCH}" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ Architecture validated: ${NORMALIZED_ARCH}"
  echo ""

  # Check GitHub Actions environment
  echo "Checking GitHub Actions environment..."

  if ! validate_github_actions_env; then
    echo "::error::Not running in GitHub Actions environment" >&2
    echo "::error::This action must run in a GitHub Actions workflow" >&2
    echo "::error::GITHUB_ACTIONS environment variable is not set to 'true'" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Not running in GitHub Actions environment" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ GITHUB_ACTIONS is set to 'true'"

  if ! validate_github_hosted_runner; then
    echo "::error::This action requires a GitHub-hosted runner" >&2
    echo "::error::Self-hosted runners are not supported" >&2
    echo "::error::RUNNER_ENVIRONMENT is not set to 'github-hosted' (current: ${RUNNER_ENVIRONMENT:-unset})" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Requires GitHub-hosted runner (not self-hosted)" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ RUNNER_ENVIRONMENT is 'github-hosted'"

  if ! validate_runtime_variables; then
    echo "::error::Required environment variables are not set" >&2
    echo "::error::This action must run in a GitHub Actions environment" >&2
    echo "status=error" >> "$GITHUB_OUTPUT_FILE"
    echo "message=Missing required environment variables" >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ RUNNER_TEMP is set"
  echo "✓ GITHUB_OUTPUT is set"
  echo "✓ GITHUB_PATH is set"
  echo ""

  echo "=== GitHub runner validation passed ==="
  echo "status=success" >> "$GITHUB_OUTPUT_FILE"
  echo "message=GitHub runner validated: Linux ${NORMALIZED_ARCH}, github-hosted" >> "$GITHUB_OUTPUT_FILE"
  exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

validate_git_runner
