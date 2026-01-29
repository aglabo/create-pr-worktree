# src: /scripts/install-dev-tools.ps1
# @(#) : Development tools installation script
#
# Copyright (c) 2025 Furukawa Atsushi <atsushifx@gmail.com>
# Released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file install-dev-tools.ps1
# @brief Install development support tools in batch
# @description
#   Automatically installs multiple development support tools using package managers
#   (winget, scoop, pnpm, eget) to streamline development environment setup.
#
#   Features:
#   - Batch installation of multiple tools across different package managers
#   - Automatic fallback installation of eget if not available
#   - Organized tool list by package manager type
#   - Error handling and validation
#
# @example
#   .\install-dev-tools.ps1
#   # Installs all configured development tools
#
# @exitcode 0 Success
# @exitcode 1 Error during installation
#
# @author atsushifx
# @version 1.3.2
# @license MIT

<#
.SYNOPSIS
    Installs development support tools in batch

.DESCRIPTION
    This script installs multiple development support tools using package managers such as
    winget, scoop, pnpm, and eget. It provides a convenient way to set up a complete
    development environment in one command.

    **Installation flow:**
    1. Verify eget is installed (fallback to winget if needed)
    2. Install winget packages
    3. Install scoop packages
    4. Install pnpm packages
    5. Install eget packages

.NOTES
    @Version  1.3.2
    @Since    2025-06-12
    @Author   atsushifx
    @License  MIT
#>

# ============================================================================
# Setup
# ============================================================================

Set-StrictMode -Version Latest

. "$PSScriptRoot/common/init.ps1"
. "$SCRIPT_ROOT/libs/AgInstaller.ps1"

# ============================================================================
# Configuration
# ============================================================================

##
# @description WinGet packages to install
# @var array of package specifications (packageName, packageId)
$WinGetPackages = @(
    # Environment variable manager for managing .env files
    "dotenvx, dotenvx.dotenvx"
)

##
# @description Scoop packages to install
# @var array of package names
$ScoopPackages = @(
    # Git hook manager for managing pre-commit, pre-push hooks
    "lefthook",
    # Code formatter supporting multiple languages
    "dprint",
    # Secret information scanner to detect credentials in code
    "gitleaks"
)

##
# @description npm packages to install via pnpm
# @var array of npm package names
$PnpmPackages = @(
    # Commit message checker - validates conventional commits format
    "commitlint",
    "@commitlint/cli",
    "@commitlint/config-conventional",
    "@commitlint/types",

    # Secret information leak checker - scans for sensitive data
    "secretlint",
    "@secretlint/secretlint-rule-preset-recommend",

    # Spell checker for code and documentation
    "cspell",

    # AI agent - Claude Code CLI for AI-assisted development
    "@anthropic/claude-code",
)

##
# @description Eget packages to install
# @var array of eget package specifications (packageName, gitHubRepo)
$EgetPackages = @(
    "codegpt, appleboy/codegpt"
)

# ============================================================================
# Functions
# ============================================================================

##
# @description Install development tools using configured package managers
# @details
#   Executes installation pipeline:
#   1. Ensures eget is available (installs via winget if needed)
#   2. Installs winget, scoop, pnpm, and eget packages sequentially
#   3. Reports completion status
#
# @return 0 Always succeeds (errors reported but don't stop execution)
# @global $WinGetPackages Array of winget packages to install
# @global $ScoopPackages Array of scoop packages to install
# @global $PnpmPackages Array of pnpm packages to install
# @global $EgetPackages Array of eget packages to install
# @example
#   Install-DevelopmentTools
function Install-DevelopmentTools {
    if (!(commandExists "eget")) {
        Write-Warning "eget is not installed."
        Install-WinGetPackages "eget,ZacharyYedidia.Eget"
    }

    # Install packages from each package manager
    Write-Host "Installing WinGet packages..." -ForegroundColor Cyan
    $WinGetPackages | Install-WinGetPackages

    Write-Host "Installing Scoop packages..." -ForegroundColor Cyan
    $ScoopPackages | Install-ScoopPackages

    Write-Host "Installing pnpm packages..." -ForegroundColor Cyan
    $PnpmPackages | Install-PnpmPackages

    Write-Host "Installing Eget packages..." -ForegroundColor Cyan
    $EgetPackages | Install-EgetPackages
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host "[Starting] development tool setup..." -ForegroundColor Green
Install-DevelopmentTools
Write-Host "[Done]" -ForegroundColor Green
