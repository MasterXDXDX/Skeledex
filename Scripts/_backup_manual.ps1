# =====================================================
#  _backup_manual.ps1
#  Crea un backup manual (tipo "Manual") del mundo actual.
#  Salida: OK | ERROR
# =====================================================
$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
. "$PSScriptRoot\_config_path.ps1"
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_backup.ps1"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
$carpeta = if ($config.servidor.carpeta_instancia) { $config.servidor.carpeta_instancia } else { "Instancia" }
$rutaInstancia = Join-Path $rutaBase $carpeta
$rutaBackups   = Join-Path $rutaInstancia "Backups"

if (Crear-Backup -Tipo "Manual") { Write-Output "OK" } else { Write-Output "ERROR" }
