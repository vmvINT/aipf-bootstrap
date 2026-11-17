$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
$boot = Join-Path $root 'boot.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($boot,[ref]$tokens,[ref]$errors)
if ($null -eq $ast -or @($errors).Count -ne 0) {
  foreach ($error in @($errors)) {
    Write-Error ("BOOT_PARSE_ERROR at line {0}: {1}" -f $error.Extent.StartLineNumber,$error.Message)
  }
  throw 'BOOT_PARSE_FAILED'
}

$text=[IO.File]::ReadAllText($boot,[Text.Encoding]::UTF8)
# A verified here-string can contain the literal source of a generated CLI.
# Count real top-level AST try/catch/finally instead of matching raw source text.
$topTries=@($ast.EndBlock.Statements | Where-Object {
  $_ -is [System.Management.Automation.Language.TryStatementAst]
})
if ($topTries.Count -ne 1) { throw 'BOOT_MAIN_TRY_NOT_UNIQUE' }
if (@($topTries[0].CatchClauses).Count -ne 1) { throw 'BOOT_MAIN_CATCH_NOT_UNIQUE' }
if ($null -eq $topTries[0].Finally) { throw 'BOOT_MAIN_FINALLY_NOT_UNIQUE' }
if ($text -notmatch 'PROFILE_REGISTERED|PROFILE_REGISTRATION_NOT_PERSISTED') {
  throw 'BOOT_PROFILE_REGISTRATION_GATE_MISSING'
}
if ($text -notmatch 'SOURCE_INTEGRITY_MISMATCH') {throw 'BOOT_SOURCE_INTEGRITY_GATE_MISSING'}
if ($text -notmatch "AIPF_BOOTSTRAP_SUCCESS") {throw 'BOOT_SUCCESS_MARKER_MISSING'}
Write-Host 'BOOT_PARSE_AND_STRUCTURE_PASS'
