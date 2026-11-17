#requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$worker=Join-Path $root 'cloudflare\worker.js'
$boot=Join-Path $root 'boot-private.ps1'
$stage0=Join-Path $root 'cloudflare\stage0-reviewed.ps1'
foreach($p in @($worker,$boot,$stage0)) {
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('WORKER_SOURCE_MISSING: '+$p) }
}
foreach($p in @($boot,$stage0)) {
  $tokens=$null
  $errors=$null
  $null=[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -gt 0) { throw ('PUBLIC_BUNDLE_POWERSHELL_PARSE_ERROR: '+($errors|Out-String)) }
}
$workerText=[IO.File]::ReadAllText($worker,[Text.Encoding]::UTF8)
if ($workerText -notmatch 'EMBEDDED_BOOT' -or $workerText -notmatch 'EMBEDDED_STAGE0') {
  throw 'SELF_CONTAINED_WORKER_MISSING'
}
if ($workerText -match 'raw\.githubusercontent\.com') {
  throw 'PUBLIC_RAW_GITHUB_RUNTIME_DEPENDENCY'
}
if(-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'NODE_REQUIRED_FOR_EXACT_WORKER_BUNDLE_TEST'
}
& node --test (Join-Path $root 'tests\worker.test.mjs')
if($LASTEXITCODE -ne 0) { throw 'EMBEDDED_WORKER_TEST_FAILED' }
Write-Host 'SELF_CONTAINED_WORKER_WINDOWS_PARSER_AND_BUNDLE_PASS'
