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
# @version  1.2.2
# @license  MIT

set -euo pipefail

# Safe output file handling - fallback to /dev/null if not in GitHub Actions
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

echo "=== Validating GitHub Runner Environment ==="
echo ""

  # Validate OS
  if ! validate_os; then
    echo "::error::Unsupported operating system: ${DETECTED_OS}" >&2
    echo "::error::This action requires Linux" >&2
    echo "::error::Please use a Linux runner (e.g., ubuntu-latest)" >&2
    {
      echo "status=error"
      echo "message=Unsupported OS: ${DETECTED_OS} (Linux required)"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

echo "✓ Operating system validated: Linux"
echo ""

  # Validate expected architecture input
  if ! validate_expected_arch; then
    echo "::error::Invalid architecture input: ${EXPECTED_ARCH}" >&2
    echo "::error::Supported values: amd64, arm64" >&2
    {
      echo "status=error"
      echo "message=Invalid architecture input: ${EXPECTED_ARCH}"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "Expected architecture: ${EXPECTED_ARCH}"

  # Detect and normalize architecture
  if ! validate_detected_arch; then
    echo "::error::Unsupported architecture: ${DETECTED_ARCH}" >&2
    echo "::error::Supported architectures: amd64 (x86_64), arm64 (aarch64)" >&2
    {
      echo "status=error"
      echo "message=Unsupported architecture: ${DETECTED_ARCH}"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "Detected architecture: ${DETECTED_ARCH}"

  # Validate architecture match
  if ! validate_arch_match; then
    echo "::error::Architecture mismatch" >&2
    echo "::error::Expected: ${EXPECTED_ARCH}" >&2
    echo "::error::Detected: ${NORMALIZED_ARCH} (${DETECTED_ARCH})" >&2
    echo "::error::Please use a runner with ${EXPECTED_ARCH} architecture" >&2
    {
      echo "status=error"
      echo "message=Architecture mismatch: expected ${EXPECTED_ARCH}, got ${NORMALIZED_ARCH}"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

echo "✓ Architecture validated: ${NORMALIZED_ARCH}"
echo ""

# Check GitHub Actions environment variables
echo "Checking GitHub Actions environment..."

  if ! validate_github_actions_env; then
    echo "::error::Not running in GitHub Actions environment" >&2
    echo "::error::This action must run in a GitHub Actions workflow" >&2
    echo "::error::GITHUB_ACTIONS environment variable is not set to 'true'" >&2
    {
      echo "status=error"
      echo "message=Not running in GitHub Actions environment"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ GITHUB_ACTIONS is set to 'true'"

  if ! validate_github_hosted_runner; then
    echo "::error::This action requires a GitHub-hosted runner" >&2
    echo "::error::Self-hosted runners are not supported" >&2
    echo "::error::RUNNER_ENVIRONMENT is not set to 'github-hosted' (current: ${RUNNER_ENVIRONMENT:-unset})" >&2
    {
      echo "status=error"
      echo "message=Requires GitHub-hosted runner (not self-hosted)"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ RUNNER_ENVIRONMENT is 'github-hosted'"

  if ! validate_runtime_variables; then
    echo "::error::Required environment variables are not set" >&2
    echo "::error::This action must run in a GitHub Actions environment" >&2
    {
      echo "status=error"
      echo "message=Missing required environment variables"
    } >> "$GITHUB_OUTPUT_FILE"
    exit 1
  fi

  echo "✓ RUNNER_TEMP is set"
  echo "✓ GITHUB_OUTPUT is set"
  echo "✓ GITHUB_PATH is set"
  echo ""

  echo "=== GitHub runner validation passed ==="
  {
    echo "status=success"
    echo "message=GitHub runner validated: Linux ${NORMALIZED_ARCH}, github-hosted"
  } >> "$GITHUB_OUTPUT_FILE"
  exit 0
}

# ============================================================================
# Script Entry Point
# ============================================================================

validate_git_runner
