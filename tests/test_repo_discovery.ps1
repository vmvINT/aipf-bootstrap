$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root=Split-Path -Parent $PSScriptRoot
$script=Join-Path $root 'boot.ps1'
$tok=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($script,[ref]$tok,[ref]$errors)
if (@($errors).Count -ne 0) { throw 'BOOT_PARSE_FAILED' }
$func=@($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-TwinRepo' }, $true))
if ($func.Count -ne 1) { throw 'REPO_RESOLVER_FUNCTION_COUNT' }
Invoke-Expression $func[0].Extent.Text
$synthetic='[{"name":"other","nameWithOwner":"example/other"},{"name":"SRE_Twin","nameWithOwner":"example/SRE_Twin"}]'
$selected=Resolve-TwinRepo $synthetic
if ($selected -cne 'example/SRE_Twin') { throw 'WRONG_TWIN_REPOSITORY_SELECTED' }
$single='[{"name":"SRE_Twin","nameWithOwner":"example/SRE_Twin"}]'
if ((Resolve-TwinRepo $single) -cne 'example/SRE_Twin') { throw 'SINGLE_ITEM_JSON_FAILED' }
$cases=@(
  @{ json='[]'; expected='BLOCKED_PRIVATE_PROFILE_DISCOVERY' },
  @{ json='[{"name":"SRE_Twin","nameWithOwner":"bad-repo"}]'; expected='BLOCKED_REPO_FULL_NAME_INVALID' },
  @{ json='[{"name":"SRE_Twin"}]'; expected='BLOCKED_REPO_FULL_NAME_MISSING' },
  @{ json='[{"name":"SRE_Twin","nameWithOwner":"example/Other"}]'; expected='BLOCKED_REPO_NAME_MISMATCH' },
  @{ json='[{"name":"SRE_Twin","nameWithOwner":"example/SRE_Twin"},{"name":"SRE_Twin","nameWithOwner":"other/SRE_Twin"}]'; expected='BLOCKED_PRIVATE_PROFILE_DISCOVERY' },
  @{ json='not-json'; expected='BLOCKED_INVALID_REPO_DISCOVERY_JSON' }
)
foreach ($case in $cases) {
    $caught=$false
    try { $null=Resolve-TwinRepo $case.json }
    catch { if ($_.Exception.Message -like ('*'+$case.expected+'*')) { $caught=$true } else { throw } }
    if (-not $caught) { throw ('MISSING_FAIL_CLOSED_CASE: '+$case.expected) }
}
Write-Host 'REPO_DISCOVERY_WINDOWS_SMOKE_PASS'
