# =====================================================
#  _backup_diario.ps1
#  Ejecutado automaticamente por tarea programada.
#  Solo hace backup si el servidor esta activo.
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaInstancia     = Join-Path $rutaBase "Instancia"
$rutaBackups       = Join-Path $rutaBase "Backups"
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$archivoEstado     = Join-Path $rutaEstado "estado.json"
$archivoLockLocal  = Join-Path $rutaEstado "servidor.lock"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
if ($config.servidor.carpeta_instancia) { $rutaInstancia = Join-Path $rutaBase $config.servidor.carpeta_instancia }
$rutaBackups = Join-Path $rutaInstancia "Backups"

. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_backup.ps1"
. "$rutaScripts\_rcon.ps1"

function Leer-Estado {
    return Get-Content $archivoEstado -Raw | ConvertFrom-Json
}
function Guardar-Estado {
    param([object]$Estado)
    Guardar-TextoSinBOM -Ruta $archivoEstado -Contenido ($Estado | ConvertTo-Json -Depth 5)
}

# Solo hacer backup si hay mundo presente
$rutaMundo = Join-Path $rutaInstancia "world"
if (-not (Test-Path $rutaMundo)) {
    Escribir-Log "Backup diario omitido: no hay mundo local." "INFO"
    exit 0
}

# Si el servidor esta activo, hacer save-all antes del backup
$contenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
if (-not [string]::IsNullOrWhiteSpace($contenido)) {
    Escribir-Log "Servidor activo. Enviando /save-all antes del backup diario..." "INFO"
    $resp = Enviar-RCON -Comando "save-all"
    if ($resp) { Escribir-Log "save-all: $resp" "OK" }
    Start-Sleep -Seconds 5
}

Escribir-Log "Iniciando backup diario automatico..." "INFO"
$resultado = Crear-Backup -Tipo "Diario"
if ($resultado) {
    Escribir-Log "Backup diario completado." "OK"
} else {
    Escribir-Log "Backup diario FALLO." "ERROR"
}
