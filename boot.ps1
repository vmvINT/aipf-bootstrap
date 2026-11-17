#requires -Version 5.1
<#
AIPF Twin first-run entrypoint (Windows LAB candidate).
Single-command bootstrap: pinned public Stage0/Stage2 files, auth, private discovery, pinned LAB install.
Intended invocation: irm <pinned GitHub raw URL>/boot.ps1 | iex
The caller chooses to execute remote code; this script never requests administrator elevation.
#>
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Error.Clear()
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$sourceSha = '94d0a7679506d2e8dff1d355dc9a1b9a10318947'
$projectSha = '245b81525af15d97b7d873d7c1223de8d68995c2'
$root = 'https://raw.githubusercontent.com/vmvINT/aipf-bootstrap/' + $sourceSha
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('aipf-boot-' + [Guid]::NewGuid().ToString('N'))
$files = @('windows/aipf-setup.ps1', 'windows/aipf.ps1', 'windows/aipf.cmd')
$expectedBlob = @{
 'windows/aipf-setup.ps1' = 'd65a896afcd41dd8eedaa1d80f660d4a2dcf8e84'
 'windows/aipf.ps1' = '82f441fe65974fe6e0764c8d90ba55a7faf8a167'
 'windows/aipf.cmd' = 'f1b903fd2782454eb9e0c4b339fcc359ce331fb8'
}
function Git-BlobHash([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $prefix = [Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)" + [char]0)
    $all = New-Object byte[] ($prefix.Length + $bytes.Length)
    [Array]::Copy($prefix, 0, $all, 0, $prefix.Length)
    [Array]::Copy($bytes, 0, $all, $prefix.Length, $bytes.Length)
    $hash = [Security.Cryptography.SHA1]::Create()
    try { return (-join ($hash.ComputeHash($all) | ForEach-Object { $_.ToString('x2') })) }
    finally { $hash.Dispose() }
}
function CheckExternal([string]$Command,[string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "COMMAND_FAILED: $Command exit=$LASTEXITCODE" }
}
function Resolve-TwinRepo([string]$Json) {
    if ([string]::IsNullOrWhiteSpace($Json)) { throw 'BLOCKED_EMPTY_REPO_DISCOVERY' }
    try { $parsed = ConvertFrom-Json -InputObject $Json -ErrorAction Stop }
    catch { throw 'BLOCKED_INVALID_REPO_DISCOVERY_JSON' }
    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($entry in @($parsed)) {
        if ($null -eq $entry) { continue }
        $name = [string]$entry.name
        if ($name -notmatch '(?i)(^|[-_])twin$') { continue }
        $prop = $entry.PSObject.Properties['nameWithOwner']
        if ($null -eq $prop) { throw 'BLOCKED_REPO_FULL_NAME_MISSING' }
        $full = [string]$prop.Value
        if ([string]::IsNullOrWhiteSpace($full)) { throw 'BLOCKED_REPO_FULL_NAME_MISSING' }
        if (-not [regex]::IsMatch($full, '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')) { throw 'BLOCKED_REPO_FULL_NAME_INVALID' }
        if (($full.Split('/')[1]) -cne $name) { throw 'BLOCKED_REPO_NAME_MISMATCH' }
        $found.Add($full)
    }
    if ($found.Count -ne 1) { throw ('BLOCKED_PRIVATE_PROFILE_DISCOVERY: candidate_count=' + $found.Count) }
    return $found[0]
}
try {
    New-Item -Path (Join-Path $temporary 'windows') -ItemType Directory -Force | Out-Null
    foreach ($file in $files) {
        $destination = Join-Path $temporary $file
        Invoke-WebRequest -Uri ($root + '/' + $file) -OutFile $destination -UseBasicParsing
        if ((Git-BlobHash $destination) -cne $expectedBlob[$file]) {
            throw "SOURCE_INTEGRITY_MISMATCH: $file"
        }
    }
    Write-Host 'AIPF: Stage 0, Git/gh/Python 3.11 (WinGet or verified official fallback), launcher'
    & (Join-Path $temporary 'windows/aipf-setup.ps1') -Apply -Login -InstallPython
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "STAGE0_FAILED: $LASTEXITCODE" }
    $launcher = Join-Path $env:LOCALAPPDATA 'AIPF\bin\aipf.cmd'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'LAUNCHER_NOT_INSTALLED' }
    $existingProfile = Join-Path $env:LOCALAPPDATA 'AIPF\profiles\twin.json'
    if (-not (Test-Path -LiteralPath $existingProfile -PathType Leaf)) {
        $repositoryJson = & gh repo list --limit 200 --visibility private --json name,nameWithOwner
        if ($LASTEXITCODE -ne 0) { throw 'PRIVATE_REPOSITORY_DISCOVERY_FAILED' }
        $repoName = Resolve-TwinRepo ([string]($repositoryJson -join [Environment]::NewLine))
        $launcherScript = Join-Path $env:LOCALAPPDATA 'AIPF\bin\aipf.ps1'
        & $launcherScript -Command profile -Profile set -Argument1 twin -Argument2 $repoName -Argument3 $projectSha
        if (-not $?) { throw 'PROFILE_REGISTRATION_FAILED' }
        if (-not (Test-Path -LiteralPath $existingProfile -PathType Leaf)) {
            throw 'PROFILE_REGISTRATION_NOT_PERSISTED'
        }
    } else {
        $stored = Get-Content -LiteralPath $existingProfile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($stored.sha -cne $projectSha) { throw 'BLOCKED_EXISTING_PROFILE_SHA_MISMATCH: refusing silent version change' }
        Write-Host 'AIPF: using existing pinned twin profile'
    }
    Write-Host 'AIPF: installing pinned Twin LAB candidate'
    $launcherScript = Join-Path $env:LOCALAPPDATA 'AIPF\bin\aipf.ps1'
    & $launcherScript -Command boot -Profile twin
    if (-not $?) { throw 'TWIN_BOOT_FAILED' }
    Write-Host 'AIPF_BOOTSTRAP_SUCCESS'
} catch {
    [Console]::Error.WriteLine("AIPF_BOOTSTRAP_BLOCKED: $($_.Exception.Message)")
    throw
} finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}
