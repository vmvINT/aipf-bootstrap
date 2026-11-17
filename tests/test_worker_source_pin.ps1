$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path -Parent $PSScriptRoot
$worker = [IO.File]::ReadAllText((Join-Path $root 'cloudflare\worker.js'))
$sourceMatch = [regex]::Match($worker, 'const SOURCE = "(https://raw\.githubusercontent\.com/vmvINT/aipf-bootstrap/[a-f0-9]{40}/boot\.ps1)";')
$digestMatch = [regex]::Match($worker, 'const EXPECTED_SHA256 = "([a-f0-9]{64})";')
if (-not $sourceMatch.Success -or -not $digestMatch.Success) { throw 'SOURCE_PIN_MISSING' }
$source = $sourceMatch.Groups[1].Value
$expected = $digestMatch.Groups[1].Value
$script = Join-Path $root 'boot-private.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'PINNED_SCRIPT_MISSING_FROM_REPO' }
# Git checkout on Windows can convert LF to CRLF; compare normalized text, not byte digests of checkout.
$temp = Join-Path ([IO.Path]::GetTempPath()) ('aipf-ci-boot-'+[guid]::NewGuid().ToString('N')+'.ps1')
try {
  Invoke-WebRequest -Uri $source -OutFile $temp -UseBasicParsing
  $remote = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($remote -cne $expected) { throw 'PINNED_REMOTE_SCRIPT_DIGEST_MISMATCH' }
  $localText = [IO.File]::ReadAllText($script,[Text.Encoding]::UTF8).Replace("`r`n","`n")
  $remoteText = [IO.File]::ReadAllText($temp,[Text.Encoding]::UTF8).Replace("`r`n","`n")
  if ($localText -cne $remoteText) { throw 'PINNED_REMOTE_AND_CHECKOUT_SOURCE_MISMATCH' }
  $tokens=$null
  $errors=$null
  $null=[System.Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)
  if (@($errors).Count -ne 0) { throw 'PINNED_REMOTE_SCRIPT_PARSER_ERROR' }
  Write-Host 'PINNED_WORKER_BOOT_INTEGRITY_AND_PARSE_PASS'
} finally {
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force }
}
