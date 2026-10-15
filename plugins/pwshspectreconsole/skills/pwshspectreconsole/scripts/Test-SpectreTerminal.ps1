#Requires -Version 7.4
<#
.SYNOPSIS
    Diagnoses the current terminal for PwshSpectreConsole: module version, encoding, color depth,
    Unicode, interactivity, Sixel image support and size, with concrete fixes for anything missing.
.EXAMPLE
    pwsh -NoProfile -File ./Test-SpectreTerminal.ps1
.EXAMPLE
    ./Test-SpectreTerminal.ps1 -AsObject | ConvertTo-Json
#>
[CmdletBinding()]
param(
    # Return the results as an object instead of drawing a report.
    [switch] $AsObject
)

$module = Get-Module PwshSpectreConsole
if (-not $module) {
    $available = Get-Module PwshSpectreConsole -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $available) {
        Write-Warning "PwshSpectreConsole is not installed. Run: Install-Module PwshSpectreConsole -Scope CurrentUser"
        return
    }
    # Avoid the module's encoding banner; this script reports encoding itself.
    $env:IgnoreSpectreEncoding = $true
    $module = Import-Module PwshSpectreConsole -PassThru
}

$profileInfo = [Spectre.Console.AnsiConsole]::Profile
$caps = $profileInfo.Capabilities
$sixel = & $module { $script:TerminalSupportsSixel }

$checks = [ordered]@{
    ModuleVersion  = "$($module.Version)$(if ($module.PrivateData.PSData.Prerelease) { '-' + $module.PrivateData.PSData.Prerelease })"
    PowerShell     = $PSVersionTable.PSVersion.ToString()
    Terminal       = if ($env:WT_SESSION) { 'Windows Terminal' } elseif ($env:TERM_PROGRAM) { $env:TERM_PROGRAM } elseif ($env:TERM) { $env:TERM } else { 'unknown' }
    OutputEncoding = [Console]::OutputEncoding.WebName
    Unicode        = $caps.Unicode
    ColorSystem    = "$($caps.ColorSystem)"
    Ansi           = $caps.Ansi
    Links          = $caps.Links
    Interactive    = $caps.Interactive
    Sixel          = [bool] $sixel
    Width          = $profileInfo.Width
    Height         = $profileInfo.Height
    NoColor        = [bool] $env:NO_COLOR
}

$advice = [System.Collections.Generic.List[string]]::new()
if ($checks.OutputEncoding -ne 'utf-8' -or -not $checks.Unicode) {
    $advice.Add('Enable UTF-8 (add to $PROFILE): $OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()')
}
if ($checks.ColorSystem -ne 'TrueColor') {
    $advice.Add("Color depth is $($checks.ColorSystem). Images and hex colors look best in a 24-bit terminal (set COLORTERM=truecolor if your terminal supports it).")
}
if (-not $checks.Interactive) {
    $advice.Add('Not interactive: Read-Spectre* prompts will throw. Provide parameters/defaults for automation.')
}
if (-not $checks.Sixel) {
    $advice.Add('No Sixel detected: Get-SpectreImage falls back to block characters. Use a Sixel terminal (Windows Terminal 1.22+, WezTerm, iTerm2, foot, Konsole) for pixel images.')
}
if ($checks.Width -lt 80) {
    $advice.Add("Terminal is only $($checks.Width) columns: clamp -Width values to [Spectre.Console.AnsiConsole]::Profile.Width.")
}
if ($checks.NoColor) {
    $advice.Add('NO_COLOR is set: colors are disabled.')
}

if ($AsObject) {
    [pscustomobject]($checks + @{ Advice = @($advice) })
    return
}

function Format-Check([object] $Value, [bool] $Good) {
    $text = "$Value" | Get-SpectreEscapedText
    if ($Good) { "[green]$text[/]" } else { "[yellow]$text[/]" }
}

$report = [ordered]@{
    'Module'       = Format-Check $checks.ModuleVersion $true
    'PowerShell'   = Format-Check $checks.PowerShell $true
    'Terminal'     = Format-Check $checks.Terminal $true
    'Encoding'     = Format-Check $checks.OutputEncoding ($checks.OutputEncoding -eq 'utf-8')
    'Unicode'      = Format-Check $checks.Unicode $checks.Unicode
    'Colors'       = Format-Check $checks.ColorSystem ($checks.ColorSystem -eq 'TrueColor')
    'Interactive'  = Format-Check $checks.Interactive $checks.Interactive
    'Sixel images' = Format-Check $checks.Sixel $checks.Sixel
    'Size'         = Format-Check "$($checks.Width) x $($checks.Height)" ($checks.Width -ge 80)
}
$rows = foreach ($entry in $report.GetEnumerator()) {
    New-SpectreGridRow -Data @("[grey]$($entry.Key)[/]", $entry.Value)
}

$grid = Format-SpectreGrid -Data $rows -Padding 2
$items = @($grid)
if ($advice.Count) {
    $items += Write-SpectreRule 'Advice' -LineColor Grey -PassThru
    $items += $advice | ForEach-Object { Write-SpectreHost "[yellow]•[/] $($_ | Get-SpectreEscapedText)" -PassThru }
}
$items | Format-SpectreRows | Format-SpectrePanel -Header '[bold]PwshSpectreConsole terminal check[/]' | Out-SpectreHost | Out-Host

$imagePath = Join-Path $module.ModuleBase 'smiley.png'
if (Test-Path $imagePath) {
    $samples = foreach ($format in 'Blocks', 'Braille', 'Canvas') {
        @((Get-SpectreImage $imagePath -MaxWidth 10 -Format $format), "[grey]$format[/]") | Format-SpectreRows
    }
    if ($checks.Sixel) {
        $samples += @((Get-SpectreImage $imagePath -MaxWidth 10 -Format Sixel), '[grey]Sixel[/]') | Format-SpectreRows
    }
    $samples | Format-SpectreColumns -Padding 3 | Format-SpectrePanel -Header '[bold]Image render modes[/]' | Out-SpectreHost | Out-Host
}
