# Composition and layout

All containers take renderables (or strings, converted as described in `markup-and-output.md`)
and return a new renderable, so they nest freely.

| Cmdlet | Use for | Key params |
|---|---|---|
| `Format-SpectrePanel` | Border + optional header around ONE renderable | `-Header`/`-Title`, `-Border` (`Rounded` default, `Square`, `Double`, `Heavy`, `Ascii`, `None`), `-Color`, `-Expand`, `-Width`, `-Height` |
| `Format-SpectreRows` | Stack items vertically | `-Expand` |
| `Format-SpectreColumns` | Flow items side by side (wraps to next line when out of width) | `-Padding` (1), `-Expand` |
| `Format-SpectreGrid` | Aligned borderless grid (label/value pairs, forms) | `-Width`, `-Padding` |
| `Format-SpectrePadded` | Add space around an item | `-Padding n` or `-Top -Left -Bottom -Right` (all four required) or `-Expand` |
| `Format-SpectreAligned` | Align an item inside its available space | `-HorizontalAlignment Left/Center/Right` (Center), `-VerticalAlignment Top/Middle/Bottom` (Middle) |
| `New-SpectreLayout` | Full-terminal split screen (rows OR columns per layout, nestable) | `-Name`, `-Data`/`-Rows`/`-Columns`, `-Ratio`, `-MinimumSize` |

## Panels

```powershell
"Deployed [green]3[/] services" | Format-SpectrePanel -Header "[bold]Summary[/]" -Color Green
$table | Format-SpectrePanel -Header "Files" -Expand            # fill the width
@("[bold]Logo[/]", $image) | Format-SpectreRows | Format-SpectrePanel    # many items -> wrap in rows first
```

`-Header` is markup: escape dynamic titles. Piping an array of items into `Format-SpectrePanel` produces
one panel per item (sometimes useful: `$servers | ForEach-Object { ... } | Format-SpectrePanel`).

Use `-Height` only with content that fits; content beyond the height is cut.

## Rows, columns, grids

```powershell
# Cards side by side
$cards = $servers | ForEach-Object {
    "[bold]$($_.Name | Get-SpectreEscapedText)[/]`nCPU $($_.Cpu)%" | Format-SpectrePanel -Color $(if ($_.Cpu -gt 80) { 'Red' } else { 'Green' })
}
$cards | Format-SpectreColumns

# Vertical stack of mixed widgets
@(
    (Write-SpectreFigletText "Report" -PassThru)
    (Write-SpectreRule "Summary" -PassThru)
    $summaryTable
) | Format-SpectreRows

# Grid: label/value pairs aligned like a form. Each row is an array (or New-SpectreGridRow).
Format-SpectreGrid -Data @(
    (New-SpectreGridRow @('[grey]Host[/]', $env:COMPUTERNAME))
    (New-SpectreGridRow @('[grey]User[/]', [Environment]::UserName))
    (New-SpectreGridRow @('[grey]PS[/]',   $PSVersionTable.PSVersion.ToString()))
) -Padding 2
```

All grid rows must have the same number of cells. Cells can be renderables (images, panels, charts).

Beware PowerShell array flattening: `@( @('a','b') @('c','d') )` is ONE flat array of four strings, not two
rows. Build rows with `New-SpectreGridRow` (as above), from a loop, or with the unary comma `,@('a','b')`:

```powershell
$info = [ordered]@{ Host = $env:COMPUTERNAME; Shell = "pwsh $($PSVersionTable.PSVersion)" }
$rows = foreach ($e in $info.GetEnumerator()) { New-SpectreGridRow @("[grey]$($e.Key)[/]", ($e.Value | Get-SpectreEscapedText)) }
Format-SpectreGrid -Data $rows
```

## Alignment and padding

```powershell
"Centered" | Format-SpectreAligned -HorizontalAlignment Center | Format-SpectrePanel -Expand
$logo | Format-SpectrePadded -Top 1 -Left 4 -Bottom 1 -Right 4
$logo | Format-SpectrePadded -Padding 2
```

Vertical alignment only has an effect when the container has spare height (layouts, panels with `-Height`).

## Layouts (full-screen)

A layout always renders at the **full console height** (`[Spectre.Console.AnsiConsole]::Profile.Height`).
Use it for dashboards/TUIs, typically inside `Invoke-SpectreLive`; for normal inline output use the
containers above.

```powershell
$layout = New-SpectreLayout -Name root -Rows @(
    (New-SpectreLayout -Name header -MinimumSize 3 -Ratio 1 -Data 'loading...'),
    (New-SpectreLayout -Name body -Ratio 6 -Columns @(
        (New-SpectreLayout -Name left  -Ratio 1 -Data 'left'),
        (New-SpectreLayout -Name right -Ratio 2 -Data 'right')
    )),
    (New-SpectreLayout -Name footer -MinimumSize 3 -Ratio 1 -Data 'footer')
)

# Replace content of a named region (returns the layout; discard it)
$layout['header'].Update(("[bold]My App[/]" | Format-SpectreAligned | Format-SpectrePanel -Expand)) | Out-Null
$layout | Out-SpectreHost
```

Rules:
- A single `New-SpectreLayout` has `-Data` **or** `-Rows` **or** `-Columns`. Nest layouts for complex grids.
- Non-layout items given to `-Rows`/`-Columns` are wrapped in an anonymous layout automatically - name
  them yourself if you need to `Update()` them later.
- `Update()` only has a visible effect on **leaf** regions (created with `-Data`). A region that was split
  with `-Rows`/`-Columns` keeps rendering its children.
- `Out-SpectreHost` trims trailing blank lines, so a layout whose bottom regions are empty looks shorter
  than the terminal; use `-Expand`ed panels in regions for a stable frame.
- `-Ratio` divides space among siblings; `-MinimumSize` (rows: lines, columns: chars) protects headers/footers.
- Content that is taller than its region is cut off. Use `-Expand` on panels so they fill their region.
- Measure regions before generating content (e.g. how many log lines fit):

```powershell
$sizes = $layout | Get-SpectreLayoutSizes          # hashtable: name -> region with Width / Height
$visibleLines = $sizes['body'].Height - 2          # minus panel border
```

## Measuring

```powershell
$size = $panel | Get-SpectreRenderableSize          # Width / Height in cells
$size = $panel | Get-SpectreRenderableSize -ContainerWidth 60
```

Use this to trim lists to the available height (see the chat example in `live-and-progress.md`).

## Responsive output

```powershell
$width = [Spectre.Console.AnsiConsole]::Profile.Width
if ($width -lt 100) { $widgets | Format-SpectreRows } else { $widgets | Format-SpectreColumns }
```
