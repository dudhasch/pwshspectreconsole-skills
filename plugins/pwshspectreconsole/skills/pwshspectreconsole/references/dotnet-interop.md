# Using the Spectre.Console .NET API directly

The module loads `Spectre.Console.dll`, so every Spectre.Console type is available from PowerShell.
Drop down to it when a cmdlet doesn't expose what you need (column alignment, captions, cell updates,
secret prompts, custom progress columns, canvases, ...). Spectre.Console API docs: https://spectreconsole.net/api/

## Rules

1. **Extension methods must be called as static methods** on their extension class, passing the object first.
   They return the object (fluent API) - discard with `[void]` or reassign.

   | C# | PowerShell |
   |---|---|
   | `table.AddRow("a", "b")` | `[void][Spectre.Console.TableExtensions]::AddRow($table, [string[]]@('a','b'))` |
   | `table.UpdateCell(0, 1, "x")` | `[void][Spectre.Console.TableExtensions]::UpdateCell($table, 0, 1, 'x')` |
   | `table.HideHeaders()` | `$table.ShowHeaders = $false` (or `[Spectre.Console.TableExtensions]::HideHeaders($table)`) |
   | `column.RightAligned()` | `$column.Alignment = [Spectre.Console.Justify]::Right` |
   | `panel.Header("x")` | `$panel.Header = [Spectre.Console.PanelHeader]::new('x')` |
   | `prompt.Secret()` | `$prompt = [Spectre.Console.TextPromptExtensions]::Secret($prompt)` |
   | `new Rows(a, b)` | `[Spectre.Console.Rows]::new([Spectre.Console.Rendering.IRenderable[]]@($a, $b))` |

   Prefer setting properties directly where they exist - it's shorter and has no return value to discard.
   Common extension classes: `TableExtensions`, `ColumnExtensions`, `AlignableExtensions`, `PaddableExtensions`,
   `HasBorderExtensions`, `BoxExtensions`, `ExpandableExtensions`, `OverflowableExtensions`,
   `SelectionPromptExtensions`, `MultiSelectionPromptExtensions`, `TextPromptExtensions`, `ProgressExtensions`.

2. **Generic types** use PowerShell syntax: `[Spectre.Console.SelectionPrompt[string]]::new()`.

3. **`Markup` vs `Text`**: `[Spectre.Console.Markup]::new($s)` parses markup (escape data with
   `[Spectre.Console.Markup]::Escape($s)` or `Get-SpectreEscapedText`); `[Spectre.Console.Text]::new($s, $style)`
   is always literal - the easiest way to show untrusted text safely.

4. **Styles**: `[Spectre.Console.Style]::new($fg, $bg, [Spectre.Console.Decoration]::Bold)` or
   `[Spectre.Console.Style]::Parse('bold yellow on blue')`.

5. **Arrays of renderables** must be typed for constructors: `[Spectre.Console.Rendering.IRenderable[]]@(...)`.

6. **Rendering**: raw objects render like module ones: `$obj | Out-SpectreHost`, or
   `[Spectre.Console.AnsiConsole]::Write($obj)` to write straight to the console.

## Examples

```powershell
# Text overflow / ellipsis in a narrow column
$col = [Spectre.Console.TableColumn]::new('Path')
$col.Width = 30; $col.NoWrap = $true
$text = [Spectre.Console.Text]::new($longPath)
$text.Overflow = [Spectre.Console.Overflow]::Ellipsis

# Custom progress columns (bar + percentage + remaining time + spinner)
$progress = [Spectre.Console.AnsiConsole]::Progress()
$progress.AutoClear = $false
$progress = [Spectre.Console.ProgressExtensions]::Columns($progress, [Spectre.Console.ProgressColumn[]]@(
    [Spectre.Console.TaskDescriptionColumn]::new(),
    [Spectre.Console.ProgressBarColumn]::new(),
    [Spectre.Console.PercentageColumn]::new(),
    [Spectre.Console.RemainingTimeColumn]::new(),
    [Spectre.Console.SpinnerColumn]::new()
))
$progress.Start({
    param($ctx)
    $t = $ctx.AddTask('Work')
    while (-not $ctx.IsFinished) { $t.Increment(2); Start-Sleep -Milliseconds 50 }
})

# Pixel canvas (draw your own graphics)
$canvas = [Spectre.Console.Canvas]::new(16, 16)
for ($i = 0; $i -lt 16; $i++) {
    [void]$canvas.SetPixel($i, $i, [Spectre.Console.Color]::Red)
    [void]$canvas.SetPixel(15 - $i, $i, [Spectre.Console.Color]::Blue)
}
$canvas | Out-SpectreHost
```
