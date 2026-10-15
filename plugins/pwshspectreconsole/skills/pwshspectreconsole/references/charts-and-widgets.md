# Charts and other widgets

## Chart items

Both chart cmdlets take items with `Label`, `Value`, `Color`. **Use `New-SpectreChartItem`** - it converts
color names/hex. Hashtables or pscustomobjects also work *only* if `Color` is already a
`[Spectre.Console.Color]`; a string like `'Green'` throws `Cannot convert ... to type Spectre.Console.Color`.

```powershell
$items = Get-ChildItem -File | Group-Object Extension | Sort-Object Count -Descending | Select-Object -First 6 |
    ForEach-Object -Begin { $palette = 'Cyan1', 'Orange1', 'Green', 'Magenta1', 'Yellow', 'Grey' ; $i = 0 } -Process {
        New-SpectreChartItem -Label (($_.Name ? $_.Name : '(none)') | Get-SpectreEscapedText) -Value $_.Count -Color $palette[$i++ % $palette.Count]
    }
```

Labels are markup - escape dynamic labels.

## Bar chart

```powershell
$items | Format-SpectreBarChart -Label "Files by extension" -Width 60
$items | Format-SpectreBarChart -HideValues
```

`-Width` defaults to the full console width and must be ≤ console width. `-Label` (alias `-Title`) is a centered caption.

## Breakdown chart (stacked 100% bar + legend)

```powershell
$disk = Get-PSDrive C
@(
    New-SpectreChartItem -Label Used -Value ([math]::Round($disk.Used / 1GB, 1)) -Color Red
    New-SpectreChartItem -Label Free -Value ([math]::Round($disk.Free / 1GB, 1)) -Color Green
) | Format-SpectreBreakdownChart -Width 50 -ShowPercentage
```

Switches: `-HideTags` (no legend), `-HideTagValues`, `-ShowPercentage`.

Charts are renderables - put them in panels, table cells (hashtable rows), or grids.

## Tree

Input is a hashtable `@{ Value = <string|renderable>; Children = @( <same shape>... ) }` (`Label` works as an
alias for `Value`). `Children` must be an **array** (wrap a single child in `@( )`). Values are markup.

```powershell
function ConvertTo-SpectreTreeNode([System.IO.DirectoryInfo] $Dir, [int] $Depth = 2) {
    $children = @()
    if ($Depth -gt 0) {
        $children += Get-ChildItem $Dir.FullName -Directory | ForEach-Object { ConvertTo-SpectreTreeNode $_ ($Depth - 1) }
    }
    $children += Get-ChildItem $Dir.FullName -File | ForEach-Object { @{ Value = "[grey]$($_.Name | Get-SpectreEscapedText)[/]" } }
    @{ Value = "[bold]$($Dir.Name | Get-SpectreEscapedText)/[/]"; Children = $children }
}
ConvertTo-SpectreTreeNode (Get-Item .) | Format-SpectreTree -Guide Line -Color Grey
```

`-Guide` (alias `-Border`): `Line` (default), `Ascii`, `DoubleLine`, `BoldLine`.

## JSON

```powershell
$obj | Format-SpectreJson -Depth 5                          # objects -> highlighted JSON
Get-Content config.json -Raw | Format-SpectreJson           # JSON string
Get-ChildItem *.json | Format-SpectreJson                   # files
$obj | Format-SpectreJson | Format-SpectrePanel -Header config.json   # border/title: wrap in a panel
$obj | Format-SpectreJson -JsonStyle @{ MemberStyle = 'Yellow'; StringStyle = 'Green'; NumberStyle = 'Cyan1' }
```

`-Border`, `-Color`, `-Title`, `-Width`, `-Height`, `-NoBorder` are **deprecated no-ops** since 2.0 - use a panel.

## Text helpers

```powershell
Write-SpectreFigletText "Deploy" -Color Cyan1 -Alignment Center        # big ASCII-art header
Write-SpectreFigletText "Deploy" -FigletFontPath .\fonts\small.flf -PassThru   # custom .flf font, as renderable

Write-SpectreRule                                                      # plain horizontal line
Write-SpectreRule "Results" -Alignment Left -Color White -LineColor Grey
Write-SpectreRule "Half" -WidthPercent 50                              # or -Width 40
$rule = Write-SpectreRule "Section" -PassThru                          # for Format-SpectreRows

Write-SpectreCalendar -Date (Get-Date) -Events @{ (Get-Date).AddDays(3).ToString('yyyy-MM-dd') = 'Release' }

Get-Location | Format-SpectreTextPath                                  # colored path; truncates nicely in narrow containers
'C:\very\long\path\to\file.txt' | Format-SpectreTextPath -PathStyle @{ LeafColor = 'HotPink' }
```

## Exceptions

```powershell
try { Invoke-RestMethod $uri -ErrorAction Stop }
catch {
    $_ | Format-SpectreException -ExceptionFormat ShortenEverything | Out-SpectreHost
}
```

`-ExceptionFormat`: `Default`, `ShortenPaths`, `ShortenTypes`, `ShortenMethods`, `ShowLinks`, `ShortenEverything`, `NoStackTrace`.
`-ExceptionStyle @{ Message='red'; Method='yellow'; Path='Yellow'; ... }` overrides colors.

For a compact friendly error, prefer a panel:
`"[red]$($_.Exception.Message | Get-SpectreEscapedText)[/]" | Format-SpectrePanel -Header "[red]Error[/]" -Color Red`.

## Recording output (experimental)

```powershell
Start-SpectreRecording -RecordingType Html          # asciinema (default) | text | html
Write-SpectreHost "Hello [red]world[/]"
$html = Stop-SpectreRecording -OutputPath .\demo.html    # also returns the content; -Title for asciinema
```

Only output that goes through Spectre (Write-Spectre*, Out-SpectreHost, prompts, live widgets) is recorded.

## Demos / discovery

`Start-SpectreDemo`, `Get-SpectreDemoFeatures`, `Get-SpectreDemoColors`, `Get-SpectreDemoEmoji`,
`Open-PwshSpectreConsoleHelp`. Every cmdlet has full help: `Get-Help Format-SpectreTable -Examples`.
