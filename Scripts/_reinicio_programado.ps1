# =====================================================
#  _reinicio_programado.ps1
#  Ejecutado por tarea programada (ej: 5 AM diario).
#  Solo reinicia si el server esta activo en este PC.
# =====================================================

$rutaBase         = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaScripts      = Join-Path $rutaBase "Scripts"
$rutaEstado       = Join-Path $rutaBase "Estado"
$archivoLockLocal = Join-Path $rutaEstado "servidor.lock"

# Solo reiniciar si hay un servidor activo localmente
$lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
if ([string]::IsNullOrWhiteSpace($lockContenido)) {
    exit 0
}
$lockData = $lockContenido | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $lockData) { exit 0 }
$proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
if (-not $proc) { exit 0 }

# Ejecutar el flujo de reinicio rapido
& PowerShell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $rutaScripts "_nucleo.ps1") -Accion "reiniciar"
