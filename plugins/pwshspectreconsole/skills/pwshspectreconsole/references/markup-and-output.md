# Markup, colors and output

## Markup syntax

Spectre markup is BBCode-like. Every opened tag must be closed with `[/]` (closes the most recent tag).

```powershell
Write-SpectreHost "[bold]Bold[/] [italic]italic[/] [underline]underline[/] [strikethrough]gone[/] [dim]dim[/]"
Write-SpectreHost "[red]red[/] [#ff8800]hex[/] [rgb(0,135,255)]rgb[/] [white on DarkRed] inverse [/]"
Write-SpectreHost "[bold yellow on blue]combined[/]"
Write-SpectreHost "[link=https://pwshspectreconsole.com]clickable link[/]"   # in terminals that support OSC 8
Write-SpectreHost ":rocket: emoji shortcodes :check_mark_button:"            # Get-SpectreDemoEmoji lists them
Write-SpectreHost "Literal brackets need doubling: [[not a tag]]"
```

Style keywords: `bold dim italic underline invert conceal slowblink rapidblink strikethrough`.
Colors: 256 named colors (`Get-SpectreDemoColors` shows them), `#rrggbb`, `rgb(r,g,b)`, `default`.

## Where markup is (and isn't) parsed

| Input | Parsed as markup? |
|---|---|
| `Write-SpectreHost $string` | Always |
| String piped/passed to `Format-SpectrePanel`, `-Rows`, `-Columns`, `New-SpectreLayout -Data`, `Format-SpectreAligned`, `Out-SpectreHost`, `Add-SpectreTableRow` | Only if the string contains `[/]` (panels/layouts also on `:x:` emoji pattern). Otherwise rendered literally. |
| `Format-SpectreTable` cell values | Only with `-AllowMarkup` |
| `-Header`/`-Title` of panels, table column headers, prompt `-Message`, prompt choices, tree node values | Always |
| `Format-SpectreJson`, `Format-SpectreTextPath` | Never (they style themselves) |

Consequences:

```powershell
"[red]oops" | Format-SpectrePanel                # shows the literal text "[red]oops"
"[red]oops[/]" | Format-SpectrePanel             # red text
"[red]Error:[/] $msg" | Format-SpectrePanel      # throws if $msg contains [something] -> escape it!
```

## Escaping (the #1 source of runtime errors)

```powershell
$safe = $userInput | Get-SpectreEscapedText          # "[admin]" -> "[[admin]]"
Write-SpectreHost "[green]User:[/] $safe"
"[red]Failed:[/] $($_.Exception.Message | Get-SpectreEscapedText)" | Format-SpectrePanel -Header "[red]Error[/]"
```

Escape: file/dir names, paths, user input, exception messages, command output, JSON/API values,
anything from `Get-Content`, and labels of prompt choices. Don't double-escape text you'll show
in a plain-text table (no `-AllowMarkup`) - it would display the doubled brackets.

`Get-SpectreEscapedText` takes a single `[string]` (pipeline input works per item). For `$null`
use `"$value" | Get-SpectreEscapedText` or check first - it's mandatory.

## Colors

```powershell
Format-SpectrePanel -Data "x" -Color Red                 # name (tab-completes)
Format-SpectrePanel -Data "x" -Color '#ff8800'           # hex
Format-SpectrePanel -Data "x" -Color ([Spectre.Console.Color]::new(255, 136, 0))
Get-SpectreDemoColors                                    # preview all named colors

# Module-wide defaults (affects borders, prompt highlights, rule titles, JSON, etc.)
Set-SpectreColors -AccentColor DeepPink1 -DefaultValueColor Grey -DefaultTableHeaderColor White -DefaultTableTextColor Default
Get-SpectreColors
```

`Set-SpectreColors` resets every parameter you don't pass to its default (Blue / Grey / Default / Default).

Use a color in markup from a `[Spectre.Console.Color]`: `"[$($color.ToMarkup())]text[/]"`.

## Getting output on screen

| Situation | Do |
|---|---|
| Top level of a script, or interactive prompt | `$renderable` (default formatter) or `$renderable \| Out-SpectreHost` |
| Inside a function that returns data | `$renderable \| Out-SpectreHost \| Out-Host` (or `[Spectre.Console.AnsiConsole]::Write($renderable)`) |
| Write markup text directly | `Write-SpectreHost "[green]ok[/]"` |
| Need text as a composable renderable | `Write-SpectreHost "..." -PassThru` (also `Write-SpectreRule -PassThru`, `Write-SpectreFigletText -PassThru`, `Write-SpectreCalendar -PassThru`) |
| Save to a file | `$renderable \| Out-SpectreHost \| Set-Content out.txt` (contains ANSI codes) or see recording in `charts-and-widgets.md` |

Why: `Out-SpectreHost` renders into a string writer and **returns the ANSI string**. A function like

```powershell
function Get-Report { $table | Out-SpectreHost; return $data }   # BUG: returns @(string, data)
```

returns both. Pipe to `Out-Host` or assign the render to `$null` only if you *don't* want it shown.

`Out-SpectreHost` renders at `$Host.UI.RawUI.BufferSize.Width`; the default formatter (bare renderable)
uses the same width minus one. `[Spectre.Console.AnsiConsole]::Write()` writes straight to the console
and uses `[Spectre.Console.AnsiConsole]::Profile.Width`.

`Write-SpectreHost` options: `-NoNewline`, `-Justify Left|Center|Right`, `-PassThru`.

## Terminal capabilities

```powershell
$p = [Spectre.Console.AnsiConsole]::Profile
$p.Width; $p.Height                              # 80x24 fallback when there's no real console (CI)
$p.Capabilities.ColorSystem                      # NoColors, Legacy, Standard, EightBit, TrueColor
$p.Capabilities.Unicode                          # $false -> boxes/braille degrade, fix encoding
$p.Capabilities.Interactive                      # $false -> prompts throw
$p.Capabilities.Ansi
```

(`Get-SpectreProfile` exists in source but is not exported in 2.6.3 - use the profile object.)

Respect `NO_COLOR`: Spectre.Console disables colors when the `NO_COLOR` env var is set.

## Encoding

If the module prints a "Your terminal host is currently using encoding ..." warning or borders show
as `?`/`-`, set UTF-8 before importing (ideally in `$PROFILE`):

```powershell
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
```

Silence the warning without changing encoding: `$env:IgnoreSpectreEncoding = $true`.

## Module loading

- Only **one version** of PwshSpectreConsole (and its Spectre.Console.dll) can be loaded per PowerShell
  process. Importing a different version later fails with `Assembly with same name is already loaded` -
  start a new `pwsh` instead. In scripts, import defensively:
  `if (-not (Get-Module PwshSpectreConsole)) { Import-Module PwshSpectreConsole }`.
- Modules that load a different Spectre.Console.dll version into the same session conflict the same way.
- Declare the dependency: `#Requires -Modules @{ ModuleName = 'PwshSpectreConsole'; ModuleVersion = '2.6.3' }`
  (minimum version; use `RequiredVersion` to pin exactly).
