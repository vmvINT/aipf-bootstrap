#requires -Version 5.1
<#
.SYNOPSIS
 AIPF Bootstrap 0 for clean Windows. No Git, gh, Python or AIPF needed initially.
.DESCRIPTION
 -Plan shows planned changes and does not install.
 -Apply installs missing prerequisites using the already-present WinGet with explicit approval.
 No private repository addresses, secrets, or production actions are embedded.
 This is Stage 0 only: project-specific boot is performed by a separate, authenticated Stage 2.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Login,
    [switch]$InstallPython
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Has([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('PATH','Machine')
    $user = [Environment]::GetEnvironmentVariable('PATH','User')
    $env:PATH = (($machine,$user,$env:PATH) | Where-Object { $_ }) -join ';'
}
function Run-External([string]$File,[string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "COMMAND_FAILED: $File exit=$LASTEXITCODE" }
}
function Ensure-Tool([string]$Command,[string]$Package) {
    if (Has $Command) {
        Write-Host "OK: $Command"
        return
    }
    if (-not $Apply) {
        Write-Host "MISSING: $Command; plan: winget install --id $Package -e"
        return
    }
    if (-not (Has 'winget')) { throw "BLOCKED_NO_WINGET: $Command. Use your organization's approved package source or the verified offline package." }
    Write-Host "INSTALL: $Package"
    Run-External 'winget' @('install','--id',$Package,'-e','--source','winget','--accept-source-agreements','--accept-package-agreements')
    Refresh-Path
    if (-not (Has $Command)) {
        throw "BLOCKED_PATH_OR_INSTALL: $Command. Reopen PowerShell and run the same command."
    }
}
Write-Host "AIPF Bootstrap 0 / Windows (no project payload)"
Write-Host ("MODE: " + $(if ($Apply) {'APPLY'} else {'PLAN'}))
Write-Host "OS: $([Environment]::OSVersion.VersionString)"
Ensure-Tool 'git' 'Git.Git'
Ensure-Tool 'gh' 'GitHub.cli'
if ($InstallPython) { Ensure-Tool 'py' 'Python.Python.3.11' }
if ($Login) {
    if (-not $Apply) {
        Write-Host 'PLAN: GitHub browser/device authentication if required'
    } else {
        if (-not (Has 'gh')) { throw 'BLOCKED_GH_NOT_AVAILABLE' }
        & gh auth status --hostname github.com *> $null
        if ($LASTEXITCODE -ne 0) {
            Run-External 'gh' @('auth','login','--hostname','github.com','--git-protocol','https','--web')
        }
        Run-External 'gh' @('auth','setup-git')
        Run-External 'gh' @('auth','status','--hostname','github.com')
    }
}
Write-Host $(if ($Apply) {'STAGE0_PREREQUISITES_DONE'} else {'STAGE0_PLAN_DONE'})
Write-Host 'NEXT: authenticated, pinned private project manifest + private project installer (not included in Stage 0)'
