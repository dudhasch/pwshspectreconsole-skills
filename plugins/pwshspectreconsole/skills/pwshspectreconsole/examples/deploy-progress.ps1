#Requires -Version 7.4
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Simulated deployment showing a status spinner, parallel progress bars driven by thread jobs,
    a live-updating results table and a summary panel.
.DESCRIPTION
    Demonstrates: returning data out of Invoke-* script blocks, never writing to the host while a live
    widget is active, Write-SpectreHost logging under a spinner, Add-SpectreJob/Wait-SpectreJobs,
    mutating a table inside Invoke-SpectreLive with static extension-method calls.
    Safe to run non-interactively (CI): widgets degrade to static output.
.EXAMPLE
    ./deploy-progress.ps1 -Services api, worker, web
#>
[CmdletBinding()]
param(
    [string[]] $Services = @('api', 'worker', 'web', 'scheduler'),
    [ValidateRange(0.1, 10)]
    [double] $Speed = 1
)

$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
# Import only if not loaded: a second version in the same session fails ("Assembly with same name is already loaded")
if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }

Write-SpectreRule '[bold]Deploy[/]' -Alignment Left -LineColor Grey

# 1) Status spinner: unknown duration, log lines above the spinner, return value comes back out
$plan = Invoke-SpectreCommandWithStatus -Title 'Resolving deployment plan...' -Spinner Dots2 -Color Cyan1 -ScriptBlock {
    param($Context)
    Start-Sleep -Milliseconds (400 / $Speed)
    Write-SpectreHost '[grey]LOG:[/] connected to cluster'
    $Context.Status = 'Reading manifests...'
    Start-Sleep -Milliseconds (400 / $Speed)
    Write-SpectreHost "[grey]LOG:[/] found [cyan1]$($Services.Count)[/] services"
    # Everything output here becomes $plan
    foreach ($svc in $Services) {
        [pscustomobject]@{ Service = $svc; Steps = Get-Random -Minimum 5 -Maximum 12 }
    }
}

# 2) Progress: one bar per service, each driven by a thread job reporting Write-Progress
$results = Invoke-SpectreCommandWithProgress -ScriptBlock {
    param($Context)
    $jobs = foreach ($item in $plan) {
        Add-SpectreJob -Context $Context -JobName "Building [bold]$($item.Service | Get-SpectreEscapedText)[/]" -Job (
            Start-ThreadJob -ArgumentList $item.Service, $item.Steps, $Speed -ScriptBlock {
                param($Service, $Steps, $Speed)
                for ($s = 1; $s -le $Steps; $s++) {
                    Start-Sleep -Milliseconds ((Get-Random -Minimum 80 -Maximum 250) / $Speed)
                    Write-Progress -Activity $Service -PercentComplete ($s / $Steps * 100)
                }
                [pscustomobject]@{ Service = $Service; Image = "$($Service):$(Get-Random -Minimum 100 -Maximum 999)"; Ok = (Get-Random -Maximum 10) -gt 0 }
            }
        )
    }
    Wait-SpectreJobs -Context $Context -Jobs $jobs -TimeoutSeconds 300
    # -ProgressAction: don't replay the jobs' Write-Progress records as a native PowerShell progress bar
    $jobs.Job | Receive-Job -Wait -AutoRemoveJob -ProgressAction SilentlyContinue   # becomes $results
}

# 3) Live table: rollout, mutating ONE table object and refreshing
$table = [Spectre.Console.Table]::new()
$table.Border = [Spectre.Console.TableBorder]::Rounded
$table.BorderStyle = [Spectre.Console.Style]::new([Spectre.Console.Color]::Grey)
[void]$table.AddColumn('[bold]Service[/]')
[void]$table.AddColumn('[bold]Image[/]')
[void]$table.AddColumn('[bold]Status[/]')

$rollout = Invoke-SpectreLive -Data $table -ScriptBlock {
    param($Context)
    $row = 0
    $summary = @{ Ok = 0; Failed = 0 }
    foreach ($r in $results) {
        $cells = [Spectre.Console.Rendering.IRenderable[]]@(
            [Spectre.Console.Text]::new($r.Service),          # Text = literal, no escaping needed
            [Spectre.Console.Text]::new($r.Image),
            [Spectre.Console.Markup]::new('[yellow]rolling out...[/]')
        )
        [void][Spectre.Console.TableExtensions]::AddRow($table, $cells)
        $Context.Refresh()
        Start-Sleep -Milliseconds (500 / $Speed)

        $status = if ($r.Ok) { $summary.Ok++; '[green]✔ healthy[/]' } else { $summary.Failed++; '[red]✘ failed[/]' }
        [void][Spectre.Console.TableExtensions]::UpdateCell($table, $row, 2, $status)
        $Context.Refresh()
        $row++
    }
    $summary                                                 # becomes $rollout
}

# 4) Summary (render once, after all live widgets have finished)
$color = if ($rollout.Failed) { 'Red' } else { 'Green' }
$message = if ($rollout.Failed) {
    "[red]$($rollout.Failed)[/] of $($results.Count) services failed health checks."
} else {
    "All [green]$($rollout.Ok)[/] services deployed."
}
$message | Format-SpectrePanel -Header '[bold]Result[/]' -Color $color | Out-SpectreHost
