---
name: pwshspectreconsole
description: Build correct, good-looking PowerShell console UIs with the PwshSpectreConsole module (Spectre.Console for PowerShell). Use whenever writing or fixing PowerShell that uses *-Spectre* cmdlets: tables (Format-SpectreTable), panels, layouts, columns/rows/grids, images in the terminal (Get-SpectreImage, Sixel/block/braille), progress bars, spinners, live displays (Invoke-SpectreLive), prompts and menus (Read-SpectreSelection, Read-SpectreConfirm), bar/breakdown charts, trees, JSON, figlet text and Spectre markup/colors. Also use when a user asks for a "pretty", "rich", "TUI" or "dashboard" console output in PowerShell.
---

# PwshSpectreConsole

PwshSpectreConsole wraps the .NET library [Spectre.Console](https://spectreconsole.net) for PowerShell 7.4+.
Target **module 2.6.3+** (current stable on PSGallery). Docs: https://pwshspectreconsole.com/reference/

```powershell
Install-Module PwshSpectreConsole -Scope CurrentUser
# Put this in $PROFILE (or at the top of the script) so box drawing, emoji and braille render:
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
```

## Mental model (read this first)

There are three kinds of cmdlets. Mixing them up is the root of most bugs.

| Verb | Returns | Writes to console? | Examples |
|---|---|---|---|
| `Format-*`, `New-*`, `Get-SpectreImage`, `Add-SpectreTableRow` | a **renderable** object | No | `Format-SpectreTable`, `Format-SpectrePanel`, `New-SpectreLayout` |
| `Write-*` | nothing (use `-PassThru` to get a renderable instead) | Yes, immediately | `Write-SpectreHost`, `Write-SpectreRule`, `Write-SpectreFigletText` |
| `Read-*`, `Invoke-*` | the user's answer / the script block's return value | Yes, interactively | `Read-SpectreSelection`, `Invoke-SpectreCommandWithProgress` |

**Build renderables, compose them, render once.** Pipe renderables into containers
(`Format-SpectrePanel`, `Format-SpectreRows`, `Format-SpectreColumns`, `Format-SpectreGrid`,
`New-SpectreLayout`, table cells) and output the final object a single time.

## Non-negotiable rules

1. **Render explicitly in scripts and functions.** `Out-SpectreHost` *returns an ANSI string* to the
   pipeline - it does not write to the host. At the top level of a script that is fine, but inside a
   function it pollutes the function's return value. Use:
   ```powershell
   $panel | Out-SpectreHost              # top-level script / interactive
   $panel | Out-SpectreHost | Out-Host   # inside a function that also returns data
   ```
   Never leave a bare renderable as an unintended statement inside a function - it becomes part of the output.
2. **Escape every piece of dynamic text** that will be interpreted as markup with `Get-SpectreEscapedText`
   (file names, user input, exception messages, API data, prompt choice labels). `[` and `]` in data
   otherwise throw `Could not find color or style '...'` or `malformed markup tag`.
   ```powershell
   Write-SpectreHost "[green]Deleted[/] $($file.Name | Get-SpectreEscapedText)"
   ```
3. **Markup needs a closing tag to be detected.** Strings piped to `Format-*` are only parsed as markup if
   they contain `[/]` (or an `:emoji:`). `"[red]oops"` renders literally. `Write-SpectreHost` always parses markup.
4. **Tables: plain text by default.** `Format-SpectreTable` cells are literal text unless you pass
   `-AllowMarkup`; with `-AllowMarkup`, escape the data and add markup in calculated properties.
5. **Nested renderables in tables must come from a hashtable or be the item itself** - not a
   `[pscustomobject]` property (that renders as the text `Spectre.Console.Table`). See `references/tables.md`.
6. **A panel holds exactly one renderable.** Combine first: `@($text, $image) | Format-SpectreRows | Format-SpectrePanel`.
   Piping an array straight into `Format-SpectrePanel` makes one panel per item.
7. **Layouts (`New-SpectreLayout`) always fill the full terminal height.** Use them for full-screen
   dashboards and `Invoke-SpectreLive`. For inline output use rows/columns/grid/panels.
8. **Spectre.Console extension methods must be called statically** in PowerShell:
   `[Spectre.Console.TableExtensions]::UpdateCell($table, 0, 1, '[green]ok[/]')`,
   `[Spectre.Console.AlignableExtensions]::RightAligned($column)`. `$table.UpdateCell(...)` fails.
9. **Inside progress/status/live blocks never use `Write-Host`/`Write-Output`/`Format-Table`** - it tears the
   display. Return data from the script block (it's the return value of `Invoke-*`), use `Write-SpectreHost`
   for log lines in status spinners, and wrap noisy commands in `Invoke-SpectreScriptBlockQuietly`.
10. **Prompts need an interactive terminal.** Guard them (CI, redirected output, scheduled tasks throw
    `the current terminal isn't interactive`):
    ```powershell
    if ([Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive) { $env = Read-SpectreSelection ... } else { $env = $DefaultEnv }
    ```
11. **`-Width` must not exceed the console width** - the validator throws in narrow terminals/CI (80 cols).
    Clamp: `-Width ([Math]::Min(60, [Spectre.Console.AnsiConsole]::Profile.Width))`.
12. **Colors** accept names (`Get-SpectreDemoColors`), hex (`'#ff8800'`) or `[Spectre.Console.Color]::Red`.
    Exception: hashtables/objects fed to chart cmdlets must use real `[Spectre.Console.Color]` values -
    prefer `New-SpectreChartItem -Label .. -Value .. -Color Green`.

## Which reference to load

Load only what the task needs:

| Task | Read |
|---|---|
| Markup syntax, colors, styles, escaping, emoji, rendering/output, encoding, width | `references/markup-and-output.md` |
| Tables: from objects, calculated columns, alignment, borders, nested content, adding/updating rows, raw .NET tables | `references/tables.md` |
| Panels, rows, columns, grid, padding, alignment, layouts, measuring, dashboards | `references/layout.md` |
| Images: Sixel vs. blocks/braille, sizing, images in tables/panels, animated GIFs, remote images | `references/images.md` |
| Progress bars, jobs, spinners, live-updating tables/layouts, keyboard loops | `references/live-and-progress.md` |
| Selection / multi-selection / grouped menus, confirm, text, pause, timeouts | `references/prompts.md` |
| Bar & breakdown charts, trees, JSON, figlet, rules, calendar, text paths, exceptions, recording | `references/charts-and-widgets.md` |
| Something not wrapped by a cmdlet (raw Spectre.Console API from PowerShell) | `references/dotnet-interop.md` |

## Workflow

1. Import defensively - one module version per process (`if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }`).
   Check the environment when output looks wrong (boxes as `?`, no colors, no images):
   run `scripts/Test-SpectreTerminal.ps1` (reports encoding, color system, Unicode, interactivity, Sixel, size).
2. Pick widgets from the tables above; build each as a renderable variable with a descriptive name.
3. Compose into one root renderable; render once (rule 1).
4. Escape all dynamic data (rule 2); guard prompts (rule 10); clamp widths (rule 11).
5. Verify by running the script. For non-interactive smoke tests, `pwsh -NoProfile -File script.ps1` works
   for everything except prompts.

Complete, tested examples live in `examples/`:
`system-dashboard.ps1` (tables + charts + image + panels), `deploy-progress.ps1` (progress, jobs, status,
live table), `interactive-menu.ps1` (prompts with fallbacks), `live-dashboard.ps1` (full-screen layout with
keyboard loop).
