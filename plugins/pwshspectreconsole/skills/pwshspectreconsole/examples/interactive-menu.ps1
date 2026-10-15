#Requires -Version 7.4
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Project setup wizard using Spectre prompts, with full non-interactive fallbacks.
.DESCRIPTION
    Demonstrates: guarding prompts with Profile.Capabilities.Interactive, parameters as the
    automation path, selecting objects with escaped labels, multi/grouped selection,
    confirm with defaults, handling cancel ($null), and a review panel with JSON.
.EXAMPLE
    ./interactive-menu.ps1                                    # interactive wizard
.EXAMPLE
    ./interactive-menu.ps1 -Name demo -Template web -Features CI, Tests -Force   # CI / non-interactive
#>
[CmdletBinding()]
param(
    [string] $Name,
    [ValidateSet('api', 'web', 'cli')]
    [string] $Template,
    [string[]] $Features,
    [string] $Region,
    [switch] $Force
)

$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
# Import only if not loaded: a second version in the same session fails ("Assembly with same name is already loaded")
if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }

$interactive = [Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive

function Resolve-Value {
    <# Returns the parameter value, otherwise prompts when interactive, otherwise the default. #>
    param($Value, [scriptblock] $Prompt, $Default)
    if ($Value) { return $Value }
    if ($interactive) {
        $answer = & $Prompt
        if ($null -eq $answer) { throw 'Cancelled.' }       # Ctrl+C / timeout returns $null
        return $answer
    }
    return $Default
}

if ($interactive) { Write-SpectreFigletText 'Setup' -Color Cyan1 }

$templates = @(
    [pscustomobject]@{ Id = 'api'; Title = 'REST API [ASP.NET]'; Description = 'Minimal API + OpenAPI' }
    [pscustomobject]@{ Id = 'web'; Title = 'Web app [Blazor]';   Description = 'Server-side Blazor' }
    [pscustomobject]@{ Id = 'cli'; Title = 'CLI tool';           Description = 'System.CommandLine' }
)

$config = [ordered]@{
    Name     = Resolve-Value $Name -Default (Split-Path -Leaf $PWD) -Prompt {
        Read-SpectreText -Message 'Project name' -DefaultAnswer (Split-Path -Leaf $PWD)
    }
    Template = Resolve-Value $Template -Default 'api' -Prompt {
        # Objects + escaped label script block: titles contain [ ] and the original object comes back
        $choice = Read-SpectreSelection -Message 'Template' -Choices $templates -EnableSearch -Color Cyan1 `
            -ChoiceLabelProperty { "$($_.Title | Get-SpectreEscapedText) [grey]- $($_.Description | Get-SpectreEscapedText)[/]" }
        $choice.Id
    }
    Features = @(Resolve-Value $Features -Default @() -Prompt {
        # -AllowEmpty returns an empty array; wrap it so "no features" isn't treated as cancel
        , @(Read-SpectreMultiSelection -Message 'Features [grey](space to toggle)[/]' -Choices 'Docker', 'CI', 'Tests', 'Docs' -AllowEmpty -PageSize 6)
    })
    Region   = Resolve-Value $Region -Default 'westeurope' -Prompt {
        Read-SpectreSelectionGrouped -Message 'Region' -Choices @{
            'Europe'   = @('westeurope', 'northeurope')
            'Americas' = @('eastus', 'westus2')
        }
    }
}

# Review
$config | Format-SpectreJson | Format-SpectrePanel -Header '[bold]Review[/]' -Color Cyan1 | Out-SpectreHost

$proceed = if ($Force) { $true }
           elseif ($interactive) { Read-SpectreConfirm -Message "Create [cyan1]$($config.Name | Get-SpectreEscapedText)[/]?" -DefaultAnswer y }
           else { Write-SpectreHost '[yellow]Non-interactive run without -Force: nothing created.[/]'; $false }

if ($proceed) {
    Write-SpectreHost "[green]✔[/] Created project [bold]$($config.Name | Get-SpectreEscapedText)[/] from template [bold]$($config.Template)[/]."
}
