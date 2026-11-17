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

# WinGet-less Windows/LTSC fallback. Official GitHub release packages are
# verified with a SHA-256 digest supplied by publisher release metadata/checksums.
function Add-UserToolPath([string]$Dir) {
    $current = @($env:Path -split ';' | Where-Object { $_ })
    if (-not ($current | Where-Object { $_.TrimEnd('\\') -ieq $Dir.TrimEnd('\\') })) { $env:Path = "$Dir;$env:Path" }
    $user = [Environment]::GetEnvironmentVariable('Path','User')
    $entries = @($user -split ';' | Where-Object { $_ })
    if (-not ($entries | Where-Object { $_.TrimEnd('\\') -ieq $Dir.TrimEnd('\\') })) {
        [Environment]::SetEnvironmentVariable('Path', (($entries + $Dir) -join ';'), 'User')
    }
}
function Get-OfficialRelease([string]$Repo,[string]$AssetPattern) {
    $headers = @{ 'User-Agent'='AIPF-Bootstrap'; 'Accept'='application/vnd.github+json' }
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -UseBasicParsing
    $hits = @($rel.assets | Where-Object { $_.name -match $AssetPattern })
    if ($hits.Count -ne 1) { throw "BLOCKED_RELEASE_ASSET_NOT_UNIQUE: $Repo" }
    return @{ Release=$rel; Asset=$hits[0] }
}
function Download-VerifiedRelease([string]$Repo,[string]$Pattern,[string]$Destination) {
    $selected = Get-OfficialRelease $Repo $Pattern
    $asset = $selected.Asset
    $digest = [string]$asset.digest
    if ($digest -notmatch '^sha256:([a-fA-F0-9]{64})$') {
        $lists = @($selected.Release.assets | Where-Object { $_.name -match '(?i)(checksums|sha256sums).*\.txt$' })
        if ($lists.Count -ne 1) { throw "BLOCKED_NO_RELEASE_DIGEST: $Repo/$($asset.name)" }
        $text = (Invoke-WebRequest -Uri $lists[0].browser_download_url -UseBasicParsing).Content
        $escaped = [regex]::Escape([string]$asset.name)
        $line = @($text -split '\r?\n' | Where-Object { $_ -match ("(?i)^([a-f0-9]{64})\s+\*?" + $escaped + "$") })
        if ($line.Count -ne 1) { throw "BLOCKED_CHECKSUM_ENTRY: $Repo/$($asset.name)" }
        $null = $line[0] -match '^([a-fA-F0-9]{64})'
        $wanted = $Matches[1].ToLowerInvariant()
    } else { $wanted = $Matches[1].ToLowerInvariant() }
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $Destination -UseBasicParsing
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $wanted) { throw "BLOCKED_RELEASE_SHA256_MISMATCH: $Repo" }
}
function Install-Portable([string]$Tool) {
    if ([Environment]::Is64BitOperatingSystem -ne $true -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        throw "BLOCKED_UNSUPPORTED_ARCHITECTURE: $env:PROCESSOR_ARCHITECTURE"
    }
    $base = Join-Path $env:LOCALAPPDATA 'AIPF\\tools'
    $stage = Join-Path ([IO.Path]::GetTempPath()) ('aipf-tool-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    try {
        if ($Tool -eq 'git') {
            $zip=Join-Path $stage 'git.zip'
            Download-VerifiedRelease 'git-for-windows/git' '^MinGit-.*-64-bit\.zip$' $zip
            $dest = Join-Path $base 'git'
            $expanded = Join-Path $stage 'expanded'
            Expand-Archive -LiteralPath $zip -DestinationPath $expanded
            $exe = Join-Path $expanded 'cmd\\git.exe'
            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'BLOCKED_GIT_PORTABLE_LAYOUT' }
            New-Item -ItemType Directory -Force -Path $base | Out-Null
            if (-not (Test-Path -LiteralPath $dest)) {
                Move-Item -LiteralPath $expanded -Destination $dest
            }
            Add-UserToolPath (Join-Path $dest 'cmd')
            if (-not (Has git)) { throw 'BLOCKED_GIT_PATH' }
        } elseif ($Tool -eq 'gh') {
            $zip=Join-Path $stage 'gh.zip'
            Download-VerifiedRelease 'cli/cli' '^gh_.*_windows_amd64\.zip$' $zip
            $expanded = Join-Path $stage 'expanded'
            Expand-Archive -LiteralPath $zip -DestinationPath $expanded
            $candidates=@(Get-ChildItem -LiteralPath $expanded -Filter 'gh.exe' -File -Recurse)
            if ($candidates.Count -ne 1) { throw 'BLOCKED_GH_PORTABLE_LAYOUT' }
            $dest = Join-Path $base 'gh'
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            Copy-Item -LiteralPath $candidates[0].FullName -Destination (Join-Path $dest 'gh.exe') -Force
            Add-UserToolPath $dest
            if (-not (Has gh)) { throw 'BLOCKED_GH_PATH' }
        } else { throw 'INVALID_PORTABLE_TOOL' }
    } finally {
        if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
function Ensure-Python311 {
    if (Has py) {
        & py -3.11 --version *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host 'TOOL_py=OK'; return }
    }
    if (-not $Apply) { Write-Host 'PLAN_INSTALL: Python 3.11.9 official per-user installer'; return }
    $download=Join-Path ([IO.Path]::GetTempPath()) ('aipf-python-'+[guid]::NewGuid().ToString('N')+'.exe')
    try {
        Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe' -OutFile $download -UseBasicParsing
        $signature=Get-AuthenticodeSignature -LiteralPath $download
        if ($signature.Status -ne 'Valid' -or [string]$signature.SignerCertificate.Subject -notmatch 'Python Software Foundation') {
            throw 'BLOCKED_PYTHON_AUTHENTICODE'
        }
        $process=Start-Process -FilePath $download -ArgumentList @('/quiet','InstallAllUsers=0','Include_launcher=1','InstallLauncherAllUsers=0','Include_pip=1','Include_test=0','PrependPath=1') -Wait -PassThru
        if ($process.ExitCode -ne 0) { throw "BLOCKED_PYTHON_INSTALL_EXIT_$($process.ExitCode)" }
        Refresh-Path
        Add-UserToolPath (Join-Path $env:LOCALAPPDATA 'Programs\\Python\\Launcher')
        Add-UserToolPath (Join-Path $env:LOCALAPPDATA 'Programs\\Python\\Python311')
        if (-not (Has py)) { throw 'BLOCKED_PY_LAUNCHER_NOT_IN_PATH' }
        & py -3.11 --version
        if ($LASTEXITCODE -ne 0) { throw 'BLOCKED_PYTHON311_MISSING_AFTER_INSTALL' }
    } finally {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force -ErrorAction SilentlyContinue }
    }
}
function Ensure-Tool([string]$Command,[string]$Package) {
    if (Has $Command) { Write-Host "TOOL_$Command=OK"; return }
    if (-not $Apply) { Write-Host "PLAN_INSTALL: $Package (WinGet or official verified portable package)"; return }
    if (Has winget) {
        External winget @('install','--id',$Package,'-e','--source','winget','--accept-source-agreements','--accept-package-agreements')
        Refresh-Path
    } else {
        Write-Host "WINGET_MISSING: using official SHA256-verified portable $Command"
        Install-Portable $Command
    }
    if (-not (Has $Command)) { throw "BLOCKED_INSTALL_OR_PATH: $Command" }
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
if ($InstallPython) { Ensure-Python311 }
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
