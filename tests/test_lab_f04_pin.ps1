$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$path=Join-Path $root 'boot.ps1'
$code=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
$tok=$null; $errors=$null
$null=[System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tok,[ref]$errors)
if (@($errors).Count -ne 0) { throw 'F04_BOOT_PARSE_FAILED' }
$checks=@(
  '0cb77a706d254d207f19f4f52642f180dc32440a',
  'twin-f04',
  '-Argument1 $profileName -Argument2 $repoName -Argument3 $projectSha',
  '-Command boot -Profile $profileName',
  'BLOCKED_EXISTING_PROFILE_SHA_MISMATCH'
)

for ($i=0; $i -lt $checks.Count; $i++) {
  if (-not $code.Contains($checks[$i])) { throw ('F04_PIN_CONTRACT_MISSING_INDEX_' + $i) }
}
if ($code.Contains("'AIPF\profiles\twin.json'")) { throw 'LEGACY_PROFILE_OVERWRITE_RISK' }
if ($code.Contains("'245b81525af15d97b7d873d7c1223de8d68995c2'")) { throw 'OLD_SOURCE_PIN_UNEXPECTED' }
Write-Output 'BOOT_F04_PROFILE_PIN_PASS'
