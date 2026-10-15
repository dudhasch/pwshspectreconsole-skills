# Tables

`Format-SpectreTable` (alias `fst`) turns objects into a `[Spectre.Console.Table]` renderable. It runs your
input through PowerShell's own `Format-Table` first, so **columns, order and labels follow the same rules
as `Format-Table`** (`-Property`, calculated properties, `-View`, format.ps1xml defaults).

## Parameters

| Parameter | Notes |
|---|---|
| `-Data` / pipeline | objects, hashtables, scalars, or renderables |
| `-Property` (positional) | names, wildcards, or calculated properties `@{Name=..; Expression={..}; Width=..}` |
| `-View` | named Format-Table view (mutually exclusive with `-Property`) |
| `-Border` | `Rounded` (default), `Square`, `Ascii`, `Ascii2`, `AsciiDoubleHead`, `Double`, `DoubleEdge`, `Heavy`, `HeavyEdge`, `HeavyHead`, `Horizontal`, `Markdown`, `Minimal`, `MinimalDoubleHead`, `MinimalHeavyHead`, `None`, `Simple`, `SimpleHeavy` |
| `-Color` | border color (default: accent color) |
| `-HeaderColor`, `-TextColor` | header / cell text color |
| `-Title` | caption above the table (ignored for scalar input) |
| `-Width` | fixed width; must be ≤ console width (throws otherwise) |
| `-Expand` | stretch to available width (good inside panels/layouts) |
| `-HideHeaders`, `-ShowRowSeparators` | |
| `-AllowMarkup` | parse cell text as Spectre markup |
| `-Wrap` | intended to wrap instead of truncate; unreliable (upstream bug), cells may wrap or truncate regardless. Prefer an explicit column `Width` or shorter data. |

## Basics

```powershell
Get-Process | Select-Object -First 5 Name, Id, CPU | Format-SpectreTable -Title "Top processes" -Border Rounded -Color Grey

# Calculated properties - same syntax as Format-Table
Get-ChildItem -File | Format-SpectreTable -Property @(
    @{ Name = 'File';  Expression = { $_.Name }; Width = 30 }
    @{ Name = 'Size';  Expression = { '{0:N1} KB' -f ($_.Length / 1KB) } }
    @{ Name = 'Modified'; Expression = { $_.LastWriteTime.ToString('yyyy-MM-dd') } }
)

1..5 | Format-SpectreTable                      # scalars -> single "Value" column
@{ Server = 'web01'; Status = 'Up' } | Format-SpectreTable   # hashtable -> one row, keys as columns
```

Hashtable key order is not guaranteed; use `[ordered]@{...}` or `[pscustomobject][ordered]@{...}` for stable columns.

## Column alignment

The `Alignment` key in calculated properties is **not applied** in 2.6.3. Set it on the returned table:

```powershell
$table = $files | Format-SpectreTable -Property Name, Length
$table.Columns[1].Alignment = [Spectre.Console.Justify]::Right     # Left | Center | Right
$table.Columns[1].NoWrap = $true
$table.Columns[1].Width = 12
$table | Out-SpectreHost
```

## Colors and markup in cells

Without `-AllowMarkup` every cell is literal text (safe for arbitrary data). With it, escape the data and
add markup yourself:

```powershell
$services | Format-SpectreTable -AllowMarkup -Property @(
    @{ Name = 'Name';   Expression = { $_.Name | Get-SpectreEscapedText } }
    @{ Name = 'Status'; Expression = {
        switch ($_.Status) {
            'Running' { '[green]● Running[/]' }
            'Stopped' { '[red]● Stopped[/]' }
            default   { "[yellow]$($_.Status)[/]" }
        } } }
)
```

Strings that already contain ANSI escape sequences (e.g. from `$PSStyle` or other tools) are detected and
converted automatically - you don't need `-AllowMarkup` for them.

## Nesting renderables (images, charts, panels, tables in cells)

Renderables survive only when they are **hashtable values** or the **pipeline items themselves**.
A `[pscustomobject]` property holding a renderable is stringified by Format-Table and shows as
`Spectre.Console.Panel`.

```powershell
$img   = Get-SpectreImage $path -MaxWidth 12
$chart = New-SpectreChartItem -Label CPU -Value 63 -Color Orange1 | Format-SpectreBarChart -Width 30

# ✅ hashtable / [ordered] rows
[ordered]@{ Icon = $img; Name = 'web01'; Load = $chart } | Format-SpectreTable

# ✅ multiple rows: one hashtable per row
@(
    [ordered]@{ Name = 'web01'; Load = $chart1 }
    [ordered]@{ Name = 'web02'; Load = $chart2 }
) | Format-SpectreTable

# ❌ pscustomobject - prints "Spectre.Console.BarChart"
[pscustomobject]@{ Name = 'web01'; Load = $chart } | Format-SpectreTable
```

## Adding and updating rows (incl. live tables)

```powershell
$table = $rows | Format-SpectreTable -AllowMarkup
$table = Add-SpectreTableRow -Table $table -Columns 'web03', '[green]ok[/]'     # count must equal column count
$table = Add-SpectreTableRow -Table $table -Columns 'web04', ($img)             # renderables are fine

# Update a cell (row, column are 0-based). Extension method => call statically.
[void][Spectre.Console.TableExtensions]::UpdateCell($table, 0, 1, '[red]down[/]')
```

`Add-SpectreTableRow` parses a string as markup only if it contains `[/]`, so escape data that might contain it.

To build an empty table to fill later (e.g. in `Invoke-SpectreLive`), start from a raw table (below) - 
`Format-SpectreTable` needs at least one input object to create columns.

## Raw .NET table (full control)

```powershell
$table = [Spectre.Console.Table]::new()
$table.Border      = [Spectre.Console.TableBorder]::Rounded
$table.BorderStyle = [Spectre.Console.Style]::new([Spectre.Console.Color]::Grey)
$table.Title       = [Spectre.Console.TableTitle]::new('[bold]Deployments[/]')
$table.Caption     = [Spectre.Console.TableTitle]::new('[dim]updated just now[/]')
$table.Expand      = $true

[void]$table.AddColumn('[bold]Service[/]')                       # header text is markup
$col = [Spectre.Console.TableColumn]::new('[bold]Duration[/]')
$col.Alignment = [Spectre.Console.Justify]::Right
[void]$table.AddColumn($col)

[void][Spectre.Console.TableExtensions]::AddRow($table, [string[]]@('api', '12s'))       # strings are markup!
[void][Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@(
    [Spectre.Console.Text]::new('worker [beta]'),                                         # literal text, no escaping needed
    [Spectre.Console.Markup]::new('[green]8s[/]')))
[void][Spectre.Console.TableExtensions]::AddEmptyRow($table)
$table | Out-SpectreHost
```

## Layout tips

- Put a table in a panel: `$table | Format-SpectrePanel -Header 'Files'`. For a borderless look inside the
  panel use `-Border None` on the table.
- Side by side: `@($table1, $table2) | Format-SpectreColumns`.
- Keep wide tables inside the terminal: select fewer properties, set column `Width`, or truncate strings in
  calculated properties (`$_.Name.Substring(0, [Math]::Min(30, $_.Name.Length))`).
- Use `-Expand` when a table is inside a fixed-width panel or layout and should fill it.
