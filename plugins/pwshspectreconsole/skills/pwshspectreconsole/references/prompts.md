# Prompts

All prompts need an **interactive terminal**. In CI, scheduled tasks, `pwsh -c` with redirected I/O, or when
output is piped they throw `Cannot show selection prompt since the current terminal isn't interactive`.
Always provide a non-interactive path (parameters with defaults) and guard:

```powershell
param([string] $Environment)
if (-not $Environment) {
    if ([Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive) {
        $Environment = Read-SpectreSelection -Message "Target environment" -Choices 'dev', 'test', 'prod'
    } else {
        throw "Pass -Environment when running non-interactively."
    }
}
```

Common behavior:
- `-Message` (aliases `-Title`, `-Question`, `-Prompt`) is **markup** - escape dynamic parts.
- **Choice labels are markup** too. Escape them via a label script block (see below).
- `-Color` sets the highlight color; `-PageSize` how many choices are visible (min 3).
- `-TimeoutSeconds` cancels the prompt and returns `$null` after N seconds.
- Ctrl+C cancels and returns `$null` - check for it.
- Prompts can't run inside `Invoke-SpectreLive` / progress / status blocks.

## Single selection

```powershell
$color = Read-SpectreSelection -Message "Pick a color" -Choices 'Red', 'Green', 'Blue' -Color Green -EnableSearch

# Objects: label from a property or script block; the ORIGINAL OBJECT is returned
$svc = Get-Service | Read-SpectreSelection -Message "Restart which service?" -ChoiceLabelProperty Name -PageSize 10
$vm  = Read-SpectreSelection -Message "VM" -Choices $vms -ChoiceLabelProperty { "$($_.Name | Get-SpectreEscapedText) [grey]($($_.State))[/]" }
if ($null -eq $vm) { return }   # cancelled / timed out
```

- Labels must be unique - duplicates throw (`You have duplicate labels...`). Add an id/suffix to the label.
- With plain string choices, labels containing `[`/`]` must be escaped, and the escaped string is returned.
  Prefer objects + `-ChoiceLabelProperty { $_.Name | Get-SpectreEscapedText }` so you get the original object back.
- `-EnableSearch` lets the user type to filter (`-SearchHighlightColor`).

## Multi selection

```powershell
$features = Read-SpectreMultiSelection -Message "Features to install" -Choices 'Docs', 'Tests', 'CI' -PageSize 10
# returns an array; empty selection is rejected unless -AllowEmpty
$picked = Read-SpectreMultiSelection -Message "Servers" -Choices $servers -ChoiceLabelProperty Name -AllowEmpty
```

Space toggles, Enter confirms.

## Grouped choices

```powershell
# Single selection: hashtable of group -> choices (parameter is [hashtable], so group order isn't guaranteed)
$region = Read-SpectreSelectionGrouped -Message "Region" -Choices @{
    'Europe'   = @('westeurope', 'northeurope')
    'Americas' = @('eastus', 'westus2')
}

# Multi selection: array of @{ Name = ...; Choices = @(...) }
$apps = Read-SpectreMultiSelectionGrouped -Message "Apps" -PageSize 12 -Choices @(
    @{ Name = 'Browsers'; Choices = @('Firefox', 'Chrome') }
    @{ Name = 'Editors';  Choices = @('VS Code', 'Vim') }
)
```

## Confirm, text, pause

```powershell
if (Read-SpectreConfirm -Message "Delete [red]$($n)[/] files?" -DefaultAnswer n `
        -ConfirmSuccess "Deleting..." -ConfirmFailure "Aborted.") { ... }      # returns [bool]

$name = Read-SpectreText -Message "Project name" -DefaultAnswer 'demo'          # returns string
$tier = Read-SpectreText -Message "Tier" -Choices 'free', 'pro' -AnswerColor Cyan1   # validated against choices (case-insensitive)
$note = Read-SpectreText -Message "Comment" -AllowEmpty

Read-SpectrePause                                      # "Press <enter> to continue"
Read-SpectrePause -Message "[grey]Press any key...[/]" -AnyKey
```

`Read-SpectreText` has no command history or cursor movement; for long free-text input `Read-Host` is
friendlier. For secrets use `Read-Host -AsSecureString` (the module has no secret prompt) or the raw API:

```powershell
$p = [Spectre.Console.TextPrompt[string]]::new('Password:')
$p = [Spectre.Console.TextPromptExtensions]::Secret($p)        # extension method -> static call
$secret = [Spectre.Console.AnsiConsole]::Prompt($p)      # don't name it $pwd (automatic variable)
```

## Typical wizard pattern

```powershell
Write-SpectreFigletText "Setup" -Color Cyan1
$cfg = [ordered]@{
    Name     = Read-SpectreText -Message "Name" -DefaultAnswer (Split-Path -Leaf $PWD)
    Template = Read-SpectreSelection -Message "Template" -Choices 'api', 'web', 'cli'
    Features = @(Read-SpectreMultiSelection -Message "Features" -Choices 'Docker', 'CI', 'Tests' -AllowEmpty)
}
$cfg | Format-SpectreJson | Format-SpectrePanel -Header "Review"
if (-not (Read-SpectreConfirm -Message "Create project?")) { return }
```
