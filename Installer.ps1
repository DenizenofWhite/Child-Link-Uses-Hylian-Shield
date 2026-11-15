# Child Link Uses Hylian Shield - installer window (Windows). Started by Install.bat (hidden console).
# Builds the mod from the player's own game files by running install.py, and can change options or uninstall.
# -Test runs the same steps without the window (for automated checks):
#   Installer.ps1 -Test -Action state|install|uninstall -Mode game|emulator -Game <dir> | -Romfs <dir> -Load <dir> [-NoEat]
param(
    [switch]$Test,
    [ValidateSet('state', 'install', 'uninstall')][string]$Action = 'state',
    [ValidateSet('game', 'emulator')][string]$Mode = 'game',
    [string]$Game, [string]$Romfs, [string]$Load,
    [switch]$NoEat
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Title = 'Child Link Uses Hylian Shield'
$Version = '1.0.0'
$ModName = 'Child-Link-Uses-Hylian-Shield'
$DarkLink = 'DarkLink-DemiseGlow'   # has the same options built in (v1.1+)
$TitleId = '0400486024DEC000'
$PythonWinget = 'Python.Python.3.14'
$IssueUrl = 'https://github.com/DenizenofWhite/Child-Link-Uses-Hylian-Shield/issues/new'
$SettingsFile = Join-Path $Here 'installer-settings.json'

# ---- logic (shared by the window and -Test) -------------------------------------------------------------------------
function Test-Python([string]$exe) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe) -or $exe -like '*\WindowsApps\*') { return $null }
    try {
        $v = & $exe -I -c "import sys, compression.zstd; print('%d.%d.%d' % sys.version_info[:3])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return ("$v").Trim() }
    } catch { }
    return $null
}

function Find-Python([string]$saved) {
    $cands = New-Object System.Collections.Generic.List[string]
    if ($saved) { $cands.Add($saved) }
    Get-ChildItem "$env:LOCALAPPDATA\*Builder\versions\*\*\tools\python\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | ForEach-Object { $cands.Add($_.FullName) }
    Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe", "$env:ProgramFiles\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object { $cands.Add($_.FullName) }
    foreach ($n in 'python', 'python3') {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { $cands.Add($c.Source) }
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        try { $p = & py -3.14 -c "import sys; print(sys.executable)" 2>$null; if ($LASTEXITCODE -eq 0) { $cands.Add(("$p").Trim()) } } catch { }
    }
    foreach ($e in $cands) { if (Test-Python $e) { return $e } }
    return $null
}

function Get-ModDir([string]$mode, [string]$game, [string]$load) {
    if ($mode -eq 'game') { if ($game) { return Join-Path (Join-Path $game 'mods') $ModName } }
    elseif ($load) { return Join-Path (Join-Path $load $TitleId) $ModName }
    return $null
}

function Get-InstalledState([string]$modDir) {
    # merged into Dark Link and Demise Glow (installed next to it): its note sits in that mod's addons folder
    if ($modDir) {
        $note = Join-Path (Join-Path (Join-Path (Split-Path $modDir) $DarkLink) 'addons') ($ModName + '.json')
        if (Test-Path -LiteralPath $note) {
            $n = Get-Content -LiteralPath $note -Raw | ConvertFrom-Json
            return [pscustomobject]@{ version = $n.version; no_eat = [bool]$n.options.no_eat; merged = $true }
        }
    }
    if (-not $modDir -or -not (Test-Path -LiteralPath $modDir)) { return $null }
    $j = Join-Path $modDir 'install.json'
    if (Test-Path -LiteralPath $j) { return (Get-Content -LiteralPath $j -Raw | ConvertFrom-Json) }
    return [pscustomobject]@{ version = '?'; no_eat = $false }
}

function Get-GameProcess([string]$game) {
    if (-not $game) { return $null }
    $g = (Resolve-Path -LiteralPath $game -ErrorAction SilentlyContinue)
    if (-not $g) { return $null }
    $g = $g.Path.TrimEnd('\') + '\'
    Get-Process -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($g, [StringComparison]::OrdinalIgnoreCase) } catch { $false }
    } | Select-Object -First 1
}

function Get-InstallArgs([string]$action, [string]$mode, [string]$game, [string]$romfs, [string]$load, [bool]$noEat) {
    $a = @('-u', '-I', (Join-Path $Here 'install.py'))
    if ($mode -eq 'game') { $a += @('--hookshot', $game.TrimEnd('\')) }
    else { $a += @('--romfs', $romfs.TrimEnd('\'), '--emulator-load', $load.TrimEnd('\')) }
    if ($action -eq 'uninstall') { $a += '--uninstall' } elseif ($noEat) { $a += '--no-eat' }
    return $a
}

function Join-Args([string[]]$a) {
    ($a | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
}

function Start-Proc([string]$exe, [string[]]$argv) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = Join-Args $argv
    $psi.WorkingDirectory = $Here
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Test-Inputs([string]$action, [string]$mode, [string]$game, [string]$romfs, [string]$load) {
    if ($mode -eq 'game') {
        if (-not $game -or -not (Test-Path -LiteralPath (Join-Path $game 'romfs'))) {
            return "Choose your Longshot or Hookshot folder (the one that contains 'romfs' and 'mods')."
        }
        if (Get-GameProcess $game) { return 'The game is running. Close it first, then try again.' }
    } else {
        if ($action -ne 'uninstall' -and (-not $romfs -or -not (Test-Path -LiteralPath $romfs))) {
            return "Choose the 'romfs' folder of your own game dump."
        }
        if (-not $load -or -not (Test-Path -LiteralPath $load)) { return "Choose your emulator's 'load' folder." }
    }
    return $null
}

# ---- -Test: the same steps without the window ------------------------------------------------------------------------
if ($Test) {
    $py = Find-Python $null
    $mod = Get-ModDir $Mode $Game $Load
    "python: $py ($(Test-Python $py))"
    "mod folder: $mod"
    "installed before: $((Get-InstalledState $mod) | ConvertTo-Json -Compress)"
    if ($Action -ne 'state') {
        $err = Test-Inputs $Action $Mode $Game $Romfs $Load
        if ($err) { "REFUSED: $err"; exit 2 }
        if (-not $py) { 'REFUSED: no Python 3.14'; exit 2 }
        $p = Start-Proc $py (Get-InstallArgs $Action $Mode $Game $Romfs $Load ([bool]$NoEat))
        $out = $p.StandardOutput.ReadToEndAsync(); $er = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $out.Result; $er.Result
        "exit: $($p.ExitCode)"
        "installed after: $((Get-InstalledState $mod) | ConvertTo-Json -Compress)"
        exit $p.ExitCode
    }
    exit 0
}

# ---- the window -------------------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
try {
# Tell Windows this window handles high-DPI screens itself (sharp text at 125-200 % scaling instead of a stretched,
# blurry bitmap). Layout below is in 96-DPI units; AutoScaleMode Dpi scales it to the screen.
Add-Type -Namespace DLD -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[void][DLD.Dpi]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()
$Clr = @{
    bg = [System.Drawing.Color]::FromArgb(10, 13, 22); panel = [System.Drawing.Color]::FromArgb(20, 27, 42)
    text = [System.Drawing.Color]::FromArgb(242, 246, 252); muted = [System.Drawing.Color]::FromArgb(178, 192, 214)
    red = [System.Drawing.Color]::FromArgb(26, 70, 160); red2 = [System.Drawing.Color]::FromArgb(44, 98, 200)
    ember = [System.Drawing.Color]::FromArgb(150, 200, 255); ok = [System.Drawing.Color]::FromArgb(140, 228, 150)
    bad = [System.Drawing.Color]::FromArgb(240, 110, 100); log = [System.Drawing.Color]::FromArgb(176, 212, 255)
}

$HdrFrames = 60; $HdrTick = 50        # header animation: 60 frames x 50 ms = one seamless 3-second loop
function New-HeaderImage([int]$w, [int]$h, [single]$scale = 1, [double]$phase = 0) {
    # Original art, drawn here: a blue kite shield giving off light (no game assets, no game crest). $phase (0..1) is
    # the position in the animation loop: the glow pulses, a sheen sweeps across the face, motes of light rise and fade.
    $bmp = New-Object System.Drawing.Bitmap ([int]($w * $scale)), ([int]($h * $scale))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.ScaleTransform($scale, $scale)
    $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAlias'
    $rect = New-Object System.Drawing.Rectangle 0, 0, $w, $h
    $bgb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(8, 11, 20), [System.Drawing.Color]::FromArgb(14, 30, 64), 0.0)
    $g.FillRectangle($bgb, $rect)
    $rnd = New-Object System.Random 7
    for ($i = 0; $i -lt 14; $i++) {                 # soft blue haze
        $cx = 300 + $rnd.Next(0, 300); $cy = $rnd.Next(10, $h - 10); $r = $rnd.Next(30, 80)
        $sb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(10, 60, 120, 230))
        $g.FillEllipse($sb, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    }
    $st = $g.Save()
    $g.TranslateTransform(500, 56); $g.RotateTransform(-8)
    $sp = New-Object System.Drawing.Drawing2D.GraphicsPath      # kite shield: rounded top, long taper to a point
    $sp.AddBezier(-26, -36, -10, -40, 10, -40, 26, -36)       # nearly flat top
    $sp.AddBezier(26, -36, 31, -35, 33, -32, 33, -26)         # squared-off shoulders (small rounding)
    $sp.AddBezier(33, -26, 33, 0, 20, 22, 0, 40)
    $sp.AddBezier(0, 40, -20, 22, -33, 0, -33, -26)
    $sp.AddBezier(-33, -26, -33, -32, -31, -35, -26, -36)
    $sp.CloseFigure()
    $pulse = 0.5 - 0.5 * [Math]::Cos(4 * [Math]::PI * $phase)      # glow breathes twice per loop
    for ($k = 7; $k -ge 1; $k--) {                  # glow
        $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb([int](10 + 13 * $pulse), 120, 180, 255)), ((3 * $k + 2) * (1 + 0.2 * $pulse))
        $pen.LineJoin = 'Round'; $g.DrawPath($pen, $sp)
    }
    $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.PointF 0, -46), (New-Object System.Drawing.PointF 0, 48),
        [System.Drawing.Color]::FromArgb(48, 96, 196), [System.Drawing.Color]::FromArgb(12, 30, 92))
    $g.FillPath($fb, $sp)
    $silver = [System.Drawing.Color]::FromArgb(214, 224, 238)
    $g.SetClip($sp)                                   # emblem (original): a silver cross with a diamond boss
    $band = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(205, 214, 224, 238))
    $g.FillRectangle($band, -3.5, -50, 7, 102); $g.FillRectangle($band, -32, -21.5, 64, 7)
    $g.ResetClip()
    $dm = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF 0, -29), (New-Object System.Drawing.PointF 8, -18), (New-Object System.Drawing.PointF 0, -7), (New-Object System.Drawing.PointF -8, -18))
    $g.FillPolygon((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 246, 255))), $dm)
    $g.DrawPolygon((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 60, 90, 150)), 1), $dm)
    $sx = -70 + 140 * $phase                        # sheen: a white band sweeping across the face
    $sr = New-Object System.Drawing.RectangleF ([single]($sx - 18)), -50, 36, 100
    $sh = New-Object System.Drawing.Drawing2D.LinearGradientBrush($sr, [System.Drawing.Color]::Transparent, [System.Drawing.Color]::Transparent, 0.0)
    $cb = New-Object System.Drawing.Drawing2D.ColorBlend 3
    $cb.Colors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, 230, 242, 255), [System.Drawing.Color]::FromArgb(150, 236, 246, 255), [System.Drawing.Color]::FromArgb(0, 230, 242, 255))
    $cb.Positions = [single[]]@(0, 0.5, 1); $sh.InterpolationColors = $cb
    $g.SetClip($sp); $g.FillRectangle($sh, $sr); $g.ResetClip()
    $rim = New-Object System.Drawing.Pen $silver, 3.6; $rim.LineJoin = 'Round'; $g.DrawPath($rim, $sp)
    $g.DrawPath((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(160, 70, 90, 120)), 1), $sp)
    foreach ($q in @(@(-28, -32), @(28, -32), @(-31, -6), @(31, -6), @(-20, 16), @(20, 16), @(-8, 31), @(8, 31))) {   # rim studs
        $g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(240, 246, 255))), [single]($q[0] - 1.6), [single]($q[1] - 1.6), 3.2, 3.2)
    }
    $g.Restore($st)
    # Light leaving the shield. Every particle's state is a function of the loop position, so the loop is seamless.
    # Soft motes: white core -> pale blue -> deep blue edge, rising and swaying, shrinking as they fade.
    $er = New-Object System.Random 11
    $core = @(244, 250, 255); $mid = @(130, 190, 255); $edge = @(16, 50, 140)
    for ($i = 0; $i -lt 30; $i++) {
        $u = 2 * $er.NextDouble() - 1; $v = $er.NextDouble(); $off = $er.NextDouble(); $life = 0.45 + 0.4 * $er.NextDouble()
        $r0 = 4 + 6 * $er.NextDouble(); $seed = 6.28 * $er.NextDouble(); $jit = $er.Next(-4, 5)
        $k = ((($phase - $off) % 1 + 1) % 1) / $life
        if ($k -ge 1) { continue }
        $x = 500 + $u * 31 * (1 - 0.7 * $v) + 6 * $k + 4 * [Math]::Sin($seed + 7 * $k); $y = 22 + 64 * $v + $jit - 52 * $k
        $r = $r0 * (1 - 0.75 * $k)
        if ($k -lt 0.25) { $q = $k / 0.25; $c0 = $core; $c1 = $mid } else { $q = ($k - 0.25) / 0.75; $c0 = $mid; $c1 = $edge }
        $rgb = 0..2 | ForEach-Object { [int]($c0[$_] + ($c1[$_] - $c0[$_]) * $q) }
        $al = $(if ($k -lt 0.12) { $k / 0.12 } else { 1 - ($k - 0.12) / 0.88 }) * 0.55
        $ep = New-Object System.Drawing.Drawing2D.GraphicsPath
        $ep.AddEllipse([single]($x - $r), [single]($y - $r), [single](2 * $r), [single](2 * $r))
        $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush $ep
        $pg.CenterColor = [System.Drawing.Color]::FromArgb([int](255 * $al), $rgb[0], $rgb[1], $rgb[2])
        $pg.SurroundColors = [System.Drawing.Color[]]@([System.Drawing.Color]::FromArgb(0, $rgb[0], $rgb[1], $rgb[2]))
        $g.FillPath($pg, $ep); $pg.Dispose(); $ep.Dispose()
    }
    for ($i = 0; $i -lt 40; $i++) {                 # bright sparkles: faster, once or twice per loop
        $ex = 460 + 80 * $rnd.NextDouble(); $ey = 18 + 80 * $rnd.NextDouble()
        $sz = 1 + $rnd.Next(0, 3); $a = $rnd.Next(110, 240); $bc = $rnd.Next(200, 256)
        $spd = 1 + ($i % 2); $life = 0.5; $off = $er.NextDouble()
        $k = ((($phase * $spd - $off) % 1 + 1) % 1) / $life
        if ($k -ge 1) { continue }
        $fade = [Math]::Sin([Math]::PI * $k)
        $eb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb([int]($a * $fade), [int]($bc * 0.8), [int]($bc * 0.92), 255))
        $g.FillEllipse($eb, [single]($ex + 4 * $k), [single]($ey - 36 * $k), $sz, $sz); $eb.Dispose()
    }
    $g.DrawString($Title, (New-Object System.Drawing.Font('Segoe UI Semibold', 19)), (New-Object System.Drawing.SolidBrush $Clr.text), 14, 16)
    $g.DrawString('Builds the mod from your own copy of the game.', (New-Object System.Drawing.Font('Segoe UI', 10)), (New-Object System.Drawing.SolidBrush $Clr.muted), 17, 57)
    $g.DrawString("by DenizenofWhite   v$Version", (New-Object System.Drawing.Font('Segoe UI', 9.5, [System.Drawing.FontStyle]::Italic)), (New-Object System.Drawing.SolidBrush $Clr.ember), 17, 80)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $Clr.red), 0, ($h - 2), $w, 2)
    $g.Dispose()
    return $bmp
}

$settings = @{}
try { if (Test-Path $SettingsFile) { (Get-Content $SettingsFile -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $settings[$_.Name] = $_.Value } } } catch { }
$script:python = Find-Python $settings['python']
$script:proc = $null; $script:procKind = $null; $script:busy = $false

$f = New-Object System.Windows.Forms.Form
$f.SuspendLayout()
$f.AutoScaleMode = 'None'   # scaled once, by hand, after the layout is built (see below)
$f.Text = "$Title - Installer"
$f.ClientSize = New-Object System.Drawing.Size(600, 612)
$f.FormBorderStyle = 'FixedSingle'; $f.MaximizeBox = $false; $f.StartPosition = 'CenterScreen'
$f.Font = New-Object System.Drawing.Font('Segoe UI', 12)
$f.BackColor = $Clr.bg; $f.ForeColor = $Clr.text

$hdr = New-Object System.Windows.Forms.PictureBox
$hdr.Location = New-Object System.Drawing.Point(0, 0); $hdr.Size = New-Object System.Drawing.Size(600, 110)
$hdr.SizeMode = 'Zoom'
$hdrBig = New-HeaderImage 600 110 2                  # drawn at 2x so it stays crisp when Windows scales the window
$hdr.Image = $hdrBig
$f.Controls.Add($hdr)

function Add-Group($text, $y, $h) {
    $g = New-Object System.Windows.Forms.GroupBox
    $g.Text = $text; $g.ForeColor = $Clr.ember; $g.Location = New-Object System.Drawing.Point(12, $y); $g.Size = New-Object System.Drawing.Size(576, $h)
    $f.Controls.Add($g); return $g
}
function Add-Radio($parent, $text, $x, $y, $w) {
    $r = New-Object System.Windows.Forms.RadioButton
    $r.Text = $text; $r.ForeColor = $Clr.text; $r.UseMnemonic = $false; $r.AutoSize = $true
    $r.Location = New-Object System.Drawing.Point($x, $y)
    $parent.Controls.Add($r); return $r
}
function Style-Button($b, $primary) {
    $b.FlatStyle = 'Flat'; $b.UseMnemonic = $false; $b.ForeColor = $Clr.text; $b.Cursor = 'Hand'
    $b.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
    if ($primary) { $b.BackColor = $Clr.red; $b.FlatAppearance.BorderColor = $Clr.ember; $b.FlatAppearance.MouseOverBackColor = $Clr.red2 }
    else { $b.BackColor = $Clr.panel; $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(110, 40, 40)
           $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(56, 34, 34) }
}
function New-Button($text, $x, $y, $w, $h, $primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, $h)
    Style-Button $b $primary; return $b
}
function Add-PathRow($parent, $label, $y, $value) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $label; $l.ForeColor = $Clr.text; $l.UseMnemonic = $false
    $l.Location = New-Object System.Drawing.Point(12, ($y + 3)); $l.Size = New-Object System.Drawing.Size(150, 20)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point(165, $y); $t.Size = New-Object System.Drawing.Size(310, 23); $t.Text = $value
    $t.BackColor = $Clr.panel; $t.ForeColor = $Clr.text; $t.BorderStyle = 'FixedSingle'
    $b = New-Button 'Browse...' 482 ($y - 1) 80 25 $false
    $b.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; if ($t.Text) { $d.SelectedPath = $t.Text }
                   if ($d.ShowDialog() -eq 'OK') { $t.Text = $d.SelectedPath } }.GetNewClosure())
    $parent.Controls.AddRange(@($l, $t, $b)); return @{ label = $l; box = $t; button = $b }
}
function New-Label($parent, $x, $y, $w, $h) {
    $l = New-Object System.Windows.Forms.Label
    $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, $h); $l.UseMnemonic = $false
    $parent.Controls.Add($l); return $l
}

$g1 = Add-Group '2. Your Game' 186 176
$rGame = Add-Radio $g1 'Longshot / Hookshot' 12 22 180
$rEmu = Add-Radio $g1 'Emulator' 200 22 120
$pGame = Add-PathRow $g1 'Game Folder:' 52 $settings['game']
$pRomfs = Add-PathRow $g1 'Game Files (romfs):' 52 $settings['romfs']
$pLoad = Add-PathRow $g1 'Emulator Load Folder:' 84 $settings['load']
$lState = New-Label $g1 12 118 550 48
$lState.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)

$g2 = Add-Group '3. Options' 370 60
$cNoEat = New-Object System.Windows.Forms.CheckBox
$cNoEat.Text = "Like Likes Can't Eat Your Shield (Experimental)"; $cNoEat.ForeColor = $Clr.text; $cNoEat.UseMnemonic = $false
$cNoEat.AutoSize = $true; $cNoEat.Location = New-Object System.Drawing.Point(12, 24); $g2.Controls.Add($cNoEat)

$g4 = Add-Group '1. Prerequisites' 120 58
function Add-PrereqRow($y, $name) {
    $n = New-Label $g4 12 ($y + 4) 230 22; $n.Text = $name; $n.ForeColor = $Clr.text
    $s = New-Label $g4 245 ($y + 4) 90 22; $s.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
    $i = New-Button 'Install Prerequisite' 380 $y 184 28 $false
    $g4.Controls.Add($i)
    return @{ status = $s; install = $i; tried = $false }
}
$rowPy = Add-PrereqRow 20 'Python 3.14'

$bInstall = New-Button 'Install / Change' 12 442 190 36 $true
$bInstall.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$bUninstall = New-Button 'Uninstall (Back to Stock)' 210 442 182 36 $false
$bReport = New-Button 'Report a Problem' 400 442 122 36 $false
$bClose = New-Button 'Close' 528 442 60 36 $false
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.WordWrap = $true
$log.Location = New-Object System.Drawing.Point(12, 488); $log.Size = New-Object System.Drawing.Size(576, 112)
$log.Font = New-Object System.Drawing.Font('Consolas', 10); $log.BackColor = [System.Drawing.Color]::FromArgb(10, 7, 7)
$log.ForeColor = $Clr.log; $log.BorderStyle = 'FixedSingle'
$f.Controls.AddRange(@($bInstall, $bUninstall, $bReport, $bClose, $log))

function Write-Log($s) { $log.AppendText($s + "`r`n") }
function Get-Mode { if ($rEmu.Checked) { 'emulator' } else { 'game' } }
function Show-Msg($text, $icon) { [System.Windows.Forms.MessageBox]::Show($text, $Title, 'OK', $icon) | Out-Null }

function Test-Prereq([string]$which) {
    # Check Again: look for Python again.
    $script:python = Find-Python $script:python; Update-View; return [bool]$script:python
}

function Show-Manual([string]$which, [string]$why) {
    # When Install Prerequisite fails: what to do by hand, the right download page, and Check Again.
    $m = New-Object System.Windows.Forms.Form
    $m.Text = 'Install by Hand'; $m.ClientSize = New-Object System.Drawing.Size(500, 250); $m.FormBorderStyle = 'FixedDialog'
    $m.MaximizeBox = $false; $m.MinimizeBox = $false; $m.StartPosition = 'CenterParent'; $m.BackColor = $Clr.bg; $m.ForeColor = $Clr.text
    $m.Font = $f.Font
    $t = New-Object System.Windows.Forms.Label
    $t.Location = New-Object System.Drawing.Point(16, 14); $t.Size = New-Object System.Drawing.Size(470, 175); $t.UseMnemonic = $false
    $page = 'https://www.python.org/downloads/'
    $t.Text = "Python couldn't be installed automatically$(if ($why) { " ($why)" }).`r`n`r`n" +
              "1. Click Open Download Page and download the Windows installer for Python 3.14 or newer.`r`n" +
              "2. Run it. The default options are fine.`r`n" +
              "3. Click Check Again."
    $b1 = New-Button 'Open Download Page' 16 200 170 34 $true
    $b1.Add_Click({ Start-Process $page }.GetNewClosure())
    $b2 = New-Button 'Check Again' 194 200 120 34 $false
    $b2.Add_Click({ if (Test-Prereq $which) { $m.Close() } else { Show-Msg 'Still not found. Follow the steps above, then click Check Again.' 'Information' } }.GetNewClosure())
    $bx = New-Button 'Close' 404 200 80 34 $false
    $bx.Add_Click({ $m.Close() }.GetNewClosure())
    $m.Controls.AddRange(@($t, $b1, $b2, $bx))
    [void]$m.ShowDialog($f)
}

function Set-Row($row, [bool]$ok) {
    if ($ok) { $row.status.Text = 'Installed'; $row.status.ForeColor = $Clr.ok } else { $row.status.Text = 'Missing'; $row.status.ForeColor = $Clr.bad }
    $row.install.Visible = -not $ok
    $row.install.Text = if ($row.tried) { 'Check Again' } else { 'Install Prerequisite' }
}

function Update-View {
    $emu = $rEmu.Checked
    foreach ($c in $pGame.Values) { $c.Visible = -not $emu }
    foreach ($c in (@($pRomfs.Values) + @($pLoad.Values))) { $c.Visible = $emu }
    $mod = Get-ModDir (Get-Mode) $pGame.box.Text $pLoad.box.Text
    $st = Get-InstalledState $mod
    if ($st) { $lState.Text = "Installed Now: Child Link Uses Hylian Shield" + $(if ($st.no_eat) { " + Like Likes Can't Eat Your Shield" } else { '' }) + " (v$($st.version))" + $(if ($st.merged) { "`r`n(added into Dark Link and Demise Glow)" } else { '' }); $lState.ForeColor = $Clr.ok }
    elseif ($mod) { $lState.Text = 'Not installed in this game.'; $lState.ForeColor = $Clr.muted }
    else { $lState.Text = 'Choose your game folder above.'; $lState.ForeColor = $Clr.muted }
    if ($script:S) { $lState.Top = [int]($(if ($emu) { 118 } else { 86 }) * $script:S) }   # no empty gap in Longshot/Hookshot mode
    Set-Row $rowPy ([bool]$script:python)
}

function Save-Settings {
    $o = @{ python = $script:python; mode = (Get-Mode); game = $pGame.box.Text; romfs = $pRomfs.box.Text; load = $pLoad.box.Text
            no_eat = [bool]$cNoEat.Checked }
    try { $o | ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8 } catch { }
}

function Set-Busy($busy, $label) {
    if ($busy -and $script:procKind -in 'mod', 'uninstall') {
        if ($script:procKind -eq 'uninstall') { $lState.Text = 'Uninstalling...' }
        else { $lState.Text = "Installing: $($script:pending)..." }
        $lState.ForeColor = $Clr.ember
    }
    # While working, lock the choices WITHOUT greying them out (Windows' grey "disabled" text is unreadable on dark).
    foreach ($r in @($rGame, $rEmu)) { $r.AutoCheck = -not $busy }
    $cNoEat.AutoCheck = -not $busy
    foreach ($t in @($pGame.box, $pRomfs.box, $pLoad.box)) { $t.ReadOnly = $busy }
    $script:busy = $busy
    $bInstall.Text = if ($busy) { $label } else { 'Install / Change' }
    if (-not $busy) { $bInstall.BackColor = $Clr.red; Update-View }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300
$script:rdOut = $null; $script:rdErr = $null; $script:tick = 0
$timer.Add_Tick({
    if (-not $script:proc) { return }
    $script:tick++
    $bInstall.BackColor = if ($script:tick % 4 -lt 2) { $Clr.red } else { $Clr.red2 }    # pulse while working
    foreach ($k in 'rdOut', 'rdErr') {
        while ($true) {
            $t = Get-Variable -Scope Script -Name $k -ValueOnly
            if (-not $t.IsCompleted -or $null -eq $t.Result) { break }
            Write-Log $t.Result
            $s = if ($k -eq 'rdOut') { $script:proc.StandardOutput } else { $script:proc.StandardError }
            Set-Variable -Scope Script -Name $k -Value $s.ReadLineAsync()
        }
    }
    if ($script:proc.HasExited -and $script:rdOut.IsCompleted -and $null -eq $script:rdOut.Result -and
        $script:rdErr.IsCompleted -and $null -eq $script:rdErr.Result) {
        $code = $script:proc.ExitCode; $kind = $script:procKind
        $script:proc = $null; $timer.Stop()
        if ($kind -eq 'python') { $script:python = Find-Python $null }
        Set-Busy $false
        if ($code -eq 0 -and ($kind -ne 'python' -or $script:python)) {
            if ($kind -eq 'python') { Write-Log '--- Python installed. ---'; Show-Msg 'Python is installed.' 'Information' }
            elseif ($kind -eq 'uninstall') { Write-Log '--- Uninstalled. Your game is back to stock. ---'; Show-Msg 'Uninstalled. Your game is back to stock.' 'Information' }
            else { Write-Log '--- Done. Start the game. ---'; Show-Msg 'Done! Start the game.' 'Information' }
        } else {
            Write-Log "--- Failed (exit $code). See the messages above. ---"
            if ($kind -eq 'python') { $rowPy.tried = $true; Update-View; Show-Manual 'python' "winget exit $code" }
            else { Show-Msg "Something went wrong. Your game was not changed.`r`n`r`nThe messages are in the window. If you want help, click Report a Problem." 'Warning' }
        }
    }
})

function Start-Logged($kind, $label, $exe, $argv) {
    try { $script:proc = Start-Proc $exe $argv } catch { Write-Log "Could not start: $_"; return }
    $script:procKind = $kind
    $script:rdOut = $script:proc.StandardOutput.ReadLineAsync()
    $script:rdErr = $script:proc.StandardError.ReadLineAsync()
    Set-Busy $true $label
    $timer.Start()
}

function Invoke-Action($action) {
    if ($script:busy) { return }
    $mode = Get-Mode
    $err = Test-Inputs $action $mode $pGame.box.Text $pRomfs.box.Text $pLoad.box.Text
    if (-not $err -and -not $script:python -and -not (Test-Prereq 'python')) { $err = 'Python 3.14 is missing: click Install Prerequisite next to it (step 1).' }
    if ($err) { Show-Msg $err 'Information'; return }
    if ($action -eq 'uninstall' -and -not (Get-InstalledState (Get-ModDir $mode $pGame.box.Text $pLoad.box.Text))) {
        Show-Msg 'The mod is not installed in this game, so there is nothing to uninstall.' 'Information'; return
    }
    if ($action -eq 'uninstall') {
        $ok = [System.Windows.Forms.MessageBox]::Show('Remove the mod and put the game back to stock?', 'Uninstall', 'YesNo', 'Question')
        if ($ok -ne 'Yes') { return }
    }
    Save-Settings
    $log.Clear()
    $script:pending = 'Child Link Uses Hylian Shield' + $(if ($cNoEat.Checked) { " + Like Likes Can't Eat Your Shield" } else { '' })
    Write-Log $(if ($action -eq 'install') { "Installing: $($script:pending)..." } else { 'Uninstalling...' })
    $kind = if ($action -eq 'uninstall') { 'uninstall' } else { 'mod' }
    $label = if ($action -eq 'uninstall') { 'Uninstalling Mod...' } else { 'Installing Mod...' }
    Start-Logged $kind $label $script:python (Get-InstallArgs $action $mode $pGame.box.Text $pRomfs.box.Text $pLoad.box.Text ([bool]$cNoEat.Checked))
}

$rGame.Add_CheckedChanged({ Update-View }); $rEmu.Add_CheckedChanged({ Update-View })
$pGame.box.Add_TextChanged({ Update-View }); $pLoad.box.Add_TextChanged({ Update-View })
$bInstall.Add_Click({ Invoke-Action 'install' })
$bUninstall.Add_Click({ Invoke-Action 'uninstall' })
$bClose.Add_Click({ $f.Close() })
function Get-Report {
    # What a bug report carries: versions, tools found, and the window's messages, with the user's name and home folder
    # replaced by placeholders (nothing personal leaves the PC).
    $head = "$Title installer v$Version | Windows $([Environment]::OSVersion.Version) | Python " +
            $(if ($script:python) { Test-Python $script:python } else { 'none' }) +
            " | mode $(Get-Mode), like likes option $([bool]$cNoEat.Checked)"
    $text = $head + "`r`n" + $log.Text
    foreach ($p in @($env:USERPROFILE, $env:LOCALAPPDATA, $env:APPDATA) | Sort-Object Length -Descending) {
        if ($p) { $text = $text.Replace($p, '%' + $(if ($p -eq $env:USERPROFILE) { 'USERPROFILE' } elseif ($p -eq $env:LOCALAPPDATA) { 'LOCALAPPDATA' } else { 'APPDATA' }) + '%') }
    }
    if ($env:USERNAME) { $text = [regex]::Replace($text, [regex]::Escape($env:USERNAME), '<user>', 'IgnoreCase') }
    return $text
}
$bReport.Add_Click({
    $ok = [System.Windows.Forms.MessageBox]::Show("Open a bug report on the mod's GitHub page in your browser?`r`n`r`nIt is filled in with the installer version, your Windows version, the prerequisites found and the window's last messages. Your user name and folders are hidden. Nothing is sent until you review it and click submit (you need a free GitHub account).`r`n`r`nThe full log is also copied to your clipboard.", 'Report a Problem', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { return }
    $rep = Get-Report
    [System.Windows.Forms.Clipboard]::SetText($rep)
    $lines = $rep -split "`r?`n"
    $body = "**What happened?**`n(describe it here)`n`n**Installer details and last messages:**`n" + '```' + "`n" +
            (($lines | Select-Object -First 1) + "`n" + (($lines | Select-Object -Skip 1 | Select-Object -Last 40) -join "`n")) + "`n" + '```'
    Add-Type -AssemblyName System.Web
    $url = $IssueUrl + '?title=' + [System.Web.HttpUtility]::UrlEncode("Installer problem (v$Version)") + '&body=' + [System.Web.HttpUtility]::UrlEncode($body)
    Start-Process $url
})
$rowPy.install.Add_Click({ if ($script:busy) { return }
    if ($rowPy.tried) {
        if (Test-Prereq 'python') { Write-Log "Python $(Test-Python $script:python) found." }
        else { Show-Msg 'Python 3.14 still not found. Install it, then click Check Again.' 'Information' }
        return
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { $rowPy.tried = $true; Update-View; Show-Manual 'python' "winget isn't available on this PC"; return }
    $ok = [System.Windows.Forms.MessageBox]::Show("Install Python 3.14 for your Windows user with winget (Windows' own installer)?`r`n`r`nPackage: $PythonWinget (Python Software Foundation, python.org).`r`nThis accepts Python's license and the winget catalog terms.", 'Install Prerequisite', 'YesNo', 'Question')
    if ($ok -ne 'Yes') { return }
    $log.Clear(); Write-Log 'Installing Python 3.14 with winget...'
    Start-Logged 'python' 'Installing Prerequisite...' 'winget' @('install', '--id', $PythonWinget, '--exact', '--scope', 'user', '--silent',
                                      '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
})
$f.Add_FormClosing({ param($s, $e)
    if ($script:proc -and -not $script:proc.HasExited) {
        $ok = [System.Windows.Forms.MessageBox]::Show('Still working. Close anyway? (The mod will not be changed.)', 'Close', 'YesNo', 'Warning')
        if ($ok -ne 'Yes') { $e.Cancel = $true } else { try { $script:proc.Kill() } catch { } }
    }
})

# Install.bat starts PowerShell hidden, and Windows applies that "hidden" to the first window a program shows. Use it
# up on purpose while the form loads, then show the form explicitly.
Add-Type -Namespace DLD -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
$f.Add_Load({ [void][DLD.Win]::ShowWindow($f.Handle, 0) })
$f.Add_Shown({ [void][DLD.Win]::ShowWindow($f.Handle, 5); $f.Activate() })

# Scale the finished layout ONCE: x1.2 (bigger text and room for it) x the screen's DPI. Fonts are in points, so
# Windows already draws them at the screen's DPI.
$script:S = 1.2 * ($f.DeviceDpi / 96.0)
$f.Scale((New-Object System.Drawing.SizeF($script:S, $script:S)))
$f.ResumeLayout($false); $f.PerformLayout()
# Header animation: each frame is drawn once at the header's real on-screen size (crisp at any DPI), on its first turn
# in the loop, then reused, so after the first 3 seconds the timer only swaps pictures. Paused while minimized.
$script:hf = 0; $script:hframes = New-Object 'object[]' $HdrFrames
$anim = New-Object System.Windows.Forms.Timer; $anim.Interval = $HdrTick
$anim.Add_Tick({
    if ($f.WindowState -eq 'Minimized') { return }
    $script:hf = ($script:hf + 1) % $HdrFrames
    $fr = $script:hframes[$script:hf]
    if (-not $fr) { try { $fr = New-HeaderImage 600 110 $script:S ($script:hf / $HdrFrames); $script:hframes[$script:hf] = $fr } catch { $anim.Stop(); return } }
    $hdr.Image = $fr
})
$f.Add_Shown({ $anim.Start() })
$f.Add_FormClosed({ $anim.Stop() })
if ($settings['mode'] -eq 'emulator') { $rEmu.Checked = $true } else { $rGame.Checked = $true }
$cNoEat.Checked = [bool]$settings['no_eat']
Update-View
[void]$f.ShowDialog()
} catch {
    [System.Windows.Forms.MessageBox]::Show("The installer hit an error:`r`n`r`n$_`r`n`r`nYou can still install from the command line (see README).", 'Dark Link and Demise Glow', 'OK', 'Error') | Out-Null
}
