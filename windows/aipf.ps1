#requires -Version 5.1
<#
AIPF Windows launcher Stage 2 (developer preview).
The public code contains NO private repo location. User explicitly registers
an immutable source by: aipf profile set NAME OWNER/REPO 40_HEX_SHA
No token or passwords are passed as arguments.
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)][string]$Command='help',
    [Parameter(Position=1)][string]$Profile='',
    [Parameter(Position=2)][string]$Argument1='',
    [Parameter(Position=3)][string]$Argument2='',
    [Parameter(Position=4)][string]$Argument3=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$version='0.2.0-dev'
$profileRoot=Join-Path $env:LOCALAPPDATA 'AIPF\profiles'
function Fail([string]$Reason,[int]$Code=4) { [Console]::Error.WriteLine($Reason); exit $Code }
function Run([string]$CommandName,[string[]]$Arguments) {
    & $CommandName @Arguments
    if ($LASTEXITCODE -ne 0) { throw "COMMAND_FAILED: $CommandName exit=$LASTEXITCODE" }
}
function Validate-Name([string]$Value) {
    if ($Value -cnotmatch '^[a-z][a-z0-9_-]{0,39}$') { Fail 'INVALID_PROFILE_NAME' 2 }
}
function Profile-Path([string]$Name) {
    Validate-Name $Name
    return Join-Path $profileRoot "$Name.json"
}
function Load-Profile([string]$Name) {
    $path=Profile-Path $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail 'BLOCKED_PROFILE_NOT_REGISTERED' }
    $item=Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { Fail 'BLOCKED_PROFILE_REPARSE' }
    $obj=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($obj.schema -ne 1 -or $obj.repo -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $obj.sha -cnotmatch '^[0-9a-f]{40}$') {
        Fail 'BLOCKED_INVALID_PROFILE'
    }
    return $obj
}
function Do-Doctor {
    Write-Output "AIPF_LAUNCHER_VERSION=$version"
    foreach ($tool in @('git','gh','py')) {
        if (Get-Command $tool -ErrorAction SilentlyContinue) { Write-Output "TOOL_$tool=OK" }
        else { Write-Output "TOOL_$tool=MISSING" }
    }
    if (Test-Path -LiteralPath $profileRoot -PathType Container) {
        $count=@(Get-ChildItem -LiteralPath $profileRoot -Filter '*.json' -File).Count
    } else { $count=0 }
    Write-Output "PROFILE_COUNT=$count"
    Write-Output 'STATUS=STAGE2_DEV_NOT_RELEASED'
}
function Register-Profile([string]$Name,[string]$Repo,[string]$Sha) {
    $path=Profile-Path $Name
    if ($Repo -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { Fail 'INVALID_REPOSITORY' 2 }
    if ($Sha -cnotmatch '^[0-9a-f]{40}$') { Fail 'INVALID_SOURCE_SHA' 2 }
    if (Test-Path -LiteralPath $path) { Fail 'BLOCKED_PROFILE_EXISTS: do not overwrite; backup and remove manually' }
    New-Item -ItemType Directory -Force -Path $profileRoot | Out-Null
    $doc=@{schema=1;repo=$Repo;sha=$Sha;installer='scripts/bootstrap_git_lab.py'} | ConvertTo-Json
    $tmp=Join-Path $profileRoot ('.'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        [IO.File]::WriteAllText($tmp,$doc,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $path -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
    Write-Output "PROFILE_REGISTERED=$Name"
    Write-Output 'PROFILE_PRIVATE_CONFIG=LOCAL_ONLY'
}
function Invoke-Project([string]$Action,[string]$Name) {
    $p=Load-Profile $Name
    foreach ($tool in @('git','gh','py')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "BLOCKED_TOOL_MISSING: $tool" }
    }
    Run 'py' @('-3.11','--version')
    Run 'gh' @('auth','status','--hostname','github.com')
    Run 'gh' @('auth','setup-git')
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('aipf-stage2-'+[guid]::NewGuid().ToString('N'))
    try {
        $url="https://github.com/$($p.repo).git"
        Run 'git' @('clone','--quiet','--no-checkout',$url,$temp)
        Run 'git' @('-C',$temp,'checkout','--quiet','--detach',$p.sha)
        $actual=(& git -C $temp rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0 -or $actual -cne $p.sha) { Fail 'BLOCKED_SOURCE_SHA_MISMATCH' }
        $origin=(& git -C $temp remote get-url origin).Trim()
        if ($origin -cne $url) { Fail 'BLOCKED_ORIGIN_MISMATCH' }
        $script=Join-Path $temp $p.installer
        if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { Fail 'BLOCKED_INSTALLER_MISSING' }
        if ($Action -eq 'boot') { $subaction='install' } else { $subaction=$Action }
        if ($Action -eq 'boot' -or $Action -eq 'update') {
            Run 'py' @('-3.11','-I',$script,'plan','--source-sha',$p.sha)
        }
        if ($Action -eq 'doctor' -or $Action -eq 'rollback') {
            Run 'py' @('-3.11','-I',$script,$subaction)
        } else {
            Run 'py' @('-3.11','-I',$script,$subaction,'--source-sha',$p.sha)
        }
        Write-Output "AIPF_ACTION_COMPLETED=$Action"
    } finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue
        }
    }
}
try {
    switch ($Command.ToLowerInvariant()) {
        'version' { Write-Output "aipf-launcher $version" }
        '--version' { Write-Output "aipf-launcher $version" }
        'help' {
            Write-Output 'Usage: aipf version | doctor | profile set NAME OWNER/REPO SHA | boot NAME | update NAME | rollback NAME'
            Write-Output 'Stage 2 preview: private profile registration required before boot. No public release.'
        }
        'doctor' { Do-Doctor }
        'profile' {
            if ($Profile -cne 'set') { Fail 'USAGE: aipf profile set NAME OWNER/REPO SHA' 2 }
            Register-Profile $Argument1 $Argument2 $Argument3
        }
        { $_ -in @('boot','update','rollback') } {
            Validate-Name $Profile
            Invoke-Project $Command.ToLowerInvariant() $Profile
        }
        default { Fail "UNKNOWN_COMMAND: $Command" 2 }
    }
} catch {
    Fail ("BLOCKED_STAGE2: "+ $_.Exception.Message)
}
