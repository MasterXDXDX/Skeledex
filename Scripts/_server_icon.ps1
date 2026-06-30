# =====================================================
#  _server_icon.ps1
#  Genera Instancia\server-icon.png (64x64) con el logo
#  de Skeledex (hexagono de nodos). Salida: OK | ERROR
# =====================================================
Add-Type -AssemblyName System.Drawing
$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"
try { $config = Get-Content $archivoConfig -Raw | ConvertFrom-Json } catch { Write-Output "ERROR"; return }
$carpeta = if ($config.servidor.carpeta_instancia) { $config.servidor.carpeta_instancia } else { "Instancia" }
$inst = Join-Path $rutaBase $carpeta
if (-not (Test-Path $inst)) { New-Item $inst -ItemType Directory -Force | Out-Null }

$size = 64
$bmp = New-Object System.Drawing.Bitmap($size, $size)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = "AntiAlias"
$g.Clear([System.Drawing.Color]::FromArgb(20, 22, 28))
$c = $size / 2.0
$R = $size * 0.36
$rc = $size * 0.20
$azul = [System.Drawing.Color]::FromArgb(91, 140, 255)
$verde = [System.Drawing.Color]::FromArgb(125, 194, 66)
$naranja = [System.Drawing.Color]::FromArgb(255, 170, 60)
$ang = @(0, 60, 120, 180, 240, 300)
$outer = @(); $inner = @()
foreach ($a in $ang) { $r = [math]::PI * $a / 180; $outer += , @($c + $R * [math]::Cos($r), $c + $R * [math]::Sin($r)); $inner += , @($c + $rc * [math]::Cos($r), $c + $rc * [math]::Sin($r)) }
$ptsIn = $inner | ForEach-Object { New-Object System.Drawing.PointF([float]$_[0], [float]$_[1]) }
$g.FillPolygon((New-Object System.Drawing.SolidBrush($verde)), [System.Drawing.PointF[]]$ptsIn)
$ptsOut = $outer | ForEach-Object { New-Object System.Drawing.PointF([float]$_[0], [float]$_[1]) }
$pen = New-Object System.Drawing.Pen($azul, [float]($size * 0.07)); $pen.LineJoin = "Round"
$g.DrawPolygon($pen, [System.Drawing.PointF[]]$ptsOut)
$nr = $size * 0.075
for ($i = 0; $i -lt 6; $i++) { $col = if ($i -eq 5) { $naranja } else { $azul }; $g.FillEllipse((New-Object System.Drawing.SolidBrush($col)), [float]($outer[$i][0] - $nr), [float]($outer[$i][1] - $nr), [float]($nr * 2), [float]($nr * 2)) }
$g.Dispose()
$bmp.Save((Join-Path $inst "server-icon.png"), [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "OK"
