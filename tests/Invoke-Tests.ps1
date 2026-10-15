#Requires -Version 7.4
<#
.SYNOPSIS
    Runs the full test suite: reference snippet checks plus every example script in non-interactive mode.
.EXAMPLE
    pwsh -NoProfile -File ./tests/Invoke-Tests.ps1
.EXAMPLE
    pwsh -NoProfile -File ./tests/Invoke-Tests.ps1 -ModuleVersion 2.6.3
#>
param(
    [string] $ModuleVersion
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$skill = Join-Path $root 'plugins/pwshspectreconsole/skills/pwshspectreconsole'
$pwsh = (Get-Process -Id $PID).Path
$failed = 0

function Invoke-Child([string] $Name, [string[]] $Arguments) {
    Write-Host "`n=== $Name" -ForegroundColor Cyan
    $output = & $pwsh -NoProfile -NonInteractive @Arguments 2>&1 | Out-String
    $code = $LASTEXITCODE
    # Scripts can fail without a non-zero exit code (non-terminating errors) - look for error records too
    $hasError = $output -match '(?m)^(\S+Exception|\S+: .+:\d+\r?$|Line \|)'
    if ($code -ne 0 -or $hasError) {
        Write-Host $output
        Write-Host "FAILED ($Name) exit=$code" -ForegroundColor Red
        return 1
    }
    Write-Host "OK ($Name)" -ForegroundColor Green
    return 0
}

$versionArgs = if ($ModuleVersion) { @('-ModuleVersion', $ModuleVersion) } else { @() }
$failed += Invoke-Child 'reference snippets' (@('-File', (Join-Path $PSScriptRoot 'Test-Snippets.ps1')) + $versionArgs)

$prelude = if ($ModuleVersion) { "Import-Module PwshSpectreConsole -RequiredVersion $ModuleVersion; " } else { '' }
$examples = @(
    @{ Name = 'system-dashboard'; Args = '-Top 5' }
    @{ Name = 'deploy-progress'; Args = '-Speed 10' }
    @{ Name = 'interactive-menu'; Args = '-Name demo -Template web -Features CI,Tests -Region eastus -Force' }
    @{ Name = 'live-dashboard'; Args = '-DurationSeconds 2 -RefreshMilliseconds 500' }
)
foreach ($example in $examples) {
    $path = Join-Path $skill "examples/$($example.Name).ps1"
    $failed += Invoke-Child "example: $($example.Name)" @('-Command', "$prelude& '$path' $($example.Args)")
}

$failed += Invoke-Child 'script: Test-SpectreTerminal' @('-Command', "$prelude& '$(Join-Path $skill 'scripts/Test-SpectreTerminal.ps1')'")

Write-Host ""
if ($failed) { Write-Host "$failed test group(s) failed" -ForegroundColor Red } else { Write-Host 'All tests passed' -ForegroundColor Green }
exit $failed
