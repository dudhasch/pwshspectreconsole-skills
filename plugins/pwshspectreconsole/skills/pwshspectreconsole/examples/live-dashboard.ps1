#Requires -Version 7.4
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Full-screen live dashboard: header, process table, CPU history chart and an event log, with keyboard input.
.DESCRIPTION
    Demonstrates: New-SpectreLayout with named leaf regions, Invoke-SpectreLive, sizing content to regions
    with Get-SpectreLayoutSizes, non-blocking keyboard handling, Ctrl+C handling, cleanup in finally,
    and a time limit so the script can run unattended.
    Keys: q / Esc / Ctrl+C quit, s toggles the sort column.
.EXAMPLE
    ./live-dashboard.ps1
.EXAMPLE
    ./live-dashboard.ps1 -DurationSeconds 5      # exits by itself (e.g. demos, CI)
#>
[CmdletBinding()]
param(
    [int] $DurationSeconds = 0,
    [ValidateRange(100, 5000)]
    [int] $RefreshMilliseconds = 500
)

$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
# Import only if not loaded: a second version in the same session fails ("Assembly with same name is already loaded")
if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }

$layout = New-SpectreLayout -Name root -Rows @(
    (New-SpectreLayout -Name header -MinimumSize 3 -Ratio 1 -Data ' '),
    (New-SpectreLayout -Name main -Ratio 8 -Columns @(
        (New-SpectreLayout -Name processes -Ratio 3 -Data ' '),
        (New-SpectreLayout -Name side -Ratio 2 -Rows @(
            (New-SpectreLayout -Name cpu -Ratio 1 -Data ' '),
            (New-SpectreLayout -Name log -Ratio 1 -Data ' ')
        ))
    ))
)

$canReadKeys = -not [Console]::IsInputRedirected
$state = @{
    SortBy  = 'CPU'
    Log     = [System.Collections.Generic.Queue[string]]::new()
    Samples = [System.Collections.Generic.Queue[double]]::new()
    Started = Get-Date
}

function Add-LogLine([string] $Markup) {
    $state.Log.Enqueue("[grey]$(Get-Date -Format HH:mm:ss)[/] $Markup")
    while ($state.Log.Count -gt 50) { [void]$state.Log.Dequeue() }
}

function Get-HeaderPanel {
    $elapsed = (Get-Date) - $state.Started
    $keys = if ($canReadKeys) { '[grey]q[/] quit  [grey]s[/] sort' } else { '[grey]input redirected[/]' }
    "[bold cyan1]Process monitor[/]  sort: [yellow]$($state.SortBy)[/]  uptime: $('{0:mm\:ss}' -f $elapsed)    $keys" |
        Format-SpectreAligned -HorizontalAlignment Left -VerticalAlignment Middle |
        Format-SpectrePanel -Expand -Color Cyan1
}

function Get-ProcessPanel([int] $Rows) {
    $procs = Get-Process | Sort-Object -Property $(if ($state.SortBy -eq 'CPU') { 'CPU' } else { 'WorkingSet64' }) -Descending |
        Select-Object -First ([Math]::Max(1, $Rows))
    $procs | Format-SpectreTable -Expand -Border Minimal -Property @(
        @{ Name = 'Name'; Expression = { $_.ProcessName } }
        @{ Name = 'PID'; Expression = { $_.Id } }
        @{ Name = 'CPU s'; Expression = { [math]::Round($_.CPU, 1) } }
        @{ Name = 'MB'; Expression = { [math]::Round($_.WorkingSet64 / 1MB) } }
    ) | Format-SpectrePanel -Header '[bold]Processes[/]' -Expand
}

function Get-CpuPanel([int] $Width) {
    $values = @($state.Samples)
    if ($values.Count -eq 0) { return '[grey]collecting...[/]' | Format-SpectrePanel -Header '[bold]CPU time delta[/]' -Expand }
    $i = 0
    $items = $values | Select-Object -Last 8 | ForEach-Object {
        $color = if ($_ -gt 50) { 'Red' } elseif ($_ -gt 10) { 'Yellow' } else { 'Green' }
        New-SpectreChartItem -Label "t-$((8 - $i++))" -Value ([math]::Round($_, 1)) -Color $color
    }
    $items | Format-SpectreBarChart -Width ([Math]::Max(10, $Width - 4)) |
        Format-SpectrePanel -Header '[bold]CPU time delta (s)[/]' -Expand
}

function Get-LogPanel([int] $Lines) {
    $text = (@($state.Log) | Select-Object -Last ([Math]::Max(1, $Lines))) -join "`n"
    if (-not $text) { $text = '[grey]no events[/]' }
    Write-SpectreHost $text -PassThru | Format-SpectrePanel -Header '[bold]Events[/]' -Expand
}

Add-LogLine '[green]started[/]'
$previousCpu = (Get-Process | Measure-Object CPU -Sum).Sum

Invoke-SpectreLive -Data $layout -ScriptBlock {
    param($Context)
    if ($canReadKeys) { [Console]::TreatControlCAsInput = $true }
    try {
        while ($true) {
            # 1. input (drain all pending keys, never block)
            if ($canReadKeys) {
                while ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -in 'Q', 'Escape' -or ($key.Key -eq 'C' -and $key.Modifiers -band [ConsoleModifiers]::Control)) { return }
                    if ($key.Key -eq 'S') {
                        $state.SortBy = if ($state.SortBy -eq 'CPU') { 'Memory' } else { 'CPU' }
                        Add-LogLine "sort by [yellow]$($state.SortBy)[/]"
                    }
                }
            }
            if ($DurationSeconds -gt 0 -and ((Get-Date) - $state.Started).TotalSeconds -ge $DurationSeconds) { return }

            # 2. sample data
            $cpu = (Get-Process | Measure-Object CPU -Sum).Sum
            $delta = [Math]::Max(0, $cpu - $previousCpu)
            $previousCpu = $cpu
            $state.Samples.Enqueue($delta)
            while ($state.Samples.Count -gt 8) { [void]$state.Samples.Dequeue() }
            if ($delta -gt 50) { Add-LogLine "[red]CPU spike[/] $([math]::Round($delta, 1))s" }

            # 3. size content to the regions, update leaf layouts, redraw
            $sizes = $layout | Get-SpectreLayoutSizes
            $layout['header'].Update((Get-HeaderPanel)) | Out-Null
            $layout['processes'].Update((Get-ProcessPanel -Rows ($sizes['processes'].Height - 5))) | Out-Null
            $layout['cpu'].Update((Get-CpuPanel -Width $sizes['cpu'].Width)) | Out-Null
            $layout['log'].Update((Get-LogPanel -Lines ($sizes['log'].Height - 2))) | Out-Null
            $Context.Refresh()

            Start-Sleep -Milliseconds $RefreshMilliseconds
        }
    } finally {
        if ($canReadKeys) { [Console]::TreatControlCAsInput = $false }
    }
}
Write-SpectreHost '[grey]Dashboard closed.[/]'
