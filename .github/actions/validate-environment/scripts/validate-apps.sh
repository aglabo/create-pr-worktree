#!/usr/bin/env bash
# src: ./.github/actions/validate-environment/scripts/validate-apps.sh
# @(#) : Validate required applications (Git, curl, gh CLI)
#
# Copyright (c) 2026- aglabo <https://github.com/aglabo>
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file validate-apps.sh
# @brief Validate required applications for GitHub Actions with safe version extraction
# @description
#   Validates that required applications are installed with configurable fail-fast behavior.
#   Uses SAFE extraction methods WITHOUT eval - prevents arbitrary code execution.
#
#   **Default Checks:**
#   1. Git is installed (version 2.30+ required)
#   2. curl is installed
#
#   **Optional gh CLI Validation:**
#   - When gh is included via additional-apps, validates:
#     * gh is installed (version 2.0+ required)
#     * gh is authenticated (via `gh auth status`)
#
#   **Features:**
#   - Gate action design: exits immediately on first validation error
#   - Generic version checking using sort -V (handles semver, prerelease, etc.)
#   - Safe declarative version extraction (NO EVAL)
#   - Backward compatible with field-number extraction (legacy)
#   - Machine-readable outputs for downstream actions
#   - Extensible: additional applications can be specified as arguments
#
#   **Version Extraction (Security Hardened):**
#   - Prefix-typed extractors: field:N or regex:PATTERN (explicit method declaration)
#   - sed-only with # delimiter (allows / in patterns)
#   - NO eval usage - prevents arbitrary code execution
#   - Input validation: Rejects shell metacharacters, control chars, sed delimiter (#)
#   - sed injection prevention: # character rejection prevents breaking out of pattern
#   - Examples: "regex:version ([0-9.]+)" extracts version number from "git version 2.52.0"
#
#   **Environment Variables:**
#   - FAIL_FAST: Internal implementation detail (always true for gate behavior)
#   - GITHUB_OUTPUT: Output file for GitHub Actions (optional, fallback to /dev/null)
#
#   **Outputs (machine-readable):**
#   - status: "success" or "error"
#   - message: Human-readable summary
#   - validated_apps: Comma-separated list of validated app names
#   - validated_count: Number of successfully validated apps
#   - failed_apps: Comma-separated list of failed app names (on error)
#   - failed_count: Number of failed apps
#
# @exitcode 0 Application validation successful
# @exitcode 1 Application validation failed (one or more apps missing or invalid)
#
# @author   atsushifx
# @version  1.2.0
# @license  MIT

set -euo pipefail

# Safe output file handling - fallback to /dev/null if not in GitHub Actions
GITHUB_OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"

# Fail-fast mode: INTERNAL ONLY (not exposed as action input)
# This action is a gate - errors mean the workflow cannot continue
# Always defaults to true (fail on first error)
FAIL_FAST="${FAIL_FAST:-true}"

# Error tracking (used only when FAIL_FAST=false for internal testing/debugging)
declare -a VALIDATION_ERRORS=()

# Validated applications (populated by validate_apps function)
declare -a VALIDATED_APPS=()        # Application names only
declare -a VALIDATED_VERSIONS=()    # Version strings only

# Version validation result globals (used by validate_app_version)
# SCOPE: Internal to this script process only (NOT visible to action.yml caller)
# PURPOSE: Pass results between validate_app_version() and validate_apps() functions
#          within the same shell process, avoiding stdout pollution
# EXTERNAL CONTRACT: action.yml receives results via GITHUB_OUTPUT, not these globals
#
# CONCURRENCY: NOT thread-safe. validate_apps() must execute sequentially (current design).
#              If parallel execution is needed in the future, consider:
#              - Using subshells with temp files instead of globals
#              - Using nameref (local -n) for bash 4.3+ (adds complexity)
declare VALIDATED_VERSION=""        # Full version string on success
declare VALIDATED_VERSION_NUM=""    # Extracted version number (for error reporting)
declare VALIDATED_MIN_VERSION=""    # Required minimum version (for error reporting)

# Special validation error message (used by validate_app_special)
# SCOPE: Internal to this script process, same concurrency constraints as above
declare SPECIAL_VALIDATION_ERROR="" # Detailed error message from tool-specific validation

# @description Extract version number from full version string using safe sed-only extraction
# @arg $1 string Full version string (e.g., "git version 2.52.0")
# @arg $2 string Version extractor: "field:N", "regex:PATTERN", or empty for auto semver
# @exitcode 0 Extraction successful
# @exitcode 1 Extraction failed (no match or invalid pattern)
# @stdout Extracted version number (e.g., "2.52.0")
# @stderr Error messages with ::error:: prefix
#
# @example
#   extract_version_number "git version 2.52.0" "field:3"                    # → "2.52.0"
#   extract_version_number "git version 2.52.0" "regex:.*version ([0-9.]+).*" # → "2.52.0"
#   extract_version_number "node v18.0.0" "regex:v([0-9.]+)"                 # → "18.0.0"
#   extract_version_number "curl 8.17.0" ""                                  # → "8.17.0" (auto semver)
extract_version_number() {
  local full_version="$1"
  local version_extractor="$2"

  # Default: extract semver (X.Y or X.Y.Z) if extractor is empty
  if [ -z "$version_extractor" ]; then
    local extracted
    extracted=$(echo "$full_version" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)

    if [ -z "$extracted" ]; then
      echo "::error::Version extraction failed - no semver pattern found in: $full_version" >&2
      return 1
    fi

    echo "$extracted"
    return 0
  fi

  # Parse extractor format: method:argument
  local method="${version_extractor%%:*}"
  local argument="${version_extractor#*:}"

  case "$method" in
    field)
      # Extract Nth field (space-delimited)
      if [[ ! "$argument" =~ ^[0-9]+$ ]]; then
        echo "::error::Invalid field number: $argument" >&2
        return 1
      fi
      echo "$full_version" | cut -d' ' -f"$argument"
      ;;

    regex)
      # Extract using sed -E regex with capture group
      # Use # delimiter to allow / in regex patterns
      if [ -z "$argument" ]; then
        echo "::error::Empty regex pattern" >&2
        return 1
      fi

      # Security: Validate regex pattern to prevent injection
      # Reject our delimiter (#) to prevent breaking out of sed pattern
      if [[ "$argument" == *"#"* ]]; then
        echo "::error::Regex pattern cannot contain '#' character (reserved as sed delimiter): $argument" >&2
        return 1
      fi

      # DESIGN PHILOSOPHY: Security and Auditability over Flexibility
      #
      # We intentionally reject common shell metacharacters including '|' (pipe).
      # While '|' is valid in regex (alternation), we reject it because:
      #
      # 1. This extractor is NOT a general-purpose regex engine
      # 2. Simplicity and auditability are prioritized over expressiveness
      # 3. Version extraction patterns should be simple (e.g., "version ([0-9.]+)")
      # 4. Complex patterns indicate poor --version output design by upstream tools
      # 5. Rejecting metacharacters makes code review and security audits tractable
      #
      # If you need alternation, use character classes instead:
      #   Bad:  "version|ver ([0-9.]+)"    # pipe rejected
      #   Good: "vers?ion ([0-9.]+)"        # optional 's' via ?
      #   Good: "ver[s]?ion ([0-9.]+)"      # character class
      #
      # This is a conscious trade-off: we sacrifice some regex flexibility
      # to gain confidence that no injection attacks can occur via this path.
      #
      # Reject shell metacharacters that shouldn't appear in version extraction regex
      if [[ "$argument" =~ [\;\|\&\$\`\\] ]]; then
        echo "::error::Regex pattern contains dangerous shell metacharacters: $argument" >&2
        return 1
      fi

      # Reject newlines and control characters
      if [[ "$argument" =~ $'\n'|$'\r'|$'\t' ]]; then
        echo "::error::Regex pattern contains control characters" >&2
        return 1
      fi

      local extracted
      extracted=$(echo "$full_version" | sed -E "s#${argument}#\1#")

      # Check if extraction succeeded (result differs from input)
      if [ "$extracted" = "$full_version" ]; then
        echo "::error::Version extraction failed - pattern did not match: $argument" >&2
        echo "::error::Full version string: $full_version" >&2
        return 1
      fi

      echo "$extracted"
      ;;

    *)
      echo "::error::Unknown extraction method: $method (expected: field, regex)" >&2
      return 1
      ;;
  esac
}

# @description Check version meets minimum requirement using GNU sort -V
# @arg $1 string Version to check (e.g., "2.52.0")
# @arg $2 string Minimum required version (e.g., "2.30")
# @exitcode 0 Version meets or exceeds minimum requirement
# @exitcode 1 Version below minimum requirement
check_version() {
  local version="$1"
  local min_version="$2"

  # Use sort -V (version sort) to compare
  # If min_version comes first or equal, version meets requirement
  # printf outputs: min_version, version (in that order)
  # sort -V sorts them in version order
  # If first line after sort == min_version, then version >= min_version
  local sorted_min=$(printf '%s\n%s\n' "$min_version" "$version" | sort -V | head -1)

  if [ "$sorted_min" = "$min_version" ]; then
    return 0  # version >= min_version
  else
    return 1  # version < min_version
  fi
}

# @description Get application version string
# @arg $1 string Command name
# @exitcode 0 Version retrieved successfully
# @exitcode 1 Command failed or version unavailable
# @stdout Full version string (e.g., "git version 2.52.0")
get_app_version() {
  local cmd="$1"

  # Get full version string
  local version_output
  if ! version_output=$("$cmd" --version 2>&1 | head -1); then
    return 1
  fi

  # Output version string to stdout
  echo "$version_output"
  return 0
}

# @description Check GitHub CLI authentication status
# @exitcode 0 gh is authenticated
# @exitcode 1 gh is not authenticated or authentication check failed
check_gh_authentication() {
  # Check authentication status using gh auth status
  # Exit code 0 = authenticated, 1 = not authenticated or auth issues
  gh auth status >/dev/null 2>&1
  return $?
}

# @description Validate application exists and command name is safe
# @arg $1 string Command name
# @arg $2 string Application display name
# @exitcode 0 Command is valid and exists
# @exitcode 1 Command not found
# @exitcode 2 Invalid command name (contains shell metacharacters)
# @stderr Status messages
validate_app_exists() {
  local cmd="$1"
  local app_name="$2"

  # Security: Validate command name (reject shell metacharacters)
  # This prevents command injection via malicious app definitions
  #
  # Rejected: ; | & $ ` ( ) space tab (common injection vectors)
  # Intentionally allowed: / . - _ (for paths like /usr/bin/gh or ./bin/tool)
  # Design: Balance security with practicality for legitimate command names
  if [[ "$cmd" =~  [\;\|\&\$\`\(\)[:space:]] ]]; then
    return 2  # Special exit code for security error
  fi

  echo "Checking ${app_name}..." >&2

  if ! command -v "$cmd" &> /dev/null; then
    return 1  # Command not found
  fi

  return 0  # Valid and exists
}

# @description Validate application version
# @arg $1 string Command name
# @arg $2 string Application display name
# @arg $3 string Version extractor (field:N, regex:PATTERN, or empty)
# @arg $4 string Minimum required version (empty = skip check)
# @exitcode 0 Version meets requirements
# @exitcode 1 Version extraction failed
# @exitcode 2 Version below minimum requirement
# @stderr Version info and warnings
# @set VALIDATED_VERSION Full version string (on success)
# @set VALIDATED_VERSION_NUM Extracted version number (on version too low)
# @set VALIDATED_MIN_VERSION Required minimum version (on version too low)
validate_app_version() {
  local cmd="$1"
  local app_name="$2"
  local version_extractor="$3"
  local min_ver="$4"

  # Clear result globals
  VALIDATED_VERSION=""
  VALIDATED_VERSION_NUM=""
  VALIDATED_MIN_VERSION=""

  # Get full version string using helper function
  local version_string
  if ! version_string=$(get_app_version "$cmd"); then
    return 1  # Extraction failed
  fi

  echo "  ✓ ${version_string}" >&2
  echo "" >&2

  # Check minimum version if min_ver is specified
  if [ -n "$min_ver" ]; then
    # Extract version number from full version string
    local version_num
    if ! version_num=$(extract_version_number "$version_string" "$version_extractor"); then
      return 1  # Version number extraction failed
    fi

    # Validate version against minimum requirement
    if ! check_version "$version_num" "$min_ver"; then
      # Store error details in globals for caller
      VALIDATED_VERSION_NUM="$version_num"
      VALIDATED_MIN_VERSION="$min_ver"
      return 2  # Version too low (distinct exit code)
    fi
  else
    # Version check skipped (no extractor or min_version specified)
    echo "  ::warning::${app_name}: version check skipped (no minimum version specified)" >&2
  fi

  # Store success result in global (NOT stdout)
  VALIDATED_VERSION="$version_string"
  return 0
}

# @description Perform tool-specific validation checks (e.g., gh auth check)
# @arg $1 string Command name
# @arg $2 string Application display name
# @exitcode 0 Validation passed or no special check needed
# @exitcode 1 Validation failed
# @stderr Status messages and errors
# @set SPECIAL_VALIDATION_ERROR Detailed error message (on failure)
validate_app_special() {
  local cmd="$1"
  local app_name="$2"

  # Clear error message global
  SPECIAL_VALIDATION_ERROR=""

  case "$cmd" in
    gh)
      # GitHub CLI: Check authentication status
      echo "Checking ${app_name} authentication..." >&2

      if ! check_gh_authentication; then
        SPECIAL_VALIDATION_ERROR="${app_name} is not authenticated. Run 'gh auth login' to authenticate."
        echo "::error::${SPECIAL_VALIDATION_ERROR}" >&2
        return 1
      fi

      echo "  ✓ ${app_name} is authenticated" >&2
      echo "" >&2
      return 0
      ;;

    # Future extension points:
    #
    # docker)
    #   # Docker: Check daemon is running
    #   echo "Checking ${app_name} daemon..." >&2
    #   if ! docker info >/dev/null 2>&1; then
    #     SPECIAL_VALIDATION_ERROR="Docker daemon is not running. Start Docker Desktop or dockerd."
    #     echo "::error::${SPECIAL_VALIDATION_ERROR}" >&2
    #     return 1
    #   fi
    #   echo "  ✓ ${app_name} daemon is running" >&2
    #   echo "" >&2
    #   return 0
    #   ;;
    #
    # aws)
    #   # AWS CLI: Check credentials are configured
    #   echo "Checking ${app_name} credentials..." >&2
    #   if ! aws sts get-caller-identity >/dev/null 2>&1; then
    #     SPECIAL_VALIDATION_ERROR="AWS credentials not configured. Run 'aws configure'."
    #     echo "::error::${SPECIAL_VALIDATION_ERROR}" >&2
    #     return 1
    #   fi
    #   echo "  ✓ ${app_name} credentials configured" >&2
    #   echo "" >&2
    #   return 0
    #   ;;

    *)
      # No special validation needed for this command
      return 0
      ;;
  esac
}

# @description Validate applications from list (main validation loop)
# @arg $@ array Application definitions (cmd|app_name|version_extractor|min_version)
# @exitcode 0 All applications validated successfully
# @exitcode 1 One or more applications failed validation (fail-fast mode)
# @set VALIDATED_APPS Array of validated application names
# @set VALIDATED_VERSIONS Array of validated version strings
# @set VALIDATION_ERRORS Array of error messages (if FAIL_FAST=false)
# @set GITHUB_OUTPUT Writes status, message, validated_apps, validated_count, etc.
validate_apps() {
  local -a app_list=("$@")

  for app_def in "${app_list[@]}"; do
    # Parse app definition: cmd|app_name|version_extractor|min_version
    # Fixed 4-element format with pipe delimiter (no regex conflicts)
    local cmd app_name version_extractor min_ver
    IFS='|' read -r cmd app_name version_extractor min_ver <<EOF
$app_def
EOF

    # Validate application exists (includes security check)
    local exists_result=0
    validate_app_exists "$cmd" "$app_name" || exists_result=$?

    if [ $exists_result -ne 0 ]; then
      local error_msg

      if [ $exists_result -eq 2 ]; then
        # Security error: invalid command name
        error_msg="Invalid command name contains shell metacharacters: $cmd"
      else
        # Command not found
        error_msg="${app_name} is not installed"
      fi

      echo "::error::${error_msg}" >&2

      if [ "$FAIL_FAST" = "true" ]; then
        echo "status=error" >> "$GITHUB_OUTPUT_FILE"
        echo "message=${error_msg}" >> "$GITHUB_OUTPUT_FILE"
        exit 1
      else
        VALIDATION_ERRORS+=("${error_msg}")
        continue
      fi
    fi

    # Validate application version (uses exit code protocol + global variables)
    local version_check_result=0
    validate_app_version "$cmd" "$app_name" "$version_extractor" "$min_ver" || version_check_result=$?

    if [ $version_check_result -ne 0 ]; then
      local error_msg

      case $version_check_result in
        2)
          # Version too low - globals contain error details
          error_msg="${app_name} version ${VALIDATED_VERSION_NUM} is below minimum required ${VALIDATED_MIN_VERSION}"
          ;;
        *)
          # Version extraction failed (exit code 1 or other)
          error_msg="Failed to get version for ${app_name}"
          ;;
      esac

      echo "::error::${error_msg}" >&2

      if [ "$FAIL_FAST" = "true" ]; then
        echo "status=error" >> "$GITHUB_OUTPUT_FILE"
        echo "message=${error_msg}" >> "$GITHUB_OUTPUT_FILE"
        exit 1
      else
        VALIDATION_ERRORS+=("${error_msg}")
        continue
      fi
    fi

    # Store app name and version (VALIDATED_VERSION global contains the version string)
    VALIDATED_APPS+=("${app_name}")
    VALIDATED_VERSIONS+=("${VALIDATED_VERSION}")

    # Perform tool-specific validation (e.g., gh auth check, docker daemon, etc.)
    if ! validate_app_special "$cmd" "$app_name"; then
      # Get detailed error message from global, with fallback
      local error_msg="${SPECIAL_VALIDATION_ERROR:-Special validation failed for ${app_name}}"

      if [ "$FAIL_FAST" = "true" ]; then
        echo "status=error" >> "$GITHUB_OUTPUT_FILE"
        echo "message=${error_msg}" >> "$GITHUB_OUTPUT_FILE"
        exit 1
      else
        VALIDATION_ERRORS+=("${error_msg}")
        continue
      fi
    fi
  done
}

echo "=== Validating Required Applications ==="
echo ""

# Default application definitions: cmd|app_name|version_extractor|min_version
# Format: "command|app_name|version_extractor|min_version"
# - command: The command to check (e.g., "git", "curl")
# - app_name: Display name for the application (e.g., "Git", "curl")
# - version_extractor: Safe extraction method (NO EVAL):
#     * field:N = Extract Nth field (space-delimited, 1-indexed)
#     * regex:PATTERN = sed -E regex with capture group (\1)
#     * Empty string = auto-extract semver (X.Y or X.Y.Z)
# - min_version: Minimum required version (triggers ERROR and exit 1 if lower)
#     * Empty string = skip version check
#
# Delimiter: | (pipe) to avoid conflicts with regex patterns
#
# Examples:
#   "git|Git|field:3|2.30"                              - Extract 3rd field, check min 2.30
#   "curl|curl||"                                       - No version check (both empty)
#   "gh|gh|regex:version ([0-9.]+)|2.0"                 - sed regex with capture group
#   "node|Node.js|regex:v([0-9.]+)|18.0"                - Extract after 'v' prefix
#
# Security advantages:
#   - NO eval usage - prevents arbitrary code execution
#   - sed only - safe and standard
#   - Prefix-typed extractors (field:/regex:) - explicit and auditable
#   - Pipe delimiter - no conflict with regex patterns or colons
declare -a DEFAULT_APPS=(
  "git|Git|field:3|2.30"                   # Extract 3rd field, check min 2.30
  "curl|curl||"                            # No version check
)

# Always check default apps, add command line arguments if provided
declare -a APPS=("${DEFAULT_APPS[@]}")
if [ $# -gt 0 ]; then
  APPS+=("$@")
fi

# Validate all applications (populates VALIDATED_VERSIONS and VALIDATION_ERRORS arrays)
validate_apps "${APPS[@]}"

# Check for collected errors (in collect-errors mode)
if [ ${#VALIDATION_ERRORS[@]} -gt 0 ]; then
  echo "=== Application validation failed ==="
  echo "::error::Application validation failed with ${#VALIDATION_ERRORS[@]} error(s):"

  # Extract failed app names from error messages
  # IMPORTANT: This extraction depends on error message format
  # If you change error messages in validate_apps(), update this regex pattern
  # Current patterns: " is not installed", " version", "Special validation failed for"
  declare -a FAILED_APPS=()
  for error in "${VALIDATION_ERRORS[@]}"; do
    echo "::error::  - ${error}"
    # Extract app name from error message (before " is not installed" or " version")
    # Note: This may not extract correctly for all error types (e.g., "Special validation failed for X")
    failed_app=$(echo "$error" | sed -E 's/ (is not installed|version).*//')
    FAILED_APPS+=("$failed_app")
  done

  # Combine all errors into a single message with newlines and 2-space indentation
  declare -a indented_errors=()
  for error in "${VALIDATION_ERRORS[@]}"; do
    indented_errors+=("  ${error}")
  done

  IFS=$'\n'
  error_summary="${indented_errors[*]}"
  IFS=' '  # Reset IFS

  # Machine-readable output for GitHub Actions
  echo "status=error" >> "$GITHUB_OUTPUT_FILE"
  # Use GitHub Actions multiline string format
  cat >> "$GITHUB_OUTPUT_FILE" <<EOF
message<<MULTILINE_EOF
Application validation failed:
${error_summary}
MULTILINE_EOF
EOF

  # Additional structured outputs
  IFS=','
  echo "failed_apps=${FAILED_APPS[*]}" >> "$GITHUB_OUTPUT_FILE"
  IFS=' '  # Reset IFS
  echo "failed_count=${#FAILED_APPS[@]}" >> "$GITHUB_OUTPUT_FILE"
  echo "validated_count=${#VALIDATED_APPS[@]}" >> "$GITHUB_OUTPUT_FILE"

  exit 1
fi

# Create human-readable summary message with 2-space indentation
declare -a summary_parts=()
for i in "${!VALIDATED_APPS[@]}"; do
  summary_parts+=("  ${VALIDATED_APPS[$i]} ${VALIDATED_VERSIONS[$i]}")
done

# Use newline as separator for better readability
IFS=$'\n'
all_versions="${summary_parts[*]}"
IFS=' '  # Reset IFS

echo "=== Application validation passed ==="

# Machine-readable output for GitHub Actions
echo "status=success" >> "$GITHUB_OUTPUT_FILE"
# Use GitHub Actions multiline string format
cat >> "$GITHUB_OUTPUT_FILE" <<EOF
message<<MULTILINE_EOF
Applications validated:
${all_versions}
MULTILINE_EOF
EOF

# Additional structured outputs (use structured arrays directly)
IFS=','
echo "validated_apps=${VALIDATED_APPS[*]}" >> "$GITHUB_OUTPUT_FILE"
IFS=' '  # Reset IFS
echo "validated_count=${#VALIDATED_APPS[@]}" >> "$GITHUB_OUTPUT_FILE"
echo "failed_count=0" >> "$GITHUB_OUTPUT_FILE"

exit 0
