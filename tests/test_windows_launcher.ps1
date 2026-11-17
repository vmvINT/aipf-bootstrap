# Windows-only smoke on GitHub Actions. No network, private repos, credentials or production writes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$launcher=Join-Path $root 'windows\aipf.ps1'
$shim=Join-Path $root 'windows\aipf.cmd'
$oldLocal=$env:LOCALAPPDATA
$profile='synthetic'
$sha='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('aipf-cli-smoke-'+[guid]::NewGuid().ToString('N'))
try {
  New-Item -Path $temp -ItemType Directory -Force | Out-Null
  $env:LOCALAPPDATA=$temp
  & $launcher -Command profile -Profile set -Argument1 $profile -Argument2 'fixture/Synthetic-Repo' -Argument3 $sha
  if (-not $?) { throw 'NAMED_PROFILE_SET_FAILED' }
  $path=Join-Path $temp 'AIPF\profiles\synthetic.json'
  if (-not (Test-Path -LiteralPath $path)) { throw 'PROFILE_FILE_MISSING' }
  $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
  if ($data.repo -cne 'fixture/Synthetic-Repo' -or $data.sha -cne $sha) { throw 'WRONG_PROFILE_ARGUMENT_BINDING' }
  $out=(& $launcher -Command doctor) -join ' '
  if ($out -notmatch 'PROFILE_COUNT=1') { throw 'DOCTOR_COUNT_INVALID' }
  $env:LOCALAPPDATA=(Join-Path $temp 'positional')
  & $shim profile set synthetic fixture/Synthetic-Repo $sha
  if ($LASTEXITCODE -ne 0) { throw 'POSITIONAL_CMD_SHIM_FAILED' }
  $path2=Join-Path $env:LOCALAPPDATA 'AIPF\profiles\synthetic.json'
  if (-not (Test-Path -LiteralPath $path2)) { throw 'POSITIONAL_PROFILE_FILE_MISSING' }
  $data2=Get-Content -LiteralPath $path2 -Raw | ConvertFrom-Json
  if ($data2.repo -cne 'fixture/Synthetic-Repo') { throw 'POSITIONAL_ARGUMENT_BINDING_WRONG' }
  Write-Host 'WINDOWS_LAUNCHER_PROFILE_SMOKE_PASS'
} finally {
  $env:LOCALAPPDATA=$oldLocal
  if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
