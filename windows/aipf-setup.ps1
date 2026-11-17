#requires -Version 5.1
<# AIPF Stage 0: local reviewed files only. Does not download or execute project code. #>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Login,
    [switch]$InstallPython,
    [switch]$SkipLauncher
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Has([string]$Command) { return [bool](Get-Command $Command -ErrorAction SilentlyContinue) }
function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('PATH','Machine')
    $user = [Environment]::GetEnvironmentVariable('PATH','User')
    $env:PATH = @($machine,$user,$env:PATH) -join ';'
}
function External([string]$Executable,[string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "COMMAND_FAILED: $Executable exit=$LASTEXITCODE" }
}
function Ensure-Tool([string]$Command,[string]$Package) {
    if (Has $Command) { Write-Host "TOOL_$Command=OK"; return }
    if (-not $Apply) { Write-Host "PLAN_INSTALL: $Package"; return }
    if (-not (Has winget)) { throw "BLOCKED_WINGET_UNAVAILABLE: $Package" }
    External winget @('install','--id',$Package,'-e','--source','winget','--accept-source-agreements','--accept-package-agreements')
    Refresh-Path
    if (-not (Has $Command)) { throw "BLOCKED_INSTALL_OR_PATH: $Command (restart PowerShell and retry)" }
}
function Install-Launcher {
    $source = $PSScriptRoot
    $target = if ($env:AIPF_BIN_DIR) { $env:AIPF_BIN_DIR } else { Join-Path $env:LOCALAPPDATA 'AIPF\bin' }
    if (-not $Apply) { Write-Host "PLAN_LAUNCHER: $target"; return }
    foreach ($name in @('aipf.cmd','aipf.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf)) { throw "BLOCKED_LAUNCHER_SOURCE_MISSING: $name" }
    }
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($name in @('aipf.cmd','aipf.ps1')) {
        $temp = Join-Path $target ('.' + $name + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
        $dest = Join-Path $target $name
        try {
            Copy-Item -LiteralPath (Join-Path $source $name) -Destination $temp -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $dest -Force -ErrorAction Stop
        } finally {
            if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
        }
    }
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $parts = @($userPath -split ';' | Where-Object { $_ })
    if (-not ($parts | Where-Object { $_.TrimEnd('\') -ieq $target.TrimEnd('\') })) {
        [Environment]::SetEnvironmentVariable('Path',(($parts + $target) -join ';'),'User')
    }
    if (-not (($env:Path -split ';') | Where-Object { $_.TrimEnd('\') -ieq $target.TrimEnd('\') })) {
        $env:Path = "$target;$env:Path"
    }
    Write-Host "LAUNCHER_INSTALLED: $dest"
    External (Join-Path $target 'aipf.cmd') @('version')
}
Write-Host 'AIPF Bootstrap 0 (development / no signed release)'
Write-Host $(if ($Apply) { 'MODE=APPLY' } else { 'MODE=PLAN' })
Ensure-Tool git 'Git.Git'
Ensure-Tool gh 'GitHub.cli'
if ($InstallPython) { Ensure-Tool py 'Python.Python.3.11' }
if (-not $SkipLauncher) { Install-Launcher }
if ($Login) {
    if (-not $Apply) { Write-Host 'PLAN_AUTH: gh auth login --web' }
    else {
        if (-not (Has gh)) { throw 'BLOCKED_GH_UNAVAILABLE' }
        & gh auth status --hostname github.com *> $null
        if ($LASTEXITCODE -ne 0) { External gh @('auth','login','--hostname','github.com','--git-protocol','https','--web') }
        External gh @('auth','setup-git')
        External gh @('auth','status','--hostname','github.com')
    }
}
Write-Host $(if ($Apply) { 'STAGE0_APPLY_DONE' } else { 'STAGE0_PLAN_DONE' })
Write-Host 'STAGE2_PENDING: private profile manifest and project boot not yet supported'
