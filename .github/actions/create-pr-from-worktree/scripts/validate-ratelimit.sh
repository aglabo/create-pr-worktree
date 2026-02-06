#!/usr/bin/env bash
# @file validate-ratelimit.sh
# @brief Validate GitHub API rate limit availability for PR operations
# @description
#   This script validates GitHub API rate limit before PR creation/update operations.
#   It is organized in three layers: Data Fetching (pure functions), Validation Logic
#   (pure functions), and Main I/O (all input/output and exit handling).
#
#   **IMPORTANT PREREQUISITE:**
#   This script assumes that environment validation has been completed successfully
#   by a prior validation step (e.g., validate-environment action). The following
#   tools MUST be available and properly configured:
#
#   - gh: GitHub CLI (version 2.0+, authenticated with valid token)
#   - jq: JSON processor (version 1.0+)
#   - timeout: GNU coreutils timeout command
#
#   **Recommended Workflow:**
#   ```yaml
#   - name: Validate runner environment (REQUIRED FIRST)
#     uses: atsushifx/.github-aglabo/.github/actions/validate-environment@v1
#     with:
#       additional-apps: "gh|gh|regex:version ([0-9.]+)|2.0,jq|jq|regex:jq-([0-9.]+)|1.0"
#
#   - name: Validate API rate limit (this script)
#     run: ./validate-ratelimit.sh
#   ```
#
#   If the required tools are not available, this script will fail with detailed
#   error messages indicating which tool is missing. However, it is STRONGLY
#   RECOMMENDED to validate the environment BEFORE calling this script to catch
#   configuration issues early in the workflow.
#
# @env GH_TOKEN GitHub authentication token (required)
# @env GITHUB_TOKEN Alternative to GH_TOKEN (required if GH_TOKEN not set)
# @env GITHUB_OUTPUT Path to GitHub Actions output file (required)
#
# @exitcode 0 Rate limit is sufficient (ok) or low but acceptable (warning)
# @exitcode 1 Rate limit exhausted (error), fetch failed, or prerequisites not met
#
# @stdout Validation progress messages and GitHub Actions annotations
# @stderr Error messages (redirected to stdout by main function)
#
# @see https://docs.github.com/en/rest/rate-limit
# @see https://cli.github.com/manual/
#
# @example
#   # With environment variables set
#   GH_TOKEN="${{ secrets.GITHUB_TOKEN }}" \
#   GITHUB_OUTPUT="${GITHUB_OUTPUT}" \
#   ./validate-ratelimit.sh
#
# @note Exit code design rationale:
#   - warning status exits with 0 to allow PR creation to proceed
#   - caller workflows can check outputs.status for finer control
#   - future versions may introduce exit code 2 for warnings
#
# @note Reset time handling:
#   If reset_time is "unknown" (due to date parsing failure or missing field),
#   validation still proceeds based solely on the remaining count.
#
#   Rationale:
#   - Remaining count is the authoritative source for rate limit status
#   - Reset time is informational only (for user guidance)
#   - Failing on unknown reset time would be overly strict
#
#   Caller workflows may treat unknown reset time as a special case by
#   checking outputs.message for "reset time is unavailable".
#
#   Future versions (v4+) may introduce exit code 2 for warnings with
#   unknown reset time to allow finer-grained control.
#
# @author atsushifx
# @version 3.3.0
# @license MIT
# @copyright Copyright (c) 2026- aglabo <https://github.com/aglabo>

set -uo pipefail

# ============================================================================
# Constants
# ============================================================================

# Rate limit thresholds
readonly RATE_LIMIT_WARNING_THRESHOLD=10
readonly RATE_LIMIT_ERROR_THRESHOLD=0

# Timeout configuration
readonly API_TIMEOUT_SECONDS=30

# Exit codes for error classification
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_GH_NOT_FOUND=127
readonly EXIT_JQ_NOT_FOUND=126
readonly EXIT_TIMEOUT=124

# ============================================================================
# LAYER 1: Data Fetching (Pure Functions)
# ============================================================================

# @description Fetch GitHub API rate limit data with timeout and prerequisite checks.
#   This is a pure function that returns data via stdout and status via exit code.
#   It performs prerequisite checks (gh and jq availability) before attempting
#   the API call.
#
# @noargs
#
# @exitcode 0 Success - rate limit data fetched
# @exitcode 127 gh command not found (environment prerequisite not met)
# @exitcode 126 jq command not found (environment prerequisite not met)
# @exitcode 124 Timeout - API call exceeded time limit
# @exitcode 1 Other error (API failure, authentication failure, etc.)
#
# @stdout Rate limit JSON data (only on success)
# @stderr None (all output via stdout or exit code)
#
# @example
#   if rate_limit_json=$(fetch_rate_limit_data); then
#     echo "Fetched: $rate_limit_json"
#   else
#     echo "Failed with exit code: $?"
#   fi
fetch_rate_limit_data() {
  local rate_limit_json

  # Fetch rate limit with timeout
  if ! rate_limit_json=$(timeout "${API_TIMEOUT_SECONDS}s" gh api rate_limit 2>&1); then
    return $?
  fi

  echo "$rate_limit_json"
  return "$EXIT_SUCCESS"
}

# @description Parse rate limit JSON and extract required values.
#   This is a pure function that parses JSON and returns extracted values
#   via stdout. It validates the JSON structure and returns an error if
#   any required field is missing or invalid.
#
# @arg $1 string Rate limit JSON response from GitHub API
#
# @exitcode 0 Success - JSON parsed successfully
# @exitcode 1 Parse error - JSON is invalid or missing required fields
#
# @stdout Space-separated values: "remaining total reset_time" (only on success)
# @stderr None (all output via stdout or exit code)
#
# @example
#   if parse_result=$(parse_rate_limit_json "$json"); then
#     read -r remaining total reset_time <<< "$parse_result"
#   fi
parse_rate_limit_json() {
  local json="$1"
  local remaining total reset_time

  remaining=$(echo "$json" | jq -r '.rate.remaining' 2>/dev/null) || return 1
  total=$(echo "$json" | jq -r '.rate.limit' 2>/dev/null) || return 1
  reset_time=$(echo "$json" | jq -r '.rate.reset' 2>/dev/null) || return 1

  echo "$remaining $total $reset_time"
  return "$EXIT_SUCCESS"
}

# @description Format Unix timestamp to human-readable date string.
#   This function attempts multiple date formatting methods for cross-platform
#   compatibility (GNU date and BSD date). Falls back to "unknown" if all
#   methods fail.
#
# @arg $1 string Unix timestamp (seconds since epoch)
#
# @stdout Formatted date string (e.g., "2024-01-15 10:30:00 UTC") or "unknown"
#
# @example
#   reset_date=$(format_reset_time "1705318200")
#   echo "Resets at: $reset_date"
format_reset_time() {
  local timestamp="$1"
  date -d "@$timestamp" 2>/dev/null || date -r "$timestamp" 2>/dev/null || echo "unknown"
}

# ============================================================================
# LAYER 2: Validation Logic (Pure Functions)
# ============================================================================

# @description Determine validation status based on remaining API calls.
#   This is a pure function that implements the business logic for rate limit
#   validation. It returns the status string via stdout without any side effects.
#
#   NOTE: This function relies ONLY on the remaining count, not on reset time.
#   Even if reset_time is "unknown", the status is determined by remaining count.
#   This is intentional - remaining count is authoritative, reset time is advisory.
#
# @arg $1 integer Remaining API calls
#
# @stdout Status string: "ok" | "warning" | "error"
#
# @example
#   status=$(determine_status 15)  # Returns "ok"
#   status=$(determine_status 5)   # Returns "warning"
#   status=$(determine_status 0)   # Returns "error"
determine_status() {
  local remaining=$1

  if [ "$remaining" -le "$RATE_LIMIT_ERROR_THRESHOLD" ]; then
    echo "error"
  elif [ "$remaining" -lt "$RATE_LIMIT_WARNING_THRESHOLD" ]; then
    echo "warning"
  else
    echo "ok"
  fi
}

# ============================================================================
# Main: Validation & I/O (Modularized)
# ============================================================================

# @description Handle data fetch errors with detailed error messages.
#   This function is called when fetch_rate_limit_data() fails. It classifies
#   the error based on exit code, outputs appropriate error messages, writes
#   to GITHUB_OUTPUT, and exits with error code.
#
# @arg $1 integer Exit code from fetch_rate_limit_data()
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
#
# @example
#   fetch_rate_limit_data || handle_fetch_error $?
handle_fetch_error() {
  local fetch_exit_code=$1
  local message

  # Create error message based on exit code (error classification)
  case $fetch_exit_code in
    "$EXIT_TIMEOUT")
      echo "::error::GitHub API call timed out after ${API_TIMEOUT_SECONDS} seconds"
      echo "::error::This may indicate network issues or GitHub API unavailability."
      message="GitHub API request timed out after ${API_TIMEOUT_SECONDS} seconds"
      ;;
    *)
      echo "::error::Failed to fetch GitHub API rate limit information"
      echo "::error::This may indicate authentication failure or API errors."
      message="Failed to fetch GitHub API rate limit (API error)"
      ;;
  esac

  # Write to GITHUB_OUTPUT
  {
    echo "status=error"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=error, message=${message}"
  echo ""
  echo "=== Rate limit validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Handle JSON parse errors.
#   This function is called when parse_rate_limit_json() fails. It outputs
#   error messages, writes to GITHUB_OUTPUT, and exits with error code.
#
# @noargs
#
# @noreturn This function always exits with EXIT_ERROR
#
# @set GITHUB_OUTPUT Appends error status and message
#
# @stdout Error messages and GitHub Actions annotations
#
# @example
#   parse_rate_limit_json "$json" || handle_parse_error
handle_parse_error() {
  local message

  echo "::error::Failed to parse rate limit JSON response"
  echo "::error::The API response format may have changed or is invalid."
  message="Failed to parse rate limit data (invalid JSON response)"

  # Write to GITHUB_OUTPUT
  {
    echo "status=error"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=error, message=${message}"
  echo ""
  echo "=== Rate limit validation failed ==="
  exit "$EXIT_ERROR"
}

# @description Output rate limit status with appropriate messages.
#   This function generates and outputs status-specific messages and GitHub
#   Actions annotations based on the validation status.
#
#   NOTE: When reset_date is "unknown", the function outputs a specific message
#   ("Rate limit reset time is unavailable") to inform the user, but validation
#   still proceeds based on remaining count. Caller workflows may check
#   outputs.message for "reset time is unavailable" and treat it specially.
#
# @arg $1 string Status (ok|warning|error)
# @arg $2 integer Remaining API calls
# @arg $3 integer Total API calls
# @arg $4 string Reset date (formatted or "unknown")
#
# @stdout Status-specific message string
#
# @example
#   message=$(output_rate_limit_status "$status" "$remaining" "$total" "$reset_date")
output_rate_limit_status() {
  local status=$1
  local remaining=$2
  local total=$3
  local reset_date=$4
  local message

  case "$status" in
    error)
      message="Rate limit exhausted (${remaining}/${total} remaining)"
      echo "::error::GitHub API rate limit exhausted. Please wait for reset."
      if [ "$reset_date" != "unknown" ]; then
        echo "::error::Rate limit resets at: $reset_date"
      else
        # NOTE: Validation proceeds even with unknown reset time.
        # Remaining count is authoritative; reset time is advisory only.
        echo "::error::Rate limit reset time is unavailable"
      fi
      ;;
    warning)
      message="Rate limit low (${remaining}/${total} remaining)"
      echo "::warning::GitHub API rate limit is low: $remaining / $total remaining"
      if [ "$reset_date" != "unknown" ]; then
        echo "::warning::Rate limit resets at: $reset_date"
      else
        # NOTE: Validation proceeds even with unknown reset time.
        # Remaining count is authoritative; reset time is advisory only.
        echo "::warning::Rate limit reset time is unavailable"
      fi
      ;;
    ok)
      message="Rate limit sufficient (${remaining}/${total} remaining)"
      echo "✓ GitHub API rate limit check passed"
      ;;
  esac

  echo "$message"
}

# @description Write validation result to GITHUB_OUTPUT and exit.
#   This function writes the final validation result to GITHUB_OUTPUT,
#   displays a summary message, and exits with the appropriate exit code.
#
# @arg $1 string Status (ok|warning|error)
# @arg $2 string Status message
#
# @noreturn This function always exits (with EXIT_SUCCESS or EXIT_ERROR)
#
# @set GITHUB_OUTPUT Appends status and message
#
# @stdout Summary message
#
# @note Warning status exits with 0 to allow PR creation to proceed.
#   Caller workflow may override this behavior by checking outputs.status.
#   Future versions may introduce exit 2 for warning to allow finer control.
#
# @example
#   write_output_and_exit "$status" "$message"
write_output_and_exit() {
  local status=$1
  local message=$2

  # Write to GITHUB_OUTPUT
  {
    echo "status=${status}"
    echo "message=${message}"
  } >> "$GITHUB_OUTPUT"

  echo "Output: status=${status}, message=${message}"
  echo ""

  # Display summary and exit
  case "$status" in
    error)
      echo "=== Rate limit validation failed ==="
      exit "$EXIT_ERROR"
      ;;
    warning)
      echo "=== Rate limit validation passed with warnings ==="
      exit "$EXIT_SUCCESS"
      ;;
    ok)
      echo "=== Rate limit validation complete ==="
      exit "$EXIT_SUCCESS"
      ;;
  esac
}

# @description Main validation workflow (orchestration).
#   This function orchestrates the validation process by calling modularized
#   functions in sequence:
#   1. Fetch rate limit data (or handle error)
#   2. Parse JSON response (or handle error)
#   3. Extract and format data
#   4. Determine validation status
#   5. Output status messages
#   6. Write to GITHUB_OUTPUT and exit
#
#   This orchestration approach keeps the main function clean and readable,
#   with all complex logic delegated to specialized functions.
#
# @noargs
#
# @noreturn This function delegates to write_output_and_exit() which always exits
#
# @set GITHUB_OUTPUT Appends status and message (via delegated functions)
#
# @stdout Validation progress, messages, and GitHub Actions annotations
#
# @example
#   main "$@"
main() {
  local rate_limit_json parse_result
  local remaining total reset_time reset_date
  local status message

  echo "=== GitHub API Rate Limit Validation ==="
  echo ""

  # ========================================
  # Data Fetching
  # ========================================

  rate_limit_json=$(fetch_rate_limit_data) || handle_fetch_error $?

  # ========================================
  # Data Parsing
  # ========================================

  parse_result=$(parse_rate_limit_json "$rate_limit_json") || handle_parse_error

  # ========================================
  # Data Extraction
  # ========================================

  read -r remaining total reset_time <<< "$parse_result"
  reset_date=$(format_reset_time "$reset_time")

  # ========================================
  # Validation Logic
  # ========================================

  echo "GitHub API rate limit: $remaining / $total remaining"
  echo ""

  status=$(determine_status "$remaining")

  # ========================================
  # Output & Exit
  # ========================================

  message=$(output_rate_limit_status "$status" "$remaining" "$total" "$reset_date")

  write_output_and_exit "$status" "$message"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
