$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$script=Join-Path $root 'boot.ps1'
$text=[IO.File]::ReadAllText($script,[Text.Encoding]::UTF8)
$tok=$null; $errs=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tok,[ref]$errs)
if (@($errs).Count -ne 0) { throw 'F05_BOOT_PARSE_FAILED' }
foreach ($v in @(
    '516d94843d0b8a4f1e86e7bc6445392aac1e123b',
    "twin-router-lab",
    '-Argument1 $profileName -Argument2 $repoName -Argument3 $projectSha',
    '-Command $labAction -Profile $profileName',
    'BLOCKED_EXISTING_PROFILE_SHA_MISMATCH',
    'function Get-LabAction'
)) {
    if (-not $text.Contains($v)) { throw 'F05_BOOT_PIN_OR_ACTION_MISSING' }
}
$func=@($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-LabAction' },$true))
if ($func.Count -ne 1) { throw 'F05_ACTION_HELPER_NOT_UNIQUE' }
Invoke-Expression $func[0].Extent.Text
$old='0cb77a706d254d207f19f4f52642f180dc32440a'
$new='516d94843d0b8a4f1e86e7bc6445392aac1e123b'
$dir=Join-Path ([IO.Path]::GetTempPath()) ('aipf-f05-state-'+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $dir | Out-Null
    $state=Join-Path $dir 'active.json'
    if ((Get-LabAction $state $new $old) -cne 'boot') { throw 'F05_FRESH_INSTALL_ACTION_WRONG' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+$old+'","previous":null}'))
    if ((Get-LabAction $state $new $old) -cne 'update') { throw 'F05_OLD_ACTIVE_NOT_UPDATING' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+$new+'","previous":"'+$old+'"}'))
    if ((Get-LabAction $state $new $old) -cne 'boot') { throw 'F05_REPEAT_NOT_IDEMPOTENT' }
    [IO.File]::WriteAllText($state,('{"schema":1,"active":"'+('c'*40)+'"}'))
    $blocked=$false
    try { $null=Get-LabAction $state $new $old } catch { $blocked=$_.Exception.Message -like 'BLOCKED_UNKNOWN_ACTIVE_SOURCE*' }
    if (-not $blocked) { throw 'F05_UNKNOWN_ACTIVE_OVERWRITE_RISK' }
    [IO.File]::WriteAllText($state,'corrupt')
    $blocked=$false
    try { $null=Get-LabAction $state $new $old } catch { $blocked=$_.Exception.Message -eq 'BLOCKED_STATE_INVALID_JSON' }
    if (-not $blocked) { throw 'F05_INVALID_STATE_NOT_BLOCKED' }
    Write-Host 'F05_BOOT_INSTALL_UPDATE_ROLLBACK_PRECONDITIONS_PASS'
} finally {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Force -Recurse }
}
