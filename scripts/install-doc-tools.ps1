# src: /scripts/install-doc-tools.ps1
# @(#) : Document linting and writing tools installation script
#
# Copyright (c) 2025 Furukawa Atsushi <atsushifx@gmail.com>
# Released under the MIT License.
# https://opensource.org/licenses/MIT
#
# @file install-doc-tools.ps1
# @brief Install documentation and writing tools with configuration
# @description
#   Installs comprehensive documentation linting and writing support tools for Japanese and English.
#   Includes textlint with language-specific rules, markdownlint, and spell checker with configuration.
#
#   **Installed tools:**
#   - textlint: Japanese/English writing rule checker
#   - markdownlint-cli2: Markdown linting
#   - cspell: Spell checker for code and documentation
#
#   **Configuration:**
#   - Copies .textlintrc.yaml, .markdownlint.yaml, .textlint/, and .vscode/ from templates
#
# @param $TemplateDir Template directory path (default: "./templates")
# @param $DestinationDir Destination root directory (default: ".")
#
# @example
#   .\install-doc-tools.ps1
#   # Installs all writing tools with default template directory
#
#   .\install-doc-tools.ps1 -TemplateDir "./custom-templates" -DestinationDir "."
#   # Installs from custom template location
#
# @exitcode 0 Success
# @exitcode 1 Error during installation
#
# @author atsushifx
# @version 1.4.2
# @license MIT

<#
.SYNOPSIS
    Install textlint, markdownlint, cspell for writers, and copy configuration files

.DESCRIPTION
    This script installs writing and documentation tools with comprehensive rule sets:

    **Installed tools:**
    - textlint: Advanced writing rule checker with Japanese language support
    - markdownlint-cli2: Markdown format and style checker
    - cspell: Multi-language spell checker

    **Installation flow:**
    1. Install textlint with Japanese and AI writing rules
    2. Install markdownlint-cli2 for markdown validation
    3. Install cspell for spell checking
    4. Copy configuration files from template directory to project

.PARAMETER TemplateDir
    Template directory containing configuration files.
    Default: "./templates"

.PARAMETER DestinationDir
    Root destination directory for configuration files.
    Configs will be copied to: $DestinationDir/configs/
    Exception: .vscode will be copied to $DestinationDir/.vscode/
    Default: "."

.NOTES
    @Version  1.4.2
    @Author   atsushifx <https://github.com/atsushifx>
    @Since    2025-06-12
    @License  MIT https://opensource.org/licenses/MIT
#>

# ============================================================================
# Parameters
# ============================================================================

##
# @description Template directory containing configuration files
# @var string path to template directory
Param (
    [string]$TemplateDir = "./templates",
    [string]$DestinationDir = "."
)

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
# @description List of textlint packages and rules to install
# @details
#   Includes:
#   - Core textlint engine
#   - Filter rules for allowlist and comments
#   - Japanese technical writing rules
#   - Japanese spacing rules
#   - AI writing enhancement rules
#   - Spell checking and proofreading rules
#
# @var array npm package names for textlint ecosystem
$TextlintPackages = @(
    # Core textlint engine and utilities
    "textlint",
    "textlint-filter-rule-allowlist",
    "textlint-filter-rule-comments",

    # Japanese technical writing rules
    "textlint-rule-preset-ja-technical-writing",
    "textlint-rule-preset-ja-spacing",
    "@textlint-ja/textlint-rule-preset-ai-writing",
    "textlint-rule-ja-no-orthographic-variants",
    "@textlint-ja/textlint-rule-no-synonyms",
    "sudachi-synonyms-dictionary",
    "@textlint-ja/textlint-rule-morpheme-match",
    "textlint-rule-ja-hiraku",
    "textlint-rule-no-mixed-zenkaku-and-hankaku-alphabet",

    # Common misspelling and proofreading
    "textlint-rule-common-misspellings",
    "@proofdict/textlint-rule-proofdict",
    "textlint-rule-prh",

    # Markdown linting
    "markdownlint-cli2",

    # Spell checking
    "cspell"
)

##
# @description Configuration files to copy from template
# @details
#   Copies the following:
#   - .textlintrc.yaml: textlint configuration
#   - .textlint/: textlint custom rules and dictionaries directory
#   - .markdownlint.yaml: markdown linting rules
#   - .vscode/: VSCode extensions and settings
#
# @var array relative paths of config files/directories
$ConfigFilesToCopy = @(
    # textlint settings and rules
    ".textlintrc.yaml",
    ".textlint",

    # markdownlint
    ".markdownlint.yaml",

    # VSCode settings and extensions (special case: copies to root .vscode)
    ".vscode"
)

# ============================================================================
# Functions
# ============================================================================

##
# @description Copy linter configuration files from template to destination
# @details
#   **Behavior:**
#   - Creates configs directory if it doesn't exist
#   - Copies specified files/directories from template
#   - .vscode is special-cased to copy to root instead of configs/
#   - Skips already existing files
#   - Validates source files exist before copying
#
# @param $Items Files or directories to copy (pipeline/parameter input)
# @param $TemplateDir Source template directory path
# @param $DestinationDir Target root directory path
#
# @example
#   @(".textlintrc.yaml", ".markdownlint.yaml") | Copy-LinterConfigs -TemplateDir "./templates"
#
# @example
#   Copy-LinterConfigs -Items @(".textlint", ".vscode") -TemplateDir "./templates"
#
function Copy-LinterConfigs {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$Items,

        [string]$TemplateDir = "./templates",
        [string]$DestinationDir = "."
    )

    begin {
        $targets = @()
    }

    process {
        foreach ($i in $Items) {
            # Filter out comments and empty items
            if ($i -and ($i -notmatch '^\s*#')) {
                $targets += $i
            }
        }
    }

    end {
        # Create configs directory if needed
        $configPath = Join-Path $DestinationDir "configs"
        if (-not (Test-Path $configPath)) {
            New-Item -Path $configPath -ItemType Directory | Out-Null
            Write-Host "[Created] Configs directory: $configPath"
        }

        # Copy each configuration file/directory
        foreach ($item in $targets) {
            $src = Join-Path $TemplateDir $item

            # Special handling for .vscode: copy to root instead of configs/
            $dstBase = if ($item -ieq ".vscode") {
                $DestinationDir
            } else {
                Join-Path $DestinationDir "configs"
            }

            $dst = Join-Path $dstBase $item

            if (Test-Path $src) {
                if (-not (Test-Path $dst)) {
                    if ((Get-Item $src).PSIsContainer) {
                        Write-Host "[Copy] Copying directory: $item -> $dst"
                        robocopy $src $dst /E /NFL /NDL /NJH /NJS /NC /NS | Out-Null
                        Write-Host "[OK] Directory copied: $item"
                    } else {
                        Copy-Item $src -Destination $dst
                        Write-Host "[Copy] Copied file: $item -> $dst"
                    }
                } else {
                    Write-Host "[Skip] Skipped (exists): $item"
                }
            } else {
                Write-Warning "[Error] Not found in templates: $item"
            }
        }
    }
}

##
# @description Main installation routine for writing environment setup
# @details
#   **Execution flow:**
#   1. Install textlint packages via pnpm
#   2. Install markdownlint-cli2 via pnpm
#   3. Install cspell via pnpm
#   4. Validate template directory exists
#   5. Copy configuration files to destination
#   6. Report completion
#
# @return 0 Always succeeds
# @global $TextlintPackages Array of textlint packages to install
# @global $ConfigFilesToCopy Array of config files to copy
# @global $TemplateDir Template source directory
# @global $DestinationDir Configuration destination directory
#
function Install-WritingEnvironment {
    Write-Host "[Installing] writer tooling..." -ForegroundColor Green

    # Install all writing tools via pnpm
    Write-Host "Installing textlint packages..." -ForegroundColor Cyan
    $TextlintPackages | Install-PnpmPackages

    # Copy configuration files if template exists
    if (Test-Path $TemplateDir) {
        Write-Host "Copying configuration files..." -ForegroundColor Cyan
        $ConfigFilesToCopy | Copy-LinterConfigs -TemplateDir $TemplateDir -DestinationDir $DestinationDir
    } else {
        Write-Host "[Warning] Template directory not found: $TemplateDir. Skipping config copy." -ForegroundColor Yellow
    }

    Write-Host "[OK] Writer environment setup completed." -ForegroundColor Green
}

# ============================================================================
# Main Execution
# ============================================================================

Install-WritingEnvironment
