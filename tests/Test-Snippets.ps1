#Requires -Version 7.4
<#
.SYNOPSIS
    Executes the code patterns documented in the skill references against the installed
    PwshSpectreConsole module and reports which ones fail.
.DESCRIPTION
    Runs non-interactively (prompts are only checked for their non-interactive failure mode).
    Exit code = number of failed checks.
.EXAMPLE
    pwsh -NoProfile -File ./tests/Test-Snippets.ps1
#>
param(
    [string] $ModuleVersion
)
$ErrorActionPreference = 'Stop'
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$env:IgnoreSpectreEncoding = $true

$importArgs = @{ Name = 'PwshSpectreConsole' }
if ($ModuleVersion) { $importArgs.RequiredVersion = $ModuleVersion }
Import-Module @importArgs
$module = Get-Module PwshSpectreConsole
$smiley = Join-Path $module.ModuleBase 'smiley.png'

$script:failures = [System.Collections.Generic.List[string]]::new()
$script:passed = 0

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    try {
        $out = & $Body | Out-String
        $script:passed++
        Write-Host "PASS  $Name" -ForegroundColor Green
        return $out
    } catch {
        $script:failures.Add("$Name :: $($_.Exception.Message)")
        Write-Host "FAIL  $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw "Assertion failed: $Message" } }
function Assert-Throws([scriptblock] $Body, [string] $Message) {
    $threw = $false
    try { & $Body | Out-Null } catch { $threw = $true }
    if (-not $threw) { throw "Expected an exception: $Message" }
}

Write-Host "PwshSpectreConsole $($module.Version) $($module.PrivateData.PSData.Prerelease) on PowerShell $($PSVersionTable.PSVersion)"

# ---------------- markup-and-output.md ----------------
Test-Case 'markup: styles, colors, links, emoji, escaped brackets' {
    $o = Write-SpectreHost "[bold]B[/] [#ff8800]hex[/] [rgb(0,135,255)]rgb[/] [white on DarkRed] inv [/] [link=https://x.y]l[/] :rocket: [[lit]]" -PassThru | Out-SpectreHost
    Assert-True ($o -like '*[lit]*') 'doubled brackets render as literal'
}
Test-Case 'markup: unescaped data throws, escaped works' {
    Assert-Throws { Write-SpectreHost "[green]ok[/] [admin]" } 'unescaped [admin]'
    Write-SpectreHost "[green]ok[/] $('[admin]' | Get-SpectreEscapedText)" -PassThru | Out-SpectreHost | Out-Null
}
Test-Case 'markup: string without [/] is literal in a panel' {
    $o = '[red]oops' | Format-SpectrePanel | Out-SpectreHost
    Assert-True ($o -like '*`[red`]oops*') 'literal markup'
}
Test-Case 'output: Out-SpectreHost returns a string; Out-Host keeps function output clean' {
    function Get-Dirty { 'a' | Format-SpectrePanel | Out-SpectreHost; 42 }
    function Get-Clean { 'a' | Format-SpectrePanel | Out-SpectreHost | Out-Host; 42 }
    Assert-True (@(Get-Dirty).Count -eq 2) 'dirty returns 2 items'
    Assert-True (@(Get-Clean).Count -eq 1) 'clean returns 1 item'
}
Test-Case 'colors: name, hex, object, ToMarkup' {
    'x' | Format-SpectrePanel -Color Red | Out-Null
    'x' | Format-SpectrePanel -Color '#ff8800' | Out-Null
    'x' | Format-SpectrePanel -Color ([Spectre.Console.Color]::new(255, 136, 0)) | Out-Null
    $c = [Spectre.Console.Color]::Orange1
    Write-SpectreHost "[$($c.ToMarkup())]t[/]" -PassThru | Out-SpectreHost | Out-Null
}
Test-Case 'profile: capabilities readable' {
    $p = [Spectre.Console.AnsiConsole]::Profile
    Assert-True ($p.Width -gt 0) 'width'
    $null = $p.Capabilities.ColorSystem, $p.Capabilities.Unicode, $p.Capabilities.Interactive
}

# ---------------- tables.md ----------------
Test-Case 'tables: calculated properties, title, border' {
    Get-ChildItem $PSHOME -File | Select-Object -First 3 | Format-SpectreTable -Title Files -Border Square -Property @(
        @{ Name = 'File'; Expression = { $_.Name }; Width = 30 }
        @{ Name = 'Size'; Expression = { '{0:N1} KB' -f ($_.Length / 1KB) } }
    ) | Out-SpectreHost | Out-Null
}
Test-Case 'tables: scalar + hashtable input' {
    1..3 | Format-SpectreTable | Out-SpectreHost | Out-Null
    @{ Server = 'web01'; Status = 'Up' } | Format-SpectreTable | Out-SpectreHost | Out-Null
}
Test-Case 'tables: alignment via Columns[i]' {
    $t = Get-ChildItem $PSHOME -File | Select-Object -First 3 Name, Length | Format-SpectreTable
    $t.Columns[1].Alignment = [Spectre.Console.Justify]::Right
    $t.Columns[1].NoWrap = $true
    $t.Columns[1].Width = 12
    $t | Out-SpectreHost | Out-Null
}
Test-Case 'tables: -AllowMarkup with escaped data' {
    @([pscustomobject]@{ Name = '[x]'; Status = 'Running' }) | Format-SpectreTable -AllowMarkup -Property @(
        @{ Name = 'Name'; Expression = { $_.Name | Get-SpectreEscapedText } }
        @{ Name = 'Status'; Expression = { if ($_.Status -eq 'Running') { '[green]● Running[/]' } else { '[red]x[/]' } } }
    ) | Out-SpectreHost | Out-Null
    Assert-Throws { [pscustomobject]@{ Name = '[x]' } | Format-SpectreTable -AllowMarkup | Out-SpectreHost } 'unescaped AllowMarkup'
}
Test-Case 'tables: nested renderables in [ordered] rows, not pscustomobject' {
    $img = Get-SpectreImage $smiley -MaxWidth 6
    $chart = New-SpectreChartItem -Label CPU -Value 63 -Color Orange1 | Format-SpectreBarChart -Width 30
    $o = @([ordered]@{ Icon = $img; Name = 'web01'; Load = $chart }, [ordered]@{ Icon = $img; Name = 'web02'; Load = $chart }) |
        Format-SpectreTable | Out-SpectreHost
    Assert-True ($o -notlike '*Spectre.Console*') 'hashtable rows render widgets'
    $bad = [pscustomobject]@{ Load = $chart } | Format-SpectreTable | Out-SpectreHost
    Assert-True ($bad -like '*Spectre.Console.BarChart*') 'pscustomobject stringifies (documented pitfall)'
}
Test-Case 'tables: Add-SpectreTableRow + UpdateCell' {
    $t = [pscustomobject]@{ Name = 'a'; Status = 'ok' } | Format-SpectreTable -AllowMarkup
    $t = Add-SpectreTableRow -Table $t -Columns 'web03', '[green]ok[/]'
    $t = Add-SpectreTableRow -Table $t -Columns 'web04', (Get-SpectreImage $smiley -MaxWidth 4)
    [void][Spectre.Console.TableExtensions]::UpdateCell($t, 0, 1, '[red]down[/]')
    Assert-Throws { $t.UpdateCell(0, 1, 'x') } 'instance call of extension method'
    $t | Out-SpectreHost | Out-Null
}
Test-Case 'tables: raw .NET table' {
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::new([Spectre.Console.Color]::Grey)
    $table.Title = [Spectre.Console.TableTitle]::new('[bold]Deployments[/]')
    $table.Caption = [Spectre.Console.TableTitle]::new('[dim]updated just now[/]')
    $table.Expand = $true
    [void]$table.AddColumn('[bold]Service[/]')
    $col = [Spectre.Console.TableColumn]::new('[bold]Duration[/]')
    $col.Alignment = [Spectre.Console.Justify]::Right
    [void]$table.AddColumn($col)
    [void][Spectre.Console.TableExtensions]::AddRow($table, [string[]]@('api', '12s'))
    [void][Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
        [Spectre.Console.Text]::new('worker [beta]'), [Spectre.Console.Markup]::new('[green]8s[/]')))
    [void][Spectre.Console.TableExtensions]::AddEmptyRow($table)
    $o = $table | Out-SpectreHost
    Assert-True ($o -like '*worker `[beta`]*') 'Text is literal'
}

# ---------------- layout.md ----------------
Test-Case 'layout: panel, rows, columns, grid, padded, aligned' {
    'Deployed [green]3[/] services' | Format-SpectrePanel -Header '[bold]Summary[/]' -Color Green | Out-SpectreHost | Out-Null
    $img = Get-SpectreImage $smiley -MaxWidth 8
    @('[bold]Logo[/]', $img) | Format-SpectreRows | Format-SpectrePanel | Out-SpectreHost | Out-Null
    @(('a' | Format-SpectrePanel), ('b' | Format-SpectrePanel)) | Format-SpectreColumns | Out-SpectreHost | Out-Null
    @((Write-SpectreFigletText 'Report' -PassThru), (Write-SpectreRule 'Summary' -PassThru)) | Format-SpectreRows | Out-SpectreHost | Out-Null
    Format-SpectreGrid -Data @(
        (New-SpectreGridRow @('[grey]Host[/]', [Environment]::MachineName))
        (New-SpectreGridRow @('[grey]PS[/]', $PSVersionTable.PSVersion.ToString()))
    ) -Padding 2 | Out-SpectreHost | Out-Null
    'Centered' | Format-SpectreAligned -HorizontalAlignment Center | Format-SpectrePanel -Expand | Out-SpectreHost | Out-Null
    $img | Format-SpectrePadded -Top 1 -Left 4 -Bottom 1 -Right 4 | Out-SpectreHost | Out-Null
    $img | Format-SpectrePadded -Padding 2 | Out-SpectreHost | Out-Null
}
Test-Case 'layout: New-SpectreLayout, Update, sizes, full height' {
    $layout = New-SpectreLayout -Name root -Rows @(
        (New-SpectreLayout -Name header -MinimumSize 3 -Ratio 1 -Data 'loading...'),
        (New-SpectreLayout -Name body -Ratio 6 -Columns @(
            (New-SpectreLayout -Name left -Ratio 1 -Data 'left'),
            (New-SpectreLayout -Name right -Ratio 2 -Data 'right')
        ))
    )
    $layout['header'].Update(('[bold]My App[/]' | Format-SpectreAligned | Format-SpectrePanel -Expand)) | Out-Null
    $sizes = $layout | Get-SpectreLayoutSizes
    Assert-True ($sizes['body'].Height -gt 0 -and $sizes['right'].Width -gt $sizes['left'].Width) 'sizes'
    $layout['left'].Update(('left' | Format-SpectrePanel -Expand)) | Out-Null
    # Out-SpectreHost trims trailing blank lines, so use an expanded panel to make the full height visible
    $lines = ($layout | Out-SpectreHost) -split "`n"
    Assert-True ($lines.Count -eq [Spectre.Console.AnsiConsole]::Profile.Height) "layout fills console height ($($lines.Count))"
}
Test-Case 'layout: Get-SpectreRenderableSize' {
    $s = 'hello' | Format-SpectrePanel | Get-SpectreRenderableSize
    Assert-True ($s.Width -eq 9 -and $s.Height -eq 3) "size $($s.Width)x$($s.Height)"
}
Test-Case 'layout: -Width larger than console throws' {
    Assert-Throws { 'x' | Format-SpectrePanel -Width 10000 } 'width validation'
}

# ---------------- images.md ----------------
Test-Case 'images: all cell formats + MaxWidth' {
    foreach ($f in 'Blocks', 'Braille', 'Canvas') {
        $i = Get-SpectreImage $smiley -MaxWidth 12 -Format $f
        Assert-True ($i -is [PwshSpectreConsole.CellImage]) "$f is CellImage"
        $i | Out-SpectreHost | Out-Null
    }
}
Test-Case 'images: Sixel without support throws unless -Force' {
    if (-not $module.Invoke({ $script:TerminalSupportsSixel })) {
        Assert-Throws { Get-SpectreImage $smiley -Format Sixel } 'sixel unsupported'
    }
    $s = Get-SpectreImage $smiley -MaxWidth 10 -Format Sixel -Force
    Assert-True ($s -is [PwshSpectreConsole.PixelImage]) 'PixelImage'
}
Test-Case 'images: pipeline FileInfo + gallery' {
    Get-Item $smiley | Get-SpectreImage -MaxWidth 6 | Out-SpectreHost | Out-Null
    @(Get-Item $smiley) | ForEach-Object {
        @((Get-SpectreImage $_.FullName -MaxWidth 10), ($_.BaseName | Get-SpectreEscapedText)) | Format-SpectreRows | Format-SpectrePanel
    } | Format-SpectreColumns | Out-SpectreHost | Out-Null
}

# ---------------- live-and-progress.md ----------------
Test-Case 'status: context, Write-SpectreHost, return value' {
    $r = Invoke-SpectreCommandWithStatus -Title 'Connecting...' -Spinner Dots2 -Color Cyan1 -ScriptBlock {
        param($Context)
        Write-SpectreHost '[grey]LOG:[/] connected'
        $Context.Status = 'Downloading...'
        $Context.Spinner = [Spectre.Console.Spinner+Known]::Star
        return @{ Items = 42 }
    }
    Assert-True ($r.Items -eq 42) 'status return'
}
Test-Case 'progress: MaxValue, Increment, collect results' {
    $r = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param($Context)
        $task = $Context.AddTask('Copying 3 files')
        $task.MaxValue = 3
        $done = foreach ($n in 1..3) { $task.Increment(1); "f$n" }
        $done
    }
    Assert-True ($r.Count -eq 3) 'progress return'
}
Test-Case 'progress: thread jobs + Wait-SpectreJobs' {
    $r = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param($Context)
        $jobs = @(
            Add-SpectreJob -Context $Context -JobName 'a' -Job (Start-ThreadJob { Start-Sleep -Milliseconds 300; 'A' })
            Add-SpectreJob -Context $Context -JobName 'b' -Job (Start-ThreadJob { Start-Sleep -Milliseconds 500; 'B' })
        )
        Wait-SpectreJobs -Context $Context -Jobs $jobs -TimeoutSeconds 30 -EstimatedDurationSeconds 2
        $jobs.Job | Receive-Job -Wait -AutoRemoveJob
    }
    Assert-True (($r -join '') -eq 'AB') "jobs returned $r"
}
Test-Case 'live: mutate table, UpdateCell, UpdateTarget, RemoveAt' {
    $table = [Spectre.Console.Table]::new()
    [void]$table.AddColumn('Service'); [void]$table.AddColumn('Status')
    $r = Invoke-SpectreLive -Data $table -ScriptBlock {
        param($Context)
        $i = 0
        foreach ($svc in 'api', 'worker') {
            [void][Spectre.Console.TableExtensions]::AddRow($table, [string[]]@($svc, '[yellow]deploying[/]'))
            $Context.Refresh()
            [void][Spectre.Console.TableExtensions]::UpdateCell($table, $i, 1, '[green]done[/]')
            $Context.Refresh()
            $i++
        }
        $table.Rows.RemoveAt(0)
        $Context.UpdateTarget(('swapped' | Format-SpectrePanel))
        $Context.Refresh()
        'ok'
    }
    Assert-True ($r -eq 'ok') 'live return'
}
Test-Case 'quietly: suppresses noisy output (errors re-thrown under EAP Stop)' {
    $v = Invoke-SpectreScriptBlockQuietly -Command { Write-Output 'kept'; Write-Error 'noise' } -ErrorAction Continue
    Assert-True ($v -contains 'kept') 'output returned'
    Assert-Throws { Invoke-SpectreScriptBlockQuietly -Command { Write-Error 'noise' } } 'EAP Stop rethrows'
}

# ---------------- prompts.md ----------------
Test-Case 'prompts: non-interactive guard' {
    if (-not [Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive) {
        Assert-Throws { Read-SpectreSelection -Message 'x' -Choices 'a', 'b' } 'non-interactive prompt throws'
    }
    $p = [Spectre.Console.TextPrompt[string]]::new('Password:')
    $p = [Spectre.Console.TextPromptExtensions]::Secret($p)
    Assert-True ($null -ne $p) 'secret prompt builds'
}

# ---------------- charts-and-widgets.md ----------------
Test-Case 'charts: New-SpectreChartItem works, string color in hashtable fails' {
    $items = 'a', 'b', 'c' | ForEach-Object -Begin { $palette = 'Cyan1', 'Orange1', 'Green'; $i = 0 } -Process {
        New-SpectreChartItem -Label $_ -Value ($i + 1) -Color $palette[$i++ % $palette.Count]
    }
    $items | Format-SpectreBarChart -Label 'Files' -Width 60 | Out-SpectreHost | Out-Null
    $items | Format-SpectreBarChart -HideValues -Width 40 | Out-SpectreHost | Out-Null
    $items | Format-SpectreBreakdownChart -Width 50 -ShowPercentage | Out-SpectreHost | Out-Null
    @{ Label = 'A'; Value = 1; Color = [Spectre.Console.Color]::Green } | Format-SpectreBarChart -Width 30 | Out-SpectreHost | Out-Null
    Assert-Throws { @{ Label = 'A'; Value = 1; Color = 'Green' } | Format-SpectreBarChart -Width 30 -ErrorAction Stop | Out-SpectreHost } 'string color'
}
Test-Case 'tree: recursive directory function' {
    function ConvertTo-SpectreTreeNode([System.IO.DirectoryInfo] $Dir, [int] $Depth = 1) {
        $children = @()
        if ($Depth -gt 0) {
            $children += Get-ChildItem $Dir.FullName -Directory | Select-Object -First 2 | ForEach-Object { ConvertTo-SpectreTreeNode $_ ($Depth - 1) }
        }
        $children += Get-ChildItem $Dir.FullName -File | Select-Object -First 3 | ForEach-Object { @{ Value = "[grey]$($_.Name | Get-SpectreEscapedText)[/]" } }
        @{ Value = "[bold]$($Dir.Name | Get-SpectreEscapedText)/[/]"; Children = $children }
    }
    ConvertTo-SpectreTreeNode (Get-Item $PSHOME) | Format-SpectreTree -Guide Line -Color Grey | Out-SpectreHost | Out-Null
    @{ Value = 'root'; Children = @(@{ Value = (Write-SpectreCalendar -PassThru) }) } | Format-SpectreTree -Guide BoldLine | Out-SpectreHost | Out-Null
}
Test-Case 'json: object, string, panel, style' {
    $obj = @{ a = 1; b = @(1, 2); c = @{ d = $null } }
    $obj | Format-SpectreJson -Depth 5 | Out-SpectreHost | Out-Null
    ($obj | ConvertTo-Json) | Format-SpectreJson | Format-SpectrePanel -Header 'config.json' | Out-SpectreHost | Out-Null
    $obj | Format-SpectreJson -JsonStyle @{ MemberStyle = 'Yellow'; StringStyle = 'Green'; NumberStyle = 'Cyan1' } | Out-SpectreHost | Out-Null
}
Test-Case 'text helpers: figlet, rules, calendar, text path' {
    Write-SpectreFigletText 'Deploy' -Color Cyan1 -Alignment Center -PassThru | Out-SpectreHost | Out-Null
    Write-SpectreRule -PassThru | Out-SpectreHost | Out-Null
    Write-SpectreRule 'Results' -Alignment Left -Color White -LineColor Grey -PassThru | Out-SpectreHost | Out-Null
    Write-SpectreRule 'Half' -WidthPercent 50 -PassThru | Out-SpectreHost | Out-Null
    Write-SpectreCalendar -Date (Get-Date) -Events @{ (Get-Date).AddDays(3).ToString('yyyy-MM-dd') = 'Release' } -PassThru | Out-SpectreHost | Out-Null
    $PSHOME | Format-SpectreTextPath -PathStyle @{ LeafColor = 'HotPink' } | Out-SpectreHost | Out-Null
}
Test-Case 'exceptions: formats and style' {
    foreach ($fmt in 'Default', 'ShortenPaths', 'ShortenTypes', 'ShortenMethods', 'ShowLinks', 'ShortenEverything', 'NoStackTrace') {
        try { 1 / 0 } catch { $_ | Format-SpectreException -ExceptionFormat $fmt | Out-SpectreHost | Out-Null }
    }
    try { 1 / 0 } catch { $_ | Format-SpectreException -ExceptionStyle @{ Message = 'red'; Method = 'yellow' } | Out-SpectreHost | Out-Null }
}

# ---------------- dotnet-interop.md ----------------
Test-Case 'interop: Style.Parse, Text overflow, Rows ctor, canvas, progress columns' {
    $null = [Spectre.Console.Style]::Parse('bold yellow on blue')
    $null = [Spectre.Console.Style]::new([Spectre.Console.Color]::Red, [Spectre.Console.Color]::Black, [Spectre.Console.Decoration]::Bold)
    $text = [Spectre.Console.Text]::new('x' * 200)
    $text.Overflow = [Spectre.Console.Overflow]::Ellipsis
    [Spectre.Console.Rows]::new([Spectre.Console.Rendering.IRenderable[]]@($text, $text)) | Out-SpectreHost | Out-Null
    $canvas = [Spectre.Console.Canvas]::new(16, 16)
    for ($i = 0; $i -lt 16; $i++) { [void]$canvas.SetPixel($i, $i, [Spectre.Console.Color]::Red) }
    $canvas | Out-SpectreHost | Out-Null
    [void][Spectre.Console.TableExtensions]::HideHeaders(([Spectre.Console.Table]::new()))
    $progress = [Spectre.Console.AnsiConsole]::Progress()
    $progress.AutoClear = $false
    $progress = [Spectre.Console.ProgressExtensions]::Columns($progress, [Spectre.Console.ProgressColumn[]]@(
        [Spectre.Console.TaskDescriptionColumn]::new(), [Spectre.Console.ProgressBarColumn]::new(),
        [Spectre.Console.PercentageColumn]::new(), [Spectre.Console.RemainingTimeColumn]::new(), [Spectre.Console.SpinnerColumn]::new()))
    $progress.Start({ param($ctx) $t = $ctx.AddTask('Work'); while (-not $ctx.IsFinished) { $t.Increment(25) } })
}

Write-Host ""
Write-Host "Passed: $script:passed  Failed: $($script:failures.Count)"
$script:failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
exit $script:failures.Count
