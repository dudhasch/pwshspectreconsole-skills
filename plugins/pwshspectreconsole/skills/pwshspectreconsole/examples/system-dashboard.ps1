#Requires -Version 7.4
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Static system report: header, info grid, image, process table, disk breakdown and memory bar chart.
.DESCRIPTION
    Demonstrates: building renderables first and rendering once, escaping dynamic data, colored table
    cells with -AllowMarkup, right-aligned columns, chart items, images composed with text, panels,
    rows and columns, and width-aware layout.
.EXAMPLE
    ./system-dashboard.ps1
.EXAMPLE
    ./system-dashboard.ps1 -ImagePath ./logo.png -Top 5
#>
[CmdletBinding()]
param(
    # Image shown in the header. Defaults to the sample image shipped with the module.
    [string] $ImagePath = (Join-Path (Get-Module PwshSpectreConsole -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1).ModuleBase 'smiley.png'),
    [ValidateRange(1, 30)]
    [int] $Top = 8
)

$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
# Import only if not loaded: a second version in the same session fails ("Assembly with same name is already loaded")
if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }

$consoleWidth = [Spectre.Console.AnsiConsole]::Profile.Width

# ---------- header: image + info grid side by side ----------
$info = [ordered]@{
    Host     = [Environment]::MachineName
    User     = [Environment]::UserName
    OS       = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    Shell    = "PowerShell $($PSVersionTable.PSVersion)"
    Uptime   = '{0:%d}d {0:hh}h {0:mm}m' -f [TimeSpan]::FromMilliseconds([Environment]::TickCount64)
    CPUs     = [Environment]::ProcessorCount
}
$infoRows = foreach ($entry in $info.GetEnumerator()) {
    New-SpectreGridRow -Data @("[grey]$($entry.Key)[/]", ("$($entry.Value)" | Get-SpectreEscapedText))
}
$infoGrid = Format-SpectreGrid -Data $infoRows -Padding 2

$titleAndInfo = @(
    (Write-SpectreFigletText -Text 'System' -Color Cyan1 -PassThru),
    $infoGrid
) | Format-SpectreRows
# A grid keeps image and text side by side (Format-SpectreColumns would wrap them when space is tight)
$headerContent = if (Test-Path $ImagePath) {
    Format-SpectreGrid -Data (New-SpectreGridRow -Data @((Get-SpectreImage -ImagePath $ImagePath -MaxWidth 14), $titleAndInfo)) -Padding 3
} else {
    $titleAndInfo
}
$header = $headerContent | Format-SpectrePanel -Header '[bold]Overview[/]' -Color Cyan1 -Expand

# ---------- process table: markup cells, escaped names, right-aligned numbers ----------
$processes = Get-Process | Where-Object { $_.CPU } | Sort-Object CPU -Descending | Select-Object -First $Top
$processTable = $processes | Format-SpectreTable -AllowMarkup -Border Rounded -Color Grey -Property @(
    @{ Name = 'Process'; Expression = { $_.ProcessName | Get-SpectreEscapedText } }
    @{ Name = 'PID'; Expression = { $_.Id } }
    @{ Name = 'CPU (s)'; Expression = {
            $cpu = [math]::Round($_.CPU, 1)
            $color = if ($cpu -gt 100) { 'red' } elseif ($cpu -gt 10) { 'yellow' } else { 'green' }
            "[$color]$cpu[/]"
        } }
    @{ Name = 'Memory'; Expression = { '{0:N0} MB' -f ($_.WorkingSet64 / 1MB) } }
)
# Alignment in calculated properties is ignored - set it on the columns
foreach ($i in 1..3) { $processTable.Columns[$i].Alignment = [Spectre.Console.Justify]::Right }
$processPanel = $processTable | Format-SpectrePanel -Header "[bold]Top $Top processes by CPU[/]" -Border None

# ---------- disk breakdown (cross-platform) ----------
$diskCharts = [System.IO.DriveInfo]::GetDrives() |
    Where-Object { $_.IsReady -and $_.TotalSize -ge 1GB -and $_.DriveType -in 'Fixed', 'Network' } |
    Select-Object -First 3 |
    ForEach-Object {
        $usedGb = [math]::Round(($_.TotalSize - $_.AvailableFreeSpace) / 1GB, 1)
        $freeGb = [math]::Round($_.AvailableFreeSpace / 1GB, 1)
        $usedColor = if ($_.AvailableFreeSpace / $_.TotalSize -lt 0.1) { 'Red' } else { 'Orange1' }
        $chart = @(
            New-SpectreChartItem -Label 'Used GB' -Value $usedGb -Color $usedColor
            New-SpectreChartItem -Label 'Free GB' -Value $freeGb -Color Green
        ) | Format-SpectreBreakdownChart -Width ([Math]::Min(50, $consoleWidth - 10))
        @("[bold]$($_.Name | Get-SpectreEscapedText)[/]", $chart) | Format-SpectreRows
    }
$diskPanel = $diskCharts | Format-SpectreRows | Format-SpectrePanel -Header '[bold]Disks[/]' -Color Orange1

# ---------- memory bar chart ----------
$palette = 'Cyan1', 'DeepSkyBlue1', 'SteelBlue1', 'SlateBlue1', 'MediumPurple1', 'Orchid'
$i = 0
$memoryChart = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 6 | ForEach-Object {
    New-SpectreChartItem -Label ($_.ProcessName | Get-SpectreEscapedText) -Value ([math]::Round($_.WorkingSet64 / 1MB)) -Color $palette[$i++ % $palette.Count]
} | Format-SpectreBarChart -Label 'Working set (MB)' -Width ([Math]::Min(60, $consoleWidth - 6))
$memoryPanel = $memoryChart | Format-SpectrePanel -Header '[bold]Memory[/]' -Color SlateBlue1

# ---------- compose and render once ----------
$body = if ($consoleWidth -ge 140) {
    @($diskPanel, $memoryPanel) | Format-SpectreColumns
} else {
    @($diskPanel, $memoryPanel) | Format-SpectreRows
}

@(
    $header
    $processPanel
    $body
    (Write-SpectreRule "[grey]generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')[/]" -Alignment Right -PassThru)
) | Format-SpectreRows | Out-SpectreHost
