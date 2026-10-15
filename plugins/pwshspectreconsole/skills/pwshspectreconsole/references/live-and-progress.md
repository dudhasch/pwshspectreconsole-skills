# Progress, status spinners and live displays

All three run a script block while Spectre owns part of the screen. Shared rules:

- The script block receives a **context** object as its first argument: `param($Context)`.
- **Whatever the script block outputs is the return value** of the `Invoke-*` cmdlet. Stray output
  (un-captured method results, `Write-Output`) ends up in your result - use `$null =` / `[void]`.
- **Don't write to the console** with `Write-Host`, `Format-Table`, `Out-Host`, native exe output, or
  other progress bars while the display is active - it corrupts the redraw. Allowed:
  `Write-SpectreHost` inside a *status* spinner (prints above it) and updating the live renderable.
- Commands that insist on writing to the host (installers, git, some modules): wrap them in
  `Invoke-SpectreScriptBlockQuietly -Command { ... }` (runs in a thread job and returns only the output;
  `-Level Quieter` discards output too) or redirect: `& git pull *> $null`. Under
  `$ErrorActionPreference = 'Stop'` errors written by the quiet block are re-thrown; pass `-ErrorAction Continue`
  to ignore them.
- Variables from the calling scope are readable inside the block. To change state outside, return it or
  use a reference type (hashtable/list) created outside.
- Nesting live displays (a spinner inside a progress block, etc.) is not supported by Spectre.Console - it throws.
- In non-interactive hosts (CI, redirected output) there is no cursor control: spinners print their title,
  progress bars print nothing, and **live displays print every `Refresh()` as a new copy** (noisy logs).
  The script block still runs and returns normally. Check
  `[Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive` and refresh less (or render once at the end)
  when it's `$false`.

## Status spinner - unknown duration, single activity

```powershell
$result = Invoke-SpectreCommandWithStatus -Title "Connecting..." -Spinner Dots2 -Color Cyan1 -ScriptBlock {
    param($Context)                                  # Spectre.Console.StatusContext
    Start-Sleep -Seconds 1
    Write-SpectreHost "[grey]LOG:[/] connected"      # log lines appear above the spinner
    $Context.Status = "Downloading manifest..."      # change the title text (markup)
    $Context.Spinner = [Spectre.Console.Spinner+Known]::Star
    Start-Sleep -Seconds 1
    return @{ Items = 42 }                           # becomes $result
}
Write-SpectreHost "Got [green]$($result.Items)[/] items"
```

Spinners (90+, tab-completes): `Dots` (default), `Dots2`..`Dots14`, `Line`, `Star`, `Arc`, `Circle`,
`BouncingBar`, `BouncingBall`, `Clock`, `Earth`, `Moon`, `Runner`, `Aesthetic`, `Ascii` (safe for non-UTF-8 hosts).
Full list: `([Spectre.Console.Spinner+Known].GetProperties('Public,Static')).Name`.

## Progress bars - known amount of work

```powershell
$files = Get-ChildItem -File
$copied = Invoke-SpectreCommandWithProgress -ScriptBlock {
    param($Context)                                       # Spectre.Console.ProgressContext
    $task = $Context.AddTask("Copying $($files.Count) files")   # markup; returns a ProgressTask
    $task.MaxValue = $files.Count                         # default MaxValue is 100
    $done = foreach ($f in $files) {
        Copy-Item $f.FullName -Destination $dest
        $task.Increment(1)
        $f.Name                                           # collected into $done
    }
    $done                                                 # return value
}
```

`ProgressTask` members you'll use: `Increment(n)`, `Value`, `MaxValue`, `Percentage`, `IsIndeterminate`,
`Description` (rename while running), `StopTask()`, `IsFinished`.
Indeterminate (pulsing) bar: `$task.IsIndeterminate = $true`, set `$task.Value = $task.MaxValue` when done.

Several bars:

```powershell
Invoke-SpectreCommandWithProgress -ScriptBlock {
    param($Context)
    $download = $Context.AddTask("Download")
    $extract  = $Context.AddTask("Extract")
    while (-not $Context.IsFinished) {
        $download.Increment(7); if ($download.Value -ge 50) { $extract.Increment(5) }
        Start-Sleep -Milliseconds 100
    }
}
```

### Background jobs with progress

`Add-SpectreJob` + `Wait-SpectreJobs` map PowerShell jobs onto bars. A job's `Write-Progress -PercentComplete`
drives its bar; otherwise `-EstimatedDurationSeconds` fakes progress then switches to indeterminate.

```powershell
$results = Invoke-SpectreCommandWithProgress -ScriptBlock {
    param($Context)
    $jobs = @(
        Add-SpectreJob -Context $Context -JobName "api"    -Job (Start-ThreadJob { & ./build.ps1 api })
        Add-SpectreJob -Context $Context -JobName "worker" -Job (Start-ThreadJob { & ./build.ps1 worker })
    )
    Wait-SpectreJobs -Context $Context -Jobs $jobs -TimeoutSeconds 600 -EstimatedDurationSeconds 60
    $jobs.Job | Receive-Job -Wait -AutoRemoveJob -ProgressAction SilentlyContinue
}
```

`Wait-SpectreJobs` **throws after `-TimeoutSeconds` (default 60)** - raise it for long jobs.
`Receive-Job` replays the job's `Write-Progress` records, which draws PowerShell's own progress bar under
the Spectre output - pass `-ProgressAction SilentlyContinue` (or set `$ProgressPreference` in the block).

`ForEach-Object -Parallel -AsJob`: poll `$job.ChildJobs` state and increment a single task (see module docs example 5).

## Live display - redraw any renderable in place

`Invoke-SpectreLive -Data $renderable -ScriptBlock { param($Context) ... }` draws `$renderable`, runs the
block, and redraws whenever you call `$Context.Refresh()`. **Mutate the same object** (tables, layouts)
rather than creating a new one - the live display holds a reference to the original.

```powershell
$table = [Spectre.Console.Table]::new()
[void]$table.AddColumn('Service'); [void]$table.AddColumn('Status')

Invoke-SpectreLive -Data $table -ScriptBlock {
    param($Context)                                   # Spectre.Console.LiveDisplayContext
    $i = 0
    foreach ($svc in 'api', 'worker', 'web') {
        [void][Spectre.Console.TableExtensions]::AddRow($table, [string[]]@($svc, '[yellow]deploying[/]'))
        $Context.Refresh()
        Start-Sleep -Milliseconds 500
        [void][Spectre.Console.TableExtensions]::UpdateCell($table, $i, 1, '[green]done[/]')
        $Context.Refresh()
        $i++
    }
}
```

To swap the whole content: `$Context.UpdateTarget($newRenderable); $Context.Refresh()`.

Rows in a growing live table taller than the terminal get cut off ("..."); keep only the last N rows
(`$table.Rows.RemoveAt(0)`) or show a summary.

### Full-screen dashboard (layout + keyboard)

```powershell
$layout = New-SpectreLayout -Name root -Rows @(
    (New-SpectreLayout -Name header -MinimumSize 3 -Ratio 1 -Data ' '),
    (New-SpectreLayout -Name body -Ratio 8 -Data ' ')
)
Invoke-SpectreLive -Data $layout -ScriptBlock {
    param($Context)
    [Console]::TreatControlCAsInput = $true          # so Ctrl+C reaches ReadKey
    try {
        while ($true) {
            # 1. input (non-blocking)
            $key = $null
            while ([Console]::KeyAvailable) { $key = [Console]::ReadKey($true) }
            if ($key.Key -in 'Escape', 'Q' -or ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control')) { break }

            # 2. state -> renderables
            $header = "[bold]Monitor[/] [grey]$(Get-Date -Format T) - q to quit[/]" | Format-SpectreAligned | Format-SpectrePanel -Expand
            $procs  = Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 Name, Id, CPU |
                      Format-SpectreTable -Expand -Border Minimal

            # 3. update regions, redraw
            $layout['header'].Update($header) | Out-Null
            $layout['body'].Update($procs) | Out-Null
            $Context.Refresh()
            Start-Sleep -Milliseconds 250
        }
    } finally { [Console]::TreatControlCAsInput = $false }
}
```

Tips:
- Size content to regions with `$layout | Get-SpectreLayoutSizes` (see `layout.md`).
- Keep each frame cheap; cache expensive data and refresh it every N iterations.
- Don't call `Read-Spectre*` prompts inside a live display; build your own input handling as above.
- `[Console]::KeyAvailable`/`ReadKey` need a real console (they throw when input is redirected).
