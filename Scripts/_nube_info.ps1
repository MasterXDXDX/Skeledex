# =====================================================
#  _nube_info.ps1
#  Devuelve el uso de la nube en JSON (cualquier proveedor rclone).
#  { ok, usado_gb, limite_gb, porcentaje, archivos, soporta_cuota, total_gb }
# =====================================================
$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)

$rclone = "C:\rclone\rclone.exe"
if (-not (Test-Path $rclone)) { $rclone = "rclone" }

try {
    $config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
} catch {
    Write-Output '{"ok":false,"error":"config"}'; return
}

$remoto  = $config.nube.rclone_remoto
$bucket  = $config.nube.bucket
$limite  = if ($config.nube.limite_gb) { [double]$config.nube.limite_gb } else { 0 }

$usadoGb = 0.0; $archivos = 0; $soportaCuota = $false; $totalGb = 0.0

# 1) Tamano usado (funciona en todos los proveedores)
try {
    $sizeJson = & $rclone size "${remoto}:${bucket}" --json 2>$null
    if ($LASTEXITCODE -eq 0 -and $sizeJson) {
        $s = $sizeJson | ConvertFrom-Json
        $usadoGb  = [math]::Round($s.bytes / 1GB, 2)
        $archivos = $s.count
    } else {
        Write-Output '{"ok":false,"error":"size"}'; return
    }
} catch {
    Write-Output '{"ok":false,"error":"rclone"}'; return
}

# 2) Cuota total (solo Drive/Dropbox/OneDrive la reportan via about)
try {
    $aboutJson = & $rclone about "${remoto}:" --json 2>$null
    if ($LASTEXITCODE -eq 0 -and $aboutJson) {
        $a = $aboutJson | ConvertFrom-Json
        if ($a.total -and $a.total -gt 0) {
            $totalGb = [math]::Round($a.total / 1GB, 2)
            $soportaCuota = $true
            if ($a.used) { $usadoGb = [math]::Round($a.used / 1GB, 2) }
        }
    }
} catch {}

# Calcular porcentaje: preferir cuota real; si no, usar limite configurado
$base = if ($soportaCuota) { $totalGb } else { $limite }
$porc = if ($base -gt 0) { [math]::Round(($usadoGb / $base) * 100, 1) } else { 0 }

$out = @{
    ok           = $true
    usado_gb     = $usadoGb
    limite_gb    = $limite
    total_gb     = $totalGb
    porcentaje   = $porc
    archivos     = $archivos
    soporta_cuota = $soportaCuota
} | ConvertTo-Json -Compress
Write-Output $out
