# =====================================================
#  _autosave.ps1
#  Ejecuta /save-all cada 15 minutos mientras el server
#  esta activo. Proteccion contra perdida por crash.
#  Corre en segundo plano, lanzado al iniciar.
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$archivoLockLocal  = Join-Path $rutaEstado "servidor.lock"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_rcon.ps1"

# Configuracion (con valores por defecto si no existen)
if ($config.avanzado -and -not $config.avanzado.autosave_habilitado) { return }
$intervaloMin = if ($config.avanzado -and $config.avanzado.autosave_intervalo_min) { $config.avanzado.autosave_intervalo_min } else { 15 }
$intervalo = $intervaloMin * 60

while ($true) {
    Start-Sleep -Seconds $intervalo

    # Verificar que el server sigue vivo
    $lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($lockContenido)) { break }
    $lockData = $lockContenido | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $lockData) { break }
    $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
    if (-not $proc) { break }

    # save-all
    $resp = Enviar-RCON -Comando "save-all"
    if ($resp) {
        Escribir-Log "Auto-save ejecutado: $resp" "OK"
    } else {
        Escribir-Log "Auto-save: RCON no respondio." "WARN"
    }
}
