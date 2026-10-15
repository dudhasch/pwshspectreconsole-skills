# pwshspectreconsole-skills

A [Claude Code](https://claude.com/claude-code) plugin with a skill for building correct, good-looking
PowerShell console UIs with [PwshSpectreConsole](https://pwshspectreconsole.com) (Spectre.Console for PowerShell).

When Claude writes or fixes PowerShell that uses `*-Spectre*` cmdlets, the skill gives it the mental model,
the non-obvious pitfalls and tested patterns for:

- **Tables**: calculated columns, column alignment, colored cells, safe markup, nested images/charts/tables in cells, live row updates, raw `Spectre.Console.Table`
- **Images in the terminal**: Sixel vs. blocks/braille/canvas, sizing, images inside panels/tables/grids, galleries, animated GIFs
- **Layout**: panels, rows, columns, grids, padding, alignment, full-screen layouts, measuring
- **Live output**: status spinners, progress bars, background jobs, live-updating tables and dashboards with keyboard input
- **Prompts**: selection/multi-selection/grouped menus, confirm, text, with non-interactive fallbacks
- **Charts and widgets**: bar & breakdown charts, trees, JSON, figlet, rules, calendars, exceptions
- **Markup & output**: escaping, colors, rendering inside functions, encoding, terminal capabilities, raw Spectre.Console API from PowerShell

Every pattern in the references is executed by the test suite against the real module.

## Install

In Claude Code:

```text
/plugin marketplace add dudhasch/pwshspectreconsole-skills
/plugin install pwshspectreconsole@pwshspectreconsole-skills
```

The skill then loads automatically whenever a task involves PwshSpectreConsole (or ask for it: "use the
pwshspectreconsole skill").

Without the plugin system, copy `plugins/pwshspectreconsole/skills/pwshspectreconsole` to
`~/.claude/skills/` (personal) or `.claude/skills/` (project).

## Requirements (for the PowerShell code it produces)

- PowerShell 7.4+
- PwshSpectreConsole 2.6.3+ (`Install-Module PwshSpectreConsole -Scope CurrentUser`)
- A UTF-8 terminal; truecolor recommended; a [Sixel-capable terminal](https://www.arewesixelyet.com) for pixel images

## Layout

```text
.claude-plugin/marketplace.json                 marketplace definition
plugins/pwshspectreconsole/
  .claude-plugin/plugin.json                    plugin manifest
  skills/pwshspectreconsole/
    SKILL.md                                    core rules + routing (loaded when the skill triggers)
    references/                                 topic deep-dives, loaded on demand
      markup-and-output.md  tables.md  layout.md  images.md
      live-and-progress.md  prompts.md  charts-and-widgets.md  dotnet-interop.md
    scripts/Test-SpectreTerminal.ps1            terminal capability check (encoding, colors, Sixel, ...)
    examples/                                   complete runnable scripts
      system-dashboard.ps1  deploy-progress.ps1  interactive-menu.ps1  live-dashboard.ps1
tests/
  Test-Snippets.ps1                             executes the documented patterns
  Invoke-Tests.ps1                              snippets + all examples, non-interactive
```

## Try the examples

```powershell
./plugins/pwshspectreconsole/skills/pwshspectreconsole/scripts/Test-SpectreTerminal.ps1
./plugins/pwshspectreconsole/skills/pwshspectreconsole/examples/system-dashboard.ps1
./plugins/pwshspectreconsole/skills/pwshspectreconsole/examples/deploy-progress.ps1
./plugins/pwshspectreconsole/skills/pwshspectreconsole/examples/interactive-menu.ps1
./plugins/pwshspectreconsole/skills/pwshspectreconsole/examples/live-dashboard.ps1      # q to quit
```

## Tests

```powershell
pwsh -NoProfile -File ./tests/Invoke-Tests.ps1                         # latest installed module
pwsh -NoProfile -File ./tests/Invoke-Tests.ps1 -ModuleVersion 2.6.3    # a specific version
```

CI runs the suite on Linux and Windows for every push.

## Notable pitfalls the skill teaches

| Pitfall | Symptom |
|---|---|
| `Out-SpectreHost` returns a string | functions return extra ANSI text alongside their data |
| unescaped `[`/`]` in data | `Could not find color or style '...'` / `malformed markup tag` |
| markup without `[/]` piped to `Format-*` | markup shown literally |
| renderable in a `[pscustomobject]` table cell | cell shows `Spectre.Console.Panel` |
| `Alignment` in calculated properties | ignored; set `$table.Columns[i].Alignment` |
| calling extension methods on instances | `$table.UpdateCell(...)` → method not found |
| chart hashtables with string colors | `Cannot convert "Green" ... to Spectre.Console.Color` |
| `-Width` > console width | parameter validation error in narrow terminals/CI |
| prompts in CI | `the current terminal isn't interactive` |
| `Receive-Job` after `Wait-SpectreJobs` | native PowerShell progress bar appears under Spectre output |
| live displays without a TTY | every refresh is printed again |
| importing a second module version | `Assembly with same name is already loaded` |

## License

MIT. PwshSpectreConsole is © Shaun Lawrie (MIT); Spectre.Console is © Patrik Svensson, Phil Scott, Nils Andresen (MIT).
This project is not affiliated with either.
