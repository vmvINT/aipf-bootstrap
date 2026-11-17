#requires -Version 5.1
<#
AIPF small PUBLIC trust anchor for PRIVATE GitHub Bootstrap, LAB only.
The private installer and SRE source are not served anonymously.
No token, password, private manifest or corporate URL is embedded.
Releasing this as an active Cloudflare route requires separate verified rollout.
#>
[CmdletBinding()]
param([switch]$VerifyOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
# All remote bytes are pinned independently at review. Update only via reviewed PR.
$repo = 'vmvINT/AIPF'
$sourceSha = '753f967d389aa0cc205d86d0430c9532a4cd2cd1'
$privateClientPath = 'experiments/private-bootstrap/install-private.ps1'
$privateClientSha256 = 'fca2ae9e2b40d34390435404169a30440b62fe87d40e9d940ad8d589e23ac215'
$privateBootPath = 'experiments/private-bootstrap/boot.ps1'
$privateBootSha256 = 'c2f41013d09abe48ec7ea15a3c285cb3c58d243e6886b53e00c6d2e4a99c3fd9'
$stage0Commit = '439fb97e0e0824d866fc999e9ccc12a7149f39d1'
$stage0Blob = '7f6b45b45a9c646d5455be3474a6bfeee4bfde68'

function Block([string]$code) {
    throw ('AIPF_PRIVATE_LOADER_BLOCKED:' + $code)
}
function Sha256([byte[]]$bytes) {
    $digest = [Security.Cryptography.SHA256]::Create()
    try { return (-join ($digest.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') })) }
    finally { $digest.Dispose() }
}
function BlobSha1([byte[]]$bytes) {
    $header = [Text.Encoding]::ASCII.GetBytes(('blob '+ $bytes.Length + [char]0))
    $joined = New-Object byte[] ($header.Length + $bytes.Length)
    [Array]::Copy($header,0,$joined,0,$header.Length)
    [Array]::Copy($bytes,0,$joined,$header.Length,$bytes.Length)
    $h = [Security.Cryptography.SHA1]::Create()
    try { return (-join ($h.ComputeHash($joined) | ForEach-Object { $_.ToString('x2') })) }
    finally { $h.Dispose() }
}
function CheckGh() {
    $previous = $ErrorActionPreference
    $ErrorActionPreference='Continue'
    try {
        $null = & gh auth status --hostname github.com 2>$null
        return ($LASTEXITCODE -eq 0)
    } finally { $ErrorActionPreference=$previous }
}
function SafeGhJson([string]$route) {
    $previous=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    try {
        $lines = @(& gh api --method GET $route 2>$null)
        $code=$LASTEXITCODE
    } finally { $ErrorActionPreference=$previous }
    if ($code -ne 0) { Block 'PRIVATE_GITHUB_ACCESS_DENIED_OR_FAILED' }
    try { return (ConvertFrom-Json -InputObject ($lines -join [Environment]::NewLine) -ErrorAction Stop) }
    catch { Block 'GITHUB_METADATA_INVALID' }
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('aipf-private-loader-'+ [Guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -Path $work -ItemType Directory
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        # Only dependency bootstrap is public. It is immutable and reviewed.
        # The existing native Windows Stage0 prepares Git, gh and Python 3.11.
        Write-Host 'AIPF: installing GitHub CLI prerequisite from reviewed public Stage0'
        $upstream='https://raw.githubusercontent.com/vmvINT/aipf-bootstrap/'+$stage0Commit+'/windows/aipf-setup.ps1'
        $destination=Join-Path $work 'stage0-prerequisites.ps1'
        Invoke-WebRequest -Uri $upstream -OutFile $destination -UseBasicParsing
        [byte[]]$prereq=[IO.File]::ReadAllBytes($destination)
        if ((BlobSha1 $prereq) -cne $stage0Blob) { Block 'PUBLIC_STAGE0_DIGEST_MISMATCH' }
        & $destination -Apply -Login -InstallPython
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Block 'GITHUB_CLI_NOT_INSTALLED' }
    }
    if (-not (CheckGh)) {
        Write-Host 'AIPF: sign in to GitHub in your browser (MFA may be required)'
        & gh auth login --hostname github.com --git-protocol https --web
        if ($LASTEXITCODE -ne 0 -or -not (CheckGh)) { Block 'GITHUB_LOGIN_REQUIRED' }
    }
    $meta=SafeGhJson ('repos/'+$repo)
    if ($meta.private -ne $true -or [string]$meta.full_name -cne $repo) {
        Block 'PRIVATE_REPO_NOT_AUTHORIZED'
    }
    $commit=SafeGhJson ('repos/'+$repo+'/commits/'+$sourceSha)
    if ([string]$commit.sha -cne $sourceSha) { Block 'PRIVATE_SOURCE_SHA_MISMATCH' }
    $artifact=SafeGhJson ('repos/'+$repo+'/contents/'+$privateClientPath+'?ref='+$sourceSha)
    if ([string]$artifact.type -cne 'file' -or [string]$artifact.path -cne $privateClientPath -or
        [string]$artifact.encoding -cne 'base64' -or [string]$artifact.sha -cnotmatch '^[0-9a-f]{40}$') {
        Block 'PRIVATE_CLIENT_METADATA_MISMATCH'
    }
    try { [byte[]]$bytes=[Convert]::FromBase64String((([string]$artifact.content) -replace '\s','')) }
    catch { Block 'PRIVATE_CLIENT_BYTES_INVALID' }
    if ($bytes.Length -lt 1 -or $bytes.Length -gt 1048576) { Block 'PRIVATE_CLIENT_SIZE_INVALID' }
    if ((Sha256 $bytes) -cne $privateClientSha256 -or (BlobSha1 $bytes) -cne [string]$artifact.sha) {
        Block 'PRIVATE_CLIENT_HASH_MISMATCH'
    }
    $entry=Join-Path $work 'install-private.ps1'
    [IO.File]::WriteAllBytes($entry,$bytes)
    Write-Host 'AIPF_PRIVATE_CLIENT_VERIFIED=PASS'
    $arguments=@('-Repository',$repo,'-CommitSha',$sourceSha,
                 '-ExpectedSha256',$privateBootSha256,'-ArtifactPath',$privateBootPath)
    if ($VerifyOnly) { $arguments += '-VerifyOnly' }
    else { $arguments += '-Apply' }
    & $entry @arguments
    if (-not $?) { Block 'PRIVATE_INSTALLER_FAILED' }
    if ($VerifyOnly) { Write-Host 'AIPF_PRIVATE_LOADER_VERIFY_ONLY=PASS' }
    else { Write-Host 'AIPF_PRIVATE_LOADER_HANDOFF=COMPLETE' }
} catch {
    [Console]::Error.WriteLine('AIPF_PRIVATE_LOADER_FAILED: ' + $_.Exception.Message)
    throw
} finally {
    if (Test-Path -LiteralPath $work -PathType Container) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
