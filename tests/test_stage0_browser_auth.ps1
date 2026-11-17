$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Fetch the exact immutable Windows Stage0 referenced by boot.ps1.
$pin = '439fb97e0e0824d866fc999e9ccc12a7149f39d1'
$uri = "https://raw.githubusercontent.com/vmvINT/aipf-bootstrap/$pin/windows/aipf-setup.ps1"
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('aipf-gh-auth-'+[guid]::NewGuid().ToString('N')+'.ps1')
try {
    Invoke-WebRequest -Uri $uri -OutFile $tmp -UseBasicParsing
    $text = [IO.File]::ReadAllText($tmp, [Text.Encoding]::UTF8)
    if ($text -match [regex]::Escape('& gh auth status --hostname github.com *> $null')) {
        throw 'UNSAFE_STDERR_REDIRECTION_RETAINED'
    }
    if (-not $text.Contains('System.Diagnostics.ProcessStartInfo')) {
        throw 'STATUS_EXIT_CODE_GUARD_MISSING'
    }
    $tok = $null; $errs = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($tmp,[ref]$tok,[ref]$errs)
    if (@($errs).Count -ne 0) { throw 'STAGE0_AUTH_PARSE_FAILED' }
    $nodes = @($ast.FindAll({
        param($x)
        $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
          $x.Name -eq 'Ensure-GithubLogin'
    },$true))
    if ($nodes.Count -ne 1) { throw 'GH_AUTH_FUNCTION_NOT_UNIQUE' }
    Invoke-Expression $nodes[0].Extent.Text

    function Has([string]$Name) { return $true }
    $script:observed = New-Object 'System.Collections.Generic.List[string]'
    function External([string]$Executable,[string[]]$Arguments) {
        $script:observed.Add($Executable + ' ' + ($Arguments -join ' '))
    }
    $script:statuses = @(1,0)
    $script:index = 0
    function Gh-Status-ExitCode {
        $v = $script:statuses[$script:index]
        $script:index++
        return $v
    }

    # Clean new Windows PC: absent GitHub login -> official browser flow
    # then automatic setup-git + status, with no second user command.
    Ensure-GithubLogin
    if ($script:index -ne 2) { throw 'LOGGED_OUT_NOT_RECHECKED' }
    if ($script:observed.Count -ne 3 -or
        $script:observed[0] -cne 'gh auth login --hostname github.com --git-protocol https --web' -or
        $script:observed[1] -cne 'gh auth setup-git' -or
        $script:observed[2] -cne 'gh auth status --hostname github.com') {
        throw 'BROWSER_LOGIN_NOT_CONTINUED'
    }

    # Existing auth: never open a second browser window.
    $script:statuses = @(0)
    $script:index = 0
    $script:observed.Clear()
    Ensure-GithubLogin
    if ($script:index -ne 1 -or $script:observed.Count -ne 2 -or
        $script:observed[0] -cne 'gh auth setup-git') {
        throw 'ACTIVE_LOGIN_SHOULD_BE_REUSED'
    }

    # User closes browser / aborts login -> fail safely, do not clone project.
    $script:statuses = @(1,1)
    $script:index = 0
    $script:observed.Clear()
    $blocked = $false
    try { Ensure-GithubLogin } catch {
        $blocked = $_.Exception.Message -eq 'GITHUB_AUTH_INCOMPLETE'
    }
    if (-not $blocked -or $script:observed.Count -ne 1) {
        throw 'INCOMPLETE_LOGIN_NOT_BLOCKED'
    }
    Write-Host 'GITHUB_BROWSER_AUTH_MOCK_SCENARIOS_PASS'
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
}
