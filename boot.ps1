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
$sourceSha = '708bc40656f4b33c6ed11dd8d378e4ad44c00fab'
$projectSha = '245b81525af15d97b7d873d7c1223de8d68995c2'
$root = 'https://raw.githubusercontent.com/vmvINT/aipf-bootstrap/' + $sourceSha
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('aipf-boot-' + [Guid]::NewGuid().ToString('N'))
$files = @('windows/aipf-setup.ps1', 'windows/aipf.ps1', 'windows/aipf.cmd')
$expectedBlob = @{
 'windows/aipf-setup.ps1' = 'a839f9c8be741aef86959eb8f203a3598f96fb5f'
 'windows/aipf.ps1' = 'cdb19d91e0cfdbbabe36bdbdac9d466fe4df6e2b'
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
        $candidates = @($repositoryJson | ConvertFrom-Json | Where-Object {
            $_.name -match '(^|[-_])twin$'
        })
        if ($candidates.Count -ne 1) {
            throw "BLOCKED_PRIVATE_PROFILE_DISCOVERY: expected one matching private repo, found $($candidates.Count)"
        }
        CheckExternal $launcher @('profile','set','twin',$candidates[0].nameWithOwner,$projectSha)
    } else {
        $stored = Get-Content -LiteralPath $existingProfile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($stored.sha -cne $projectSha) { throw 'BLOCKED_EXISTING_PROFILE_SHA_MISMATCH: refusing silent version change' }
        Write-Host 'AIPF: using existing pinned twin profile'
    }
    Write-Host 'AIPF: installing pinned Twin LAB candidate'
    CheckExternal $launcher @('boot','twin')
    Write-Host 'AIPF_BOOTSTRAP_SUCCESS'
} catch {
    [Console]::Error.WriteLine("AIPF_BOOTSTRAP_BLOCKED: $($_.Exception.Message)")
    throw
} finally {
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}
