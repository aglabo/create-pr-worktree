#!/usr/bin/env bash
# @file create-pr.sh
# @brief Create or update GitHub Pull Request with timeout handling
# @description
#   This script creates a new Pull Request or updates an existing one with the
#   provided title and body. It is organized in three layers: Data Fetching
#   (pure functions), Validation Logic (pure functions), and Main I/O (all
#   input/output and exit handling).
#
#   **IMPORTANT PREREQUISITE:**
#   This script assumes that environment validation has been completed successfully
#   by prior validation steps. The following tools MUST be available:
#
#   - gh: GitHub CLI (version 2.0+, authenticated with valid token)
#   - jq: JSON processor (version 1.0+)
#   - timeout: GNU coreutils timeout command (GNU version REQUIRED)
#
#   **Platform Requirements:**
#   This script requires a Linux runner with GNU coreutils. It is NOT compatible with:
#   - macOS runners (BSD timeout has different exit codes)
#   - Windows runners (timeout command not available by default)
#
#   **Supported Runners:**
#   - ubuntu-latest
#   - ubuntu-22.04
#   - ubuntu-20.04
#
#   **Recommended Workflow:**
#   ```yaml
#   - name: Validate runner environment (REQUIRED FIRST)
#     uses: atsushifx/.github-aglabo/.github/actions/validate-environment@v1
#     with:
#       additional-apps: "gh|gh|regex:version ([0-9.]+)|2.0,jq|jq|regex:jq-([0-9.]+)|1.0"
#
#   - name: Create or update PR (this script)
#     run: ./create-pr.sh "$BASE_BRANCH" "$PR_BRANCH" "$PR_TITLE" "$PR_BODY"
#   ```
#
# @arg $1 string Base branch name (target branch for PR)
# @arg $2 string PR branch name (head branch with changes)
# @arg $3 string PR title
# @arg $4 string PR body/description
#
# @env GH_TOKEN GitHub authentication token (required)
# @env GITHUB_TOKEN Alternative to GH_TOKEN (required if GH_TOKEN not set)
# @env GITHUB_OUTPUT Path to GitHub Actions output file (required)
# @env RUNNER_TEMP Path to runner temporary directory (required for body file)
#
# @exitcode 0 PR created or updated successfully
# @exitcode 1 PR operation failed (creation/update error, API failure, timeout)
#
# @stdout Operation progress messages and GitHub Actions annotations
#
# @see https://cli.github.com/manual/gh_pr_create
# @see https://cli.github.com/manual/gh_pr_edit
# @see https://cli.github.com/manual/gh_pr_list
#
# @example
#   GH_TOKEN="${{ github.token }}" \
#   GITHUB_OUTPUT="${GITHUB_OUTPUT}" \
#   RUNNER_TEMP="${RUNNER_TEMP}" \
#   ./create-pr.sh "main" "feature/my-feature" "Add new feature" "Description here"
#
# @note Operation logic:
#   - Checks if PR already exists between head and base branches
#   - If exists: Updates title and body (operation=updated)
#   - If not exists: Creates new PR (operation=created)
#   - Outputs: pr-number, pr-url, operation
#
# @note Check failure fallback behavior:
#   When check_existing_pr() fails (timeout or API error), the script treats
#   this as "no existing PR" and attempts to create a new one. This fail-open
#   strategy prioritizes availability over strict validation. Worst case: GitHub
#   API rejects duplicate PR creation with clear error message.
#
# @note Timeout configuration:
#   - PR existence check: 30 seconds
#   - PR creation: 60 seconds
#   - PR update: 30 seconds
#   - PR info retrieval: 30 seconds
#
# @note Interface design:
#   This script intentionally uses positional arguments for simplicity and
#   explicit parameter passing. Future versions may evolve to environment-based
#   options if additional parameters (labels, auto-merge, draft) are needed
#   to avoid positional argument explosion.
#
# @author atsushifx
# @version 1.0.0
# @license MIT
# @copyright Copyright (c) 2026- aglabo <https://github.com/aglabo>

# cspell:words Eeuo
set -Eeuo pipefail
trap 'echo "::error::Unexpected error at line $LINENO"' ERR

# ============================================================================
# Constants
# ============================================================================

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_TIMEOUT=124  # GNU timeout exit code (Linux REQUIRED)

# Timeout configuration
readonly TIMEOUT_PR_CHECK=30
readonly TIMEOUT_PR_CREATE=60
readonly TIMEOUT_PR_UPDATE=30
readonly TIMEOUT_PR_INFO=30

# Operation types (for output consistency)
readonly OPERATION_CREATED="created"
readonly OPERATION_UPDATED="updated"
readonly OPERATION_UPDATE_FAILED="update-failed"

# ============================================================================
# LAYER 1: Data Fetching (Pure Functions)
# ============================================================================

# @description Check if PR already exists between head and base branches.
#   This is a pure function that queries GitHub API to check PR existence.
#   Returns PR number via stdout if exists, empty string if not.
#
#   **IMPORTANT FALLBACK SEMANTICS:**
#   Failures from this function are handled with a fail-open strategy (see
#   handle_check_error). If the check fails, the script assumes no PR exists
#   and attempts creation. GitHub API will reject duplicate PRs, providing a
#   safety net.
#
# @arg $1 string PR branch (head)
# @arg $2 string Base branch
#
# @exitcode 0 Query successful (PR may or may not exist)
# @exitcode 124 Timeout
# @exitcode 1 API error
#
# @stdout PR number if exists, empty string if not (only on success)
#
# @example
#   if pr_number=$(check_existing_pr "feature" "main"); then
#     [ -n "$pr_number" ] && echo "PR #$pr_number exists"
#   fi
check_existing_pr() {
  local pr_branch="$1"
  local base_branch="$2"
  local existing_pr

  # Query without stderr mixing - let stderr go to console naturally
  if ! existing_pr=$(timeout "${TIMEOUT_PR_CHECK}s" gh pr list \
    --head "$pr_branch" \
    --base "$base_branch" \
    --json number \
    --jq '.[0].number'); then
    return $?
  fi

  echo "$existing_pr"
  return "$EXIT_SUCCESS"
}

# @description Create new Pull Request with provided details.
#   This function creates PR body file and calls gh pr create.
#   Uses mktemp to avoid file conflicts in concurrent scenarios.
#
# @arg $1 string Base branch
# @arg $2 string PR branch (head)
# @arg $3 string PR title
# @arg $4 string PR body content
#
# @exitcode 0 PR created successfully
# @exitcode 124 Timeout
# @exitcode 1 Creation failed
#
# @stdout PR URL (only on success)
#
# @example
#   if pr_url=$(create_new_pr "main" "feature" "Title" "Body"); then
#     echo "Created: $pr_url"
#   fi
create_new_pr() {
  local base_branch="$1"
  local pr_branch="$2"
  local pr_title="$3"
  local pr_body="$4"
  local body_file
  local pr_url

  # Create temporary file (safer than fixed path)
  body_file=$(mktemp) || return "$EXIT_ERROR"
  trap 'rm -f "$body_file"' RETURN

  # Prepare body file
  printf '%s\n' "$pr_body" > "$body_file"

  # Create PR with timeout - gh pr create outputs URL to stdout on success
  if ! pr_url=$(timeout "${TIMEOUT_PR_CREATE}s" gh pr create \
    --base "$base_branch" \
    --head "$pr_branch" \
    --title "$pr_title" \
    --body-file "$body_file"); then
    return $?
  fi

  echo "$pr_url"
  return "$EXIT_SUCCESS"
}

# @description Update existing Pull Request title and body.
#   This function updates PR using gh pr edit.
#   Uses mktemp to avoid file conflicts in concurrent scenarios.
#
# @arg $1 string PR number
# @arg $2 string PR title
# @arg $3 string PR body content
#
# @exitcode 0 PR updated successfully
# @exitcode 124 Timeout
# @exitcode 1 Update failed
#
# @example
#   update_existing_pr "123" "New Title" "New Body"
update_existing_pr() {
  local pr_number="$1"
  local pr_title="$2"
  local pr_body="$3"
  local body_file

  # Create temporary file (safer than fixed path)
  body_file=$(mktemp) || return "$EXIT_ERROR"
  trap 'rm -f "$body_file"' RETURN

  # Prepare body file
  printf '%s\n' "$pr_body" > "$body_file"

  # Update PR with timeout (no stderr mixing)
  if ! timeout "${TIMEOUT_PR_UPDATE}s" gh pr edit "$pr_number" \
    --title "$pr_title" \
    --body-file "$body_file"; then
    return $?
  fi

  return "$EXIT_SUCCESS"
}

# @description Get PR information (number and URL) from repository.
#   This is a pure function that fetches PR data as JSON.
#
# @arg $1 string PR branch (head)
# @arg $2 string Base branch
#
# @exitcode 0 Success - PR info fetched
# @exitcode 124 Timeout
# @exitcode 1 API error
#
# @stdout PR JSON data (only on success)
#
# @example
#   if pr_json=$(get_pr_info "feature" "main"); then
#     echo "Got PR info: $pr_json"
#   fi
get_pr_info() {
  local pr_branch="$1"
  local base_branch="$2"
  local pr_json

  # Query without stderr mixing - let stderr go to console naturally
  if ! pr_json=$(timeout "${TIMEOUT_PR_INFO}s" gh pr list \
    --head "$pr_branch" \
    --base "$base_branch" \
    --json number,url \
    --jq '.[0]'); then
    return $?
  fi

  echo "$pr_json"
  return "$EXIT_SUCCESS"
}

# ============================================================================
# LAYER 2: Validation Logic (Pure Functions)
# ============================================================================

# @description Extract PR number from GitHub PR URL.
#   Uses bash regex for safety (no external commands).
#
# @arg $1 string PR URL
#
# @exitcode 0 Success - PR number extracted
# @exitcode 1 Invalid URL format
#
# @stdout PR number (only on success)
#
# @example
#   if pr_number=$(extract_pr_number_from_url "$pr_url"); then
#     echo "PR number: $pr_number"
#   fi
extract_pr_number_from_url() {
  local pr_url="$1"

  # Match /pull/NUMBER at end of URL or followed by other path components
  if [[ "$pr_url" =~ /pull/([0-9]+)$ ]] || [[ "$pr_url" =~ /pull/([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
    return "$EXIT_SUCCESS"
  else
    return "$EXIT_ERROR"
  fi
}

# @description Validate PR URL format.
#   This is a pure validation function.
#
# @arg $1 string PR URL
#
# @exitcode 0 PR URL is valid
# @exitcode 1 PR URL is invalid or empty
validate_pr_url() {
  local pr_url="$1"

  if [ -z "$pr_url" ]; then
    return "$EXIT_ERROR"
  fi

  if [[ ! "$pr_url" =~ /pull/ ]]; then
    return "$EXIT_ERROR"
  fi

  return "$EXIT_SUCCESS"
}

# @description Validate that PR JSON is not null or empty.
#   This is a pure validation function.
#
#   **DEPRECATED**: This function is part of the old get_pr_info flow.
#   Use validate_pr_url instead for the new URL-based flow.
#
# @arg $1 string PR JSON data
#
# @exitcode 0 PR JSON is valid
# @exitcode 1 PR JSON is null or empty
validate_pr_json() {
  local pr_json="$1"

  if [ -z "$pr_json" ] || [ "$pr_json" = "null" ]; then
    return "$EXIT_ERROR"
  fi

  return "$EXIT_SUCCESS"
}

# @description Extract PR number and URL from JSON.
#   This is a pure function that parses JSON and returns extracted values.
#
#   **DEPRECATED NOTE:**
#   This function is used in the get_pr_info flow which has eventual consistency
#   issues. Consider using URL-based extraction instead (see Issue 2).
#
# @arg $1 string PR JSON data
#
# @exitcode 0 Success - values extracted and validated
# @exitcode 1 Extraction or validation failed
#
# @stdout Space-separated values: "pr_number pr_url" (only on success)
#
# @example
#   if result=$(extract_pr_data "$pr_json"); then
#     read -r pr_number pr_url <<< "$result"
#   fi
extract_pr_data() {
  local pr_json="$1"
  local pr_number pr_url

  # Validate JSON is not empty or null first
  if [ -z "$pr_json" ] || [ "$pr_json" = "null" ]; then
    return "$EXIT_ERROR"
  fi

  # Extract with explicit error checking (capture stderr)
  if ! pr_number=$(echo "$pr_json" | jq -r '.number' 2>&1); then
    return "$EXIT_ERROR"
  fi

  if ! pr_url=$(echo "$pr_json" | jq -r '.url' 2>&1); then
    return "$EXIT_ERROR"
  fi

  # Validate extracted values are not null or empty
  if [ -z "$pr_number" ] || [ "$pr_number" = "null" ]; then
    return "$EXIT_ERROR"
  fi

  if [ -z "$pr_url" ] || [ "$pr_url" = "null" ]; then
    return "$EXIT_ERROR"
  fi

  # Validate PR number format (must be numeric)
  if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    return "$EXIT_ERROR"
  fi

  # Validate URL format (must start with http:// or https://)
  if [[ ! "$pr_url" =~ ^https?:// ]]; then
    return "$EXIT_ERROR"
  fi

  echo "$pr_number $pr_url"
  return "$EXIT_SUCCESS"
}

# ============================================================================
# Main: PR Operations & I/O (Modularized)
# ============================================================================

# @description Handle PR existence check errors.
#   This function logs warnings but does NOT fail the script - it treats
#   check failures as "no existing PR" and continues with creation.
#
#   **FAIL-OPEN STRATEGY RATIONALE:**
#   1. Prioritizes availability over strict validation
#   2. GitHub API will reject duplicate PR creation attempts
#   3. Transient API issues shouldn't block PR creation
#   4. Check failures are often less severe than creation failures
#
# @arg $1 integer Exit code from check_existing_pr()
#
# @return 0 Always returns success to continue with PR creation
#
# @stdout Warning messages and GitHub Actions annotations
handle_check_error() {
  local exit_code=$1

  case $exit_code in
    "$EXIT_TIMEOUT")
      echo "::warning::GitHub API call (gh pr list) timed out after ${TIMEOUT_PR_CHECK} seconds"
      echo "::warning::Assuming no existing PR, will attempt to create new one"
      ;;
    *)
      echo "::warning::Failed to check existing PR, assuming none exists"
      ;;
  esac

  # Don't exit - treat as no existing PR and continue with creation
  echo ""
  return 0
}

# @description Handle PR creation errors.
#
# @arg $1 integer Exit code from create_new_pr()
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_create_error() {
  local exit_code=$1

  case $exit_code in
    "$EXIT_TIMEOUT")
      echo "::error::GitHub API call (gh pr create) timed out after ${TIMEOUT_PR_CREATE} seconds"
      ;;
    *)
      echo "::error::Failed to create PR"
      ;;
  esac

  exit "$exit_code"
}

# @description Handle PR update errors.
#   This function logs warnings and returns EXIT_ERROR to signal failure.
#   Update failures are non-fatal (script continues), but operation status
#   is set to 'update-failed' to accurately reflect the result.
#
# @arg $1 integer Exit code from update_existing_pr()
#
# @return EXIT_ERROR Always returns error to signal update failure
#
# @stdout Warning messages and GitHub Actions annotations
handle_update_error() {
  local exit_code=$1

  case $exit_code in
    "$EXIT_TIMEOUT")
      echo "::warning::GitHub API call (gh pr edit) timed out after ${TIMEOUT_PR_UPDATE} seconds"
      echo "::warning::PR update failed, but PR exists and can be updated manually"
      ;;
    *)
      echo "::warning::Failed to update PR title/body"
      ;;
  esac

  echo "::warning::Operation status will be set to 'update-failed'"
  echo ""

  return "$EXIT_ERROR"
}

# @description Handle PR info retrieval errors.
#
# @arg $1 integer Exit code from get_pr_info()
# @arg $2 string PR JSON (error message)
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_info_error() {
  local exit_code=$1
  local pr_json="$2"

  case $exit_code in
    "$EXIT_TIMEOUT")
      echo "::error::GitHub API call (gh pr list) timed out after ${TIMEOUT_PR_INFO} seconds"
      ;;
    *)
      echo "::error::Failed to get PR information: $pr_json"
      ;;
  esac

  exit "$exit_code"
}

# @description Handle argument validation errors.
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_argument_error() {
  echo "::error::Required arguments not provided to create-pr script"
  echo "::error::Usage: create-pr.sh <base-branch> <pr-branch> <pr-title> <pr-body>"
  exit "$EXIT_ERROR"
}

# @description Handle PR JSON validation errors.
#
# @arg $1 string PR branch
# @arg $2 string Base branch
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_json_validation_error() {
  local pr_branch="$1"
  local base_branch="$2"

  echo "::error::No PR found for branch $pr_branch -> $base_branch"
  exit "$EXIT_ERROR"
}

# @description Handle PR data extraction errors.
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_extraction_error() {
  echo "::error::Failed to extract PR number or URL from response"
  exit "$EXIT_ERROR"
}

# @description Handle operation type validation errors.
#
# @noreturn This function always exits with EXIT_ERROR
#
# @stdout Error messages and GitHub Actions annotations
handle_operation_error() {
  echo "::error::Failed to determine operation type"
  exit "$EXIT_ERROR"
}

# @description Write outputs to GITHUB_OUTPUT and display success message.
#
# @arg $1 string PR number
# @arg $2 string PR URL
# @arg $3 string Operation (created/updated)
#
# @noreturn This function always exits with EXIT_SUCCESS
#
# @set GITHUB_OUTPUT Appends pr-number, pr-url, operation
#
# @stdout Success message
write_outputs_and_exit() {
  local pr_number="$1"
  local pr_url="$2"
  local operation="$3"

  # Write to GITHUB_OUTPUT
  {
    echo "pr-number=$pr_number"
    echo "pr-url=$pr_url"
    echo "operation=$operation"
  } >> "$GITHUB_OUTPUT"

  # Display success message
  case "$operation" in
    "$OPERATION_UPDATED")
      echo "✓ Updated PR #$pr_number: $pr_url"
      ;;
    "$OPERATION_CREATED")
      echo "✓ Created PR #$pr_number: $pr_url"
      ;;
    "$OPERATION_UPDATE_FAILED")
      echo "⚠ PR #$pr_number exists but update failed: $pr_url"
      echo "  Title and body may not have been updated"
      ;;
    *)
      echo "::warning::Unknown operation: $operation"
      ;;
  esac

  exit "$EXIT_SUCCESS"
}

# @description Main PR creation/update workflow (orchestration).
#   This function orchestrates the PR operation process:
#   1. Validate arguments
#   2. Check if PR exists
#   3. Create or update PR accordingly
#   4. Get PR information
#   5. Extract and validate PR data
#   6. Write outputs and exit
#
# @arg $1 string Base branch name
# @arg $2 string PR branch name
# @arg $3 string PR title
# @arg $4 string PR body
#
# @noreturn This function delegates to write_outputs_and_exit() which always exits
#
# @set GITHUB_OUTPUT Appends pr-number, pr-url, operation (via delegated functions)
#
# @stdout Operation progress, messages, and GitHub Actions annotations
main() {
  local base_branch="${1:-}"
  local pr_branch="${2:-}"
  local pr_title="${3:-}"
  local pr_body="${4:-}"
  local existing_pr operation pr_json pr_data pr_number pr_url

  # ========================================
  # Argument Validation
  # ========================================

  if [ -z "$base_branch" ] || [ -z "$pr_branch" ] || [ -z "$pr_title" ] || [ -z "$pr_body" ]; then
    handle_argument_error
  fi

  echo "=== Pull Request Creation/Update ===="
  echo ""
  echo "Base branch: $base_branch"
  echo "PR branch: $pr_branch"
  echo ""

  # ========================================
  # Check Existing PR
  # ========================================

  echo "Checking if PR already exists..."

  if ! existing_pr=$(check_existing_pr "$pr_branch" "$base_branch"); then
    handle_check_error $?
    existing_pr=""  # Treat as non-existent
  fi

  # ========================================
  # Create or Update PR
  # ========================================

  if [ -n "$existing_pr" ]; then
    echo "PR #$existing_pr already exists, updating title and body"

    if update_existing_pr "$existing_pr" "$pr_title" "$pr_body"; then
      operation="$OPERATION_UPDATED"
    else
      handle_update_error $?
      operation="$OPERATION_UPDATE_FAILED"
    fi

    pr_number="$existing_pr"

    # Get URL using gh pr view
    if ! pr_url=$(timeout 30s gh pr view "$pr_number" --json url --jq '.url' 2>/dev/null); then
      echo "::warning::Could not retrieve PR URL, constructing from repository info"
      # Fallback: construct URL from repo info
      repo_info=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || repo_info=""
      if [ -n "$repo_info" ]; then
        pr_url="https://github.com/${repo_info}/pull/${pr_number}"
      else
        echo "::error::Cannot determine PR URL"
        exit "$EXIT_ERROR"
      fi
    fi
  else
    echo "Creating new Pull Request"

    if ! pr_url=$(create_new_pr "$base_branch" "$pr_branch" "$pr_title" "$pr_body"); then
      handle_create_error $?
    fi

    operation="$OPERATION_CREATED"

    # Extract PR number from URL
    if ! pr_number=$(extract_pr_number_from_url "$pr_url"); then
      echo "::error::Failed to extract PR number from URL: $pr_url"
      exit "$EXIT_ERROR"
    fi
  fi

  # ========================================
  # Validate Operation
  # ========================================

  if [ -z "$operation" ]; then
    handle_operation_error
  fi

  # ========================================
  # Validate PR Data
  # ========================================

  if [ -z "$pr_number" ]; then
    echo "::error::Failed to determine PR number"
    exit "$EXIT_ERROR"
  fi

  if ! validate_pr_url "$pr_url"; then
    echo "::error::Invalid or missing PR URL: $pr_url"
    exit "$EXIT_ERROR"
  fi

  # ========================================
  # Output & Exit
  # ========================================

  echo ""
  write_outputs_and_exit "$pr_number" "$pr_url" "$operation"
}

# ============================================================================
# Entry Point
# ============================================================================

main "$@"
