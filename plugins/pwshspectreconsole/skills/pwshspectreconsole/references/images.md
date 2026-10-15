# Images in the terminal

`Get-SpectreImage` returns a **renderable**; nothing is drawn until you output it. It can be placed in
panels, tables, grids, columns, layouts and live displays like any other widget.

```powershell
Get-SpectreImage -ImagePath .\logo.png -MaxWidth 40                       # local file
Get-SpectreImage 'https://example.com/logo.png' -MaxWidth 30             # http(s): downloaded once, cached per session
Get-ChildItem .\icons\*.png | Get-SpectreImage -MaxWidth 8                # pipeline (FullName binds to -ImagePath)
```

| Parameter | Notes |
|---|---|
| `-ImagePath` (aliases `-Uri`, `-FullName`) | file path or `http(s)://` URL. PNG, JPEG, GIF (animated), BMP, WebP, TGA, TIFF... (ImageSharp) |
| `-MaxWidth` (alias `-Width`) | width in **console cells**. Always set it - without it the image uses its native pixel size (1 px per cell; clamped to the console width, Sixel also to the console height) |
| `-Format` | `Auto` (default), `Sixel`, `Blocks`, `Braille`, `Canvas` |
| `-Force` | use Sixel even if detection says the terminal doesn't support it |
| `-Animation` | Sixel only: keep all GIF frames so each render shows the next frame (default: first frame only) |

## Render modes

| Format | Class | How it looks | Works in |
|---|---|---|---|
| `Sixel` | `PwshSpectreConsole.PixelImage` | real pixels, best quality | Sixel terminals: Windows Terminal 1.22+, WezTerm, foot, mlterm, xterm (`-ti vt340`), iTerm2, Konsole, VS Code (with `terminal.integrated.enableImages`) |
| `Blocks` (Auto fallback) | `PwshSpectreConsole.CellImage` | half-block characters `▀▄`, 2 pixels per cell, truecolor | any UTF-8 + 24-bit color terminal |
| `Braille` | `CellImage` | braille dots, high detail, one color per cell | UTF-8 terminals with braille glyphs; good for line art/silhouettes |
| `Canvas` | `CellImage` | full blocks `█`, 1 pixel per cell (Spectre canvas look) | most terminals |

`Auto` picks Sixel when the terminal answered the Sixel capability query at module import, otherwise Blocks.
Detection happens **once at `Import-Module`** - in some hosts (tmux, SSH, VS Code without image support,
redirected output) it reports no Sixel; use `-Format Blocks` explicitly for predictable output, or
`-Format Sixel -Force` when you know the terminal supports it. `-Format Sixel` without `-Force` **throws**
when unsupported - don't use it in scripts others will run; prefer `Auto`.

Check support: `scripts/Test-SpectreTerminal.ps1`, or https://www.arewesixelyet.com.

## Sizing

- `-MaxWidth` is in character cells. A cell is roughly twice as tall as wide; block mode compensates
  (2 pixels per cell vertically) so aspect ratio is preserved.
- Images never exceed the space of their container: inside a 30-wide column the image shrinks to fit.
- `-MaxWidth` bigger than the source image upscales it (blurry) - match it to the source for small icons.
- Choose widths per use: icons 4-8, thumbnails in tables 10-16, hero/logo 30-60.
- Sixel images can exceed the visible height and push content up; keep `-MaxWidth` modest.

## Combining with other widgets

```powershell
$img = Get-SpectreImage $path -MaxWidth 20

# Image + caption in one panel (a panel takes ONE renderable)
@($img, "[bold]$($name | Get-SpectreEscapedText)[/]") | Format-SpectreRows | Format-SpectrePanel

# Side by side with text
@($img, $detailsGrid) | Format-SpectreColumns

# Thumbnails in a table: hashtable rows (pscustomobject would print the type name)
Get-ChildItem .\photos\*.jpg | ForEach-Object {
    [ordered]@{ Preview = (Get-SpectreImage $_.FullName -MaxWidth 12); Name = $_.Name; KB = [int]($_.Length / 1KB) }
} | Format-SpectreTable

# Gallery
Get-ChildItem .\icons\*.png | ForEach-Object {
    @((Get-SpectreImage $_.FullName -MaxWidth 10), ($_.BaseName | Get-SpectreEscapedText)) |
        Format-SpectreRows | Format-SpectrePanel
} | Format-SpectreColumns
```

## Animated GIFs

- **Block/Braille/Canvas**: one static frame (the first) is rendered.
- **Sixel with `-Animation`**: each time the same image object is rendered it emits the next frame.
  Animate by re-rendering at the same cursor position:

```powershell
$image = Get-SpectreImage .\spinner.gif -MaxWidth 30 -Animation   # Auto -> Sixel when supported
[Console]::CursorVisible = $false
try {
    Clear-Host
    for ($frame = 0; $frame -lt 60; $frame++) {
        [Console]::SetCursorPosition(0, 0)
        $image | Format-SpectrePanel -Title "Frame $frame" | Out-SpectreHost
        Start-Sleep -Milliseconds 100
    }
} finally { [Console]::CursorVisible = $true }
```

Inside `Invoke-SpectreLive`, just call `$Context.Refresh()` in a loop - the live display redraws in place.

## Deprecated

`Get-SpectreImageExperimental` prints a deprecation warning and will be removed in v3.0. Replace with
`Get-SpectreImage -Format Blocks` (static) or the Sixel loop above (animation).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `?` or boxes instead of blocks | UTF-8 encoding not set (see `markup-and-output.md`) / font lacks glyphs |
| Washed out / banded colors | Terminal isn't truecolor; check `[Spectre.Console.AnsiConsole]::Profile.Capabilities.ColorSystem`. Try `-Format Braille` or accept 256-color output |
| Garbage text like `P0;1q"1;1...` | Sixel sent to a terminal that can't draw it (from `-Force`). Use `Auto`/`Blocks` |
| `The specified image path ... does not exist` | Relative paths resolve against the PowerShell location; use `Join-Path $PSScriptRoot 'img.png'` in scripts |
| Image too large / pushes output | Set `-MaxWidth`, put it in a column/panel with a fixed width |
