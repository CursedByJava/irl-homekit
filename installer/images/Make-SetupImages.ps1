# Draws Setup.exe's artwork from the IRL Homekit logo (dashboard/public/icon.svg): the side panel on the first and
# last pages (wizard-*.png) and the icon at the top of the other pages (small-*.png), at several sizes so Setup can
# pick a sharp one for the screen's scaling. Run it again after changing the logo; the PNGs are committed.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot
$c1 = [Drawing.Color]::FromArgb(255, 0xFF, 0x6A, 0x3D); $c2 = [Drawing.Color]::FromArgb(255, 0xFF, 0x2D, 0x55); $c3 = [Drawing.Color]::FromArgb(255, 0xD4, 0x14, 0x5A)

function Gradient($rect) {
    $b = New-Object Drawing.Drawing2D.LinearGradientBrush $rect, $c1, $c3, 60.0
    $blend = New-Object Drawing.Drawing2D.ColorBlend 3
    $blend.Colors = [Drawing.Color[]]@($c1, $c2, $c3); $blend.Positions = [single[]]@(0, 0.55, 1); $b.InterpolationColors = $blend; $b
}
# The logo's broadcast mark (two pairs of arcs and a dot), centred at (cx, cy), in a 512-unit logo scaled by s.
function Mark($g, $cx, $cy, $s, $alpha = 255) {
    $white = [Drawing.Color]::FromArgb($alpha, 255, 255, 255)
    foreach ($a in @(@(96, 255), @(156, 230))) {
        $pen = New-Object Drawing.Pen ([Drawing.Color]::FromArgb([int]($a[1] * $alpha / 255), 255, 255, 255)), (34 * $s)
        $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
        $r = $a[0] * $s
        $g.DrawArc($pen, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), -40, 80)
        $g.DrawArc($pen, [single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r), 140, 80)
        $pen.Dispose()
    }
    $d = 38 * $s; $g.FillEllipse((New-Object Drawing.SolidBrush $white), [single]($cx - $d), [single]($cy - $d), [single](2 * $d), [single](2 * $d))
}
function RoundRect($x, $y, $w, $h, $r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90); $p.CloseFigure(); $p
}
function Canvas($w, $h) {
    $bmp = New-Object Drawing.Bitmap $w, $h, ([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'; $g.InterpolationMode = 'HighQualityBicubic'
    return $bmp, $g
}

# Side panel: the gradient, a large soft mark behind, the mark, the name and a line about it.
foreach ($w in 202, 336, 430, 534) {
    $h = [int][Math]::Round($w * 314 / 164)
    $bmp, $g = Canvas $w $h
    $g.FillRectangle((Gradient (New-Object Drawing.Rectangle 0, 0, $w, $h)), 0, 0, $w, $h)
    $sh = [int]($h * 0.5)
    $sheen = New-Object Drawing.Drawing2D.LinearGradientBrush (New-Object Drawing.Rectangle 0, -1, $w, ($sh + 2)), ([Drawing.Color]::FromArgb(70, 255, 255, 255)), ([Drawing.Color]::FromArgb(0, 255, 255, 255)), 90.0
    $g.FillRectangle($sheen, 0, 0, $w, $sh)
    Mark $g ($w * 0.5) ($h * 0.86) ($w / 300) 28          # faint, large, low down
    Mark $g ($w * 0.5) ($h * 0.30) ($w / 760)             # the logo mark
    $u = $w / 202
    $name = New-Object Drawing.Font 'Segoe UI Semibold', ([single](22 * $u)), ([Drawing.FontStyle]::Bold), ([Drawing.GraphicsUnit]::Pixel)
    $tag = New-Object Drawing.Font 'Segoe UI', ([single](11.5 * $u)), ([Drawing.FontStyle]::Regular), ([Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object Drawing.StringFormat; $fmt.Alignment = 'Center'
    $g.DrawString('IRL Homekit', $name, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF 0, ([single]($h * 0.47)), $w, ([single](32 * $u))), $fmt)
    $g.DrawString("Your own IRL`nstreaming server", $tag, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(225, 255, 255, 255))), (New-Object Drawing.RectangleF 0, ([single]($h * 0.47 + 34 * $u)), $w, ([single](40 * $u))), $fmt)
    $g.Dispose(); $bmp.Save("$dir\wizard-$w.png", [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}

# Top-right icon: the app icon itself (rounded square, transparent corners).
foreach ($s in 58, 87, 116, 145) {
    $bmp, $g = Canvas $s $s
    $pad = $s * 0.04; $sz = $s - 2 * $pad
    $path = RoundRect $pad $pad $sz $sz ($sz * 115 / 512)
    $g.FillPath((Gradient (New-Object Drawing.Rectangle 0, 0, $s, $s)), $path)
    Mark $g ($s / 2) ($s / 2) ($sz / 512)
    $g.Dispose(); $bmp.Save("$dir\small-$s.png", [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
}
Get-ChildItem $dir -Filter *.png | ForEach-Object { "$($_.Name)  $([Drawing.Image]::FromFile($_.FullName).Size)" }
