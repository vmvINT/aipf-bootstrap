$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$src=Join-Path (Split-Path -Parent $PSScriptRoot) 'boot.ps1'
$code=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)
$tok=$null; $errs=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($src,[ref]$tok,[ref]$errs)
if (@($errs).Count -ne 0) { throw 'E2E_BOOT_PARSE_FAILED' }
foreach ($name in @(
    '1d04b434c7cdf61f3f3643872a4da4f91795e5fa',
    "twin-e2e-lab",
    '-Command $labAction -Profile $profileName',
    'function Install-SreTwinCommand',
    'SRE_TWIN_COMMAND_INSTALLED=sre-twin'
)) {
    if (-not $code.Contains($name)) { throw 'E2E_SOURCE_PIN_OR_COMMAND_MISSING' }
}
$functions=@($ast.FindAll({
    param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        ($n.Name -eq 'Install-SreTwinCommand' -or $n.Name -eq 'Get-LabAction')
},$true))
if ($functions.Count -ne 2) { throw 'E2E_BOOT_FUNCTION_COUNT_INVALID' }
foreach ($fn in $functions) { Invoke-Expression $fn.Extent.Text }

$oldEnv=$env:LOCALAPPDATA
$tmp=Join-Path ([IO.Path]::GetTempPath()) ('aipf-e2e-cli-test-'+[guid]::NewGuid().ToString('N'))
try {
    $env:LOCALAPPDATA=$tmp
    $bin=Join-Path $tmp 'AIPF\bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    Install-SreTwinCommand
    $ps=Join-Path $bin 'sre-twin.ps1'
    $cmd=Join-Path $bin 'sre-twin.cmd'
    if (-not (Test-Path $ps -PathType Leaf) -or -not (Test-Path $cmd -PathType Leaf)) {
        throw 'E2E_SHIM_NOT_INSTALLED'
    }
    $tok2=$null; $errs2=$null
    $null=[System.Management.Automation.Language.Parser]::ParseFile($ps,[ref]$tok2,[ref]$errs2)
    if (@($errs2).Count -ne 0) { throw 'E2E_SHIM_PARSE_FAILED' }
    $psContent=[IO.File]::ReadAllText($ps)
    foreach ($part in @('active.json','bootstrap-verified.json','run_incident.py','SRE_TWIN_MANAGED_ROOT','@args')) {
        if (-not $psContent.Contains($part)) { throw 'E2E_SHIM_INVARIANT_MISSING' }
    }
    $oldSha='0cb77a706d254d207f19f4f52642f180dc32440a'
    $f05='516d94843d0b8a4f1e86e7bc6445392aac1e123b'
    $newSha='1d04b434c7cdf61f3f3643872a4da4f91795e5fa'
    $state=Join-Path $tmp 'active.json'
    if ((Get-LabAction $state $newSha $oldSha) -cne 'boot') { throw 'E2E_FRESH_SHOULD_BOOT' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+$oldSha+'"}'))
    if ((Get-LabAction $state $newSha $oldSha) -cne 'update') { throw 'E2E_F04_SHOULD_UPDATE' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+$f05+'"}'))
    if ((Get-LabAction $state $newSha $oldSha) -cne 'update') { throw 'E2E_F05_SHOULD_UPDATE' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+$newSha+'"}'))
    if ((Get-LabAction $state $newSha $oldSha) -cne 'boot') { throw 'E2E_IDEMPOTENCE_INVALID' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+('a'*40)+'"}'))
    $blocked=$false
    try { $null=Get-LabAction $state $newSha $oldSha }
    catch { $blocked=$_.Exception.Message -like 'BLOCKED_UNKNOWN_ACTIVE_SOURCE*' }
    if (-not $blocked) { throw 'E2E_UNKNOWN_ACTIVE_NOT_BLOCKED' }
    Write-Host 'E2E_BOOT_SHIM_AND_STATE_GATES_PASS'
} finally {
    $env:LOCALAPPDATA=$oldEnv
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}
