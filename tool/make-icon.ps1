# Генератор иконки приложения: чёрно-белый знак + бейдж «P» в правом верхнем углу.
#
# Рисует мастер-картинку 1024x1024 и раскладывает её по mipmap-* для Android,
# включая adaptive icon (foreground + background) для Android 8+.
#
# Запуск: powershell -ExecutionPolicy Bypass -File tool\make-icon.ps1

param(
  [string]$Res = (Join-Path (Split-Path -Parent $PSScriptRoot) "android\app\src\main\res")
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$black = [System.Drawing.ColorTranslator]::FromHtml("#0B0B0D")
$white = [System.Drawing.Color]::White

function New-Canvas([int]$size) {
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $bmp.SetResolution(96, 96)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  return @{ Bitmap = $bmp; Graphics = $g }
}

function Get-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $r * 2
  $p.AddArc($x, $y, $d, $d, 180, 90)
  $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure()
  return $p
}

# Знак: треугольник с диагональным вырезом + бейдж «P».
# $scale — во сколько раз ужать содержимое вокруг центра (для adaptive safe zone).
function Draw-Mark($g, [float]$scale, [switch]$Background) {
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.ResetTransform()
  $g.TranslateTransform(512, 512)
  $g.ScaleTransform($scale, $scale)
  $g.TranslateTransform(-512, -512)

  if ($Background) {
    $path = Get-RoundedPath 0 0 1024 1024 232
    $brush = New-Object System.Drawing.SolidBrush $black
    $g.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
  }

  # Треугольник
  $tri = @(
    (New-Object System.Drawing.PointF 512, 232),
    (New-Object System.Drawing.PointF 224, 752),
    (New-Object System.Drawing.PointF 800, 752)
  )
  $whiteBrush = New-Object System.Drawing.SolidBrush $white
  $g.FillPolygon($whiteBrush, $tri)

  # Диагональный вырез (негативное пространство)
  $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
  $clip.AddPolygon($tri)
  $g.SetClip($clip)
  $pen = New-Object System.Drawing.Pen $black, 96
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $g.DrawLine($pen, 210, 748, 806, 286)
  $g.ResetClip()
  $pen.Dispose(); $clip.Dispose()

  # Бейдж «P» в правом верхнем углу
  $cx = 788; $cy = 232; $r = 152
  $g.FillEllipse($whiteBrush, $cx - $r, $cy - $r, $r * 2, $r * 2)

  $font = New-Object System.Drawing.Font "Segoe UI Black", 236, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $blackBrush = New-Object System.Drawing.SolidBrush $black
  $box = New-Object System.Drawing.RectangleF ($cx - $r), ($cy - $r - 6), ($r * 2), ($r * 2)
  $g.DrawString("P", $font, $blackBrush, $box, $fmt)

  $blackBrush.Dispose(); $fmt.Dispose(); $font.Dispose(); $whiteBrush.Dispose()
}

function Save-Scaled($master, [int]$size, [string]$path) {
  $dir = Split-Path -Parent $path
  New-Item -ItemType Directory -Force $dir | Out-Null
  $bmp = New-Object System.Drawing.Bitmap $size, $size
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.DrawImage($master, 0, 0, $size, $size)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# --- мастера ---
$legacy = New-Canvas 1024
Draw-Mark $legacy.Graphics 1.0 -Background
$legacyPath = Join-Path $env:TEMP "finals-icon-legacy.png"
$legacy.Bitmap.Save($legacyPath, [System.Drawing.Imaging.ImageFormat]::Png)

# adaptive: фон отдельным цветом, содержимое в safe zone (66/108)
$fg = New-Canvas 1024
Draw-Mark $fg.Graphics 0.58

# --- раскладка по плотностям ---
$densities = @(
  @{ dir = "mipmap-mdpi"; legacy = 48; fg = 108 },
  @{ dir = "mipmap-hdpi"; legacy = 72; fg = 162 },
  @{ dir = "mipmap-xhdpi"; legacy = 96; fg = 216 },
  @{ dir = "mipmap-xxhdpi"; legacy = 144; fg = 324 },
  @{ dir = "mipmap-xxxhdpi"; legacy = 192; fg = 432 }
)

foreach ($d in $densities) {
  Save-Scaled $legacy.Bitmap $d.legacy (Join-Path $Res "$($d.dir)\ic_launcher.png")
  Save-Scaled $fg.Bitmap $d.fg (Join-Path $Res "$($d.dir)\ic_launcher_foreground.png")
}

# --- adaptive icon ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$anydpi = Join-Path $Res "mipmap-anydpi-v26"
New-Item -ItemType Directory -Force $anydpi | Out-Null
$adaptiveXml = @'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'@
[System.IO.File]::WriteAllText((Join-Path $anydpi "ic_launcher.xml"), $adaptiveXml, $utf8NoBom)

$values = Join-Path $Res "values"
New-Item -ItemType Directory -Force $values | Out-Null
$colorsXml = @'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0B0B0D</color>
</resources>
'@
[System.IO.File]::WriteAllText((Join-Path $values "colors.xml"), $colorsXml, $utf8NoBom)

$legacy.Graphics.Dispose(); $legacy.Bitmap.Dispose()
$fg.Graphics.Dispose(); $fg.Bitmap.Dispose()

Write-Host "Иконки готовы. Превью: $legacyPath"
