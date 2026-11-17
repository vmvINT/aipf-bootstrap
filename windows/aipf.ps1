#requires -Version 5.1
[CmdletBinding()]
param([Parameter(Position=0)][string]$Command='help',[Parameter(Position=1)][string]$Profile)
$ErrorActionPreference = 'Stop'
$version = '0.1.0'
function Blocked([string]$Message,[int]$Code=4) { [Console]::Error.WriteLine($Message); exit $Code }
switch ($Command.ToLowerInvariant()) {
  'version' { Write-Output "aipf-launcher $version"; exit 0 }
  '--version' { Write-Output "aipf-launcher $version"; exit 0 }
  { $_ -in @('help','--help','-h') } {
    Write-Output @'
AIPF launcher 0.1.0 (development)
Usage: aipf <version|doctor|boot|update|rollback|help> [profile]
This launcher contains no private project code. Stage 2 is not yet implemented.
'@
    exit 0
  }
  'doctor' {
    Write-Output "AIPF_LAUNCHER_VERSION=$version"
    foreach ($tool in @('git','gh','py')) {
      if (Get-Command $tool -ErrorAction SilentlyContinue) { Write-Output "TOOL_$tool=OK" }
      else { Write-Output "TOOL_$tool=MISSING" }
    }
    Write-Output 'PRIVATE_PROFILE=NOT_CONFIGURED'
    Write-Output 'STATUS=STAGE1_READY_STAGE2_PENDING'
    exit 0
  }
  { $_ -in @('boot','update','rollback') } {
    if ([string]::IsNullOrWhiteSpace($Profile)) { Blocked 'USAGE_ERROR: profile argument required' 2 }
    if ($Profile -cnotmatch '^[A-Za-z0-9_-]+$') { Blocked 'INVALID_PROFILE' 2 }
    Blocked "BLOCKED_STAGE2_NOT_IMPLEMENTED: $Command $Profile"
  }
  default { Blocked "UNKNOWN_COMMAND: $Command" 2 }
}
