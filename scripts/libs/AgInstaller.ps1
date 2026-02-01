# src: /scripts/libs/AgInstaller.ps1
# @(#) : Package installer library
#
# Copyright (c) 2025 Furukawa Atsushi <atsushifx@gmail.com>
# Released under the MIT License.

#
# @file AgInstaller.ps1
# @brief Package installer library for multiple package managers
# @description
#   Provides unified installation functions for winget, scoop, and pnpm package managers.
#   Each function accepts package lists via parameter or pipeline, filters comments,
#   and performs batch installation with error handling.
#
#   Supported Package Managers:
#   - winget: Windows Package Manager with custom installation paths
#   - scoop: Command-line installer for Windows
#   - pnpm: Fast, disk space efficient package manager
#
# @author Furukawa Atsushi
# @version 1.0.0
# @license MIT

<#
.SYNOPSIS
    Build winget install parameters from package specification

.DESCRIPTION
    Parses "name,id" format string and returns --id and --location arguments
    for winget install command. Installation path is set to c:/app/develop/utils/<name>.

.PARAMETER Package
    Package specification in "name,id" format (e.g., "git,Git.Git")

.OUTPUTS
    String array containing --id, <id>, --location, <path> arguments

.EXAMPLE
    AgInstaller-WinGetBuildParams -Package "git,Git.Git"
    # Returns: @("--id", "Git.Git", "--location", "c:/app/develop/utils/git")
#>
function AgInstaller-WinGetBuildParams {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Package
    )
    ($name, $id) = $Package.Split(",").trim()
    return @("--id", $id, "--location", "c:/app/develop/utils/$name")
}

<#
.SYNOPSIS
    Install packages in batch via winget

.DESCRIPTION
    Accepts package list in "name,id" format via parameter or pipeline and installs
    them using winget. Automatically filters out empty lines and comments (lines starting with #).
    Each package is installed to c:/app/develop/utils/<name> directory.

.PARAMETER Packages
    Array of package specifications in "name,id" format (e.g., "git,Git.Git")
    Can be provided via pipeline

.EXAMPLE
    Install-WinGetPackages -Packages @("git,Git.Git", "7zip,7zip.7zip")

.EXAMPLE
    "7zip,7zip.7zip" | Install-WinGetPackages

.EXAMPLE
    @("git,Git.Git", "vscode,Microsoft.VisualStudioCode") | Install-WinGetPackages
#>
function Install-WinGetPackages {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$Packages
    )

    begin { $pkgList = @() }
    process {
        foreach ($pkg in $Packages) {
            if ($pkg -and ($pkg -notmatch '^\s*#')) {
                $pkgList += $pkg
            }
        }
    }
    end {
        if ($pkgList.Count -eq 0) {
            Write-Warning " No valid packages to install via winget."
            return
        }

        foreach ($pkg in $pkgList) {
            $args = AgInstaller-WinGetBuildParams -Package $pkg
            Write-Host " Installing $pkg → winget $($args -join ' ')" -ForegroundColor Cyan
            $args2 = @("install") + $args
            try {
                Start-Process "winget" -ArgumentList $args2 -Wait -NoNewWindow -ErrorAction Stop
            } catch {
                Write-Warning "❌ Installation failed: $pkg"
            }
        }
        Write-Host "✅ winget packages installed." -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Install development tools via scoop

.DESCRIPTION
    Accepts package list via parameter or pipeline and installs them using scoop.
    Automatically filters out empty lines and comments (lines starting with #).

.PARAMETER Tools
    Array of scoop package names
    Can be provided via pipeline

.EXAMPLE
    Install-ScoopPackages -Tools @("git", "dprint")

.EXAMPLE
    "gitleaks" | Install-ScoopPackages

.EXAMPLE
    @("lefthook", "dprint", "gitleaks") | Install-ScoopPackages
#>
function Install-ScoopPackages {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$Tools
    )

    begin { $toolList = @() }
    process {
        foreach ($tool in $Tools) {
            if ($tool -and ($tool -notmatch '^\s*#')) {
                $toolList += $tool
            }
        }
    }
    end {
        if ($toolList.Count -eq 0) {
            Write-Warning " No valid tools to install via scoop."
            return
        }

        foreach ($tool in $toolList) {
            Write-Host " Installing: $tool" -ForegroundColor Cyan
            scoop install $tool
        }
        Write-Host "✅ Scoop tools installed." -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Install packages globally via pnpm

.DESCRIPTION
    Accepts package list via parameter or pipeline and installs them globally using pnpm.
    Automatically filters out empty lines and comments (lines starting with #).
    All packages are installed with single 'pnpm add --global' command for efficiency.

.PARAMETER Packages
    Array of npm package names to install globally
    Can be provided via pipeline

.EXAMPLE
    Install-PnpmPackages -Packages @("cspell", "secretlint")

.EXAMPLE
    "cspell" | Install-PnpmPackages

.EXAMPLE
    @("commitlint", "@commitlint/cli", "secretlint") | Install-PnpmPackages
#>
function Install-PnpmPackages {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$Packages
    )

    begin { $pkgList = @() }
    process {
        foreach ($pkg in $Packages) {
            if ($pkg -and ($pkg -notmatch '^\s*#')) {
                $pkgList += $pkg
            }
        }
    }
    end {
        if ($pkgList.Count -eq 0) {
            Write-Warning " No valid packages to install."
            return
        }

        $cmd = "pnpm add --global " + ($pkgList -join " ")
        Write-Host " Installing via pnpm: $cmd" -ForegroundColor Cyan
        Invoke-Expression $cmd
        Write-Host "✅ pnpm packages installed." -ForegroundColor Green
    }
}

<#
.SYNOPSIS
    Clone Git repositories in batch

.DESCRIPTION
    Accepts repository list in "url,path" format via parameter or pipeline and clones
    them using git. Automatically filters out empty lines and comments (lines starting with #).
    Creates parent directories if they don't exist.

.PARAMETER Repositories
    Array of repository specifications in "url,path" format
    Can be provided via pipeline

.EXAMPLE
    Install-GitRepositories -Repositories @("https://github.com/shellspec/shellspec.git,.tools/shellspec")

.EXAMPLE
    "https://github.com/shellspec/shellspec.git,.tools/shellspec" | Install-GitRepositories

.EXAMPLE
    @("https://github.com/shellspec/shellspec.git,.tools/shellspec") | Install-GitRepositories
#>
function Install-GitRepositories {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline = $true)]
        [string[]]$Repositories
    )

    begin { $repoList = @() }
    process {
        foreach ($repo in $Repositories) {
            if ($repo -and ($repo -notmatch '^\s*#')) {
                $repoList += $repo
            }
        }
    }
    end {
        if ($repoList.Count -eq 0) {
            Write-Warning " No valid repositories to clone."
            return
        }

        foreach ($repo in $repoList) {
            ($url, $path) = $repo.Split(",").Trim()

            # Create parent directory if it doesn't exist
            $parentDir = Split-Path -Parent $path
            if ($parentDir -and -not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }

            # Clone repository if it doesn't exist
            if (Test-Path $path) {
                Write-Host " Already exists: $path (skipping)" -ForegroundColor Yellow
            } else {
                Write-Host " Cloning: $url → $path" -ForegroundColor Cyan
                try {
                    git clone $url $path
                    Write-Host " ✅ Cloned successfully: $path" -ForegroundColor Green
                } catch {
                    Write-Warning "❌ Clone failed: $url"
                }
            }
        }
        Write-Host "✅ Git repositories processed." -ForegroundColor Green
    }
}

