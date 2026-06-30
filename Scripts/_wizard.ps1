# =====================================================
#  _wizard.ps1
#  Asistente de configuracion inicial.
#  Pregunta lo esencial y genera config.json.
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$rutaScripts       = Join-Path $rutaBase "Scripts"
. "$rutaScripts\_registros.ps1"

Write-Host ""
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host "   Asistente de Configuracion - ServidorTecnico" -ForegroundColor Cyan
Write-Host "  ===========================================" -ForegroundColor Cyan
Write-Host ""

# Cargar config existente o base
if (Test-Path $archivoConfig) {
    $config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
} else {
    Write-Host "No se encontro config.json. Abortando." -ForegroundColor Red
    return
}

function Preguntar($texto, $actual) {
    $r = Read-Host "$texto [$actual]"
    if ([string]::IsNullOrWhiteSpace($r)) { return $actual }
    return $r
}

Write-Host "Deja en blanco para mantener el valor actual." -ForegroundColor Gray
Write-Host ""

$config.identidad.nombre_usuario = Preguntar "Tu nombre (ej: Master)" $config.identidad.nombre_usuario
$config.identidad.este_pc        = Preguntar "Nombre de ESTE PC (ej: Colombia)" $config.identidad.este_pc
$config.identidad.otro_pc        = Preguntar "Nombre del OTRO PC (ej: Espana)" $config.identidad.otro_pc

Write-Host ""
Write-Host "Rol de este PC:" -ForegroundColor Yellow
Write-Host "  admin    = control total, publica actualizaciones"
Write-Host "  operador = control total del panel"
Write-Host "  miembro  = solo prender/apagar, sin acceso a archivos"
$config.identidad.rol = Preguntar "Rol" $config.identidad.rol

Write-Host ""
$config.servidor.jar_nombre = Preguntar "Nombre del .jar (ej: purpur.jar)" $config.servidor.jar_nombre
$ram = Preguntar "RAM en GB (ej: 4)" "4"
$config.servidor.java_args = "-Xms2G -Xmx${ram}G -XX:+UseG1GC"

Write-Host ""
$pl = Preguntar "Direccion de Playit (ej: algo.playit.gg, o vacio)" $config.red.playit_direccion
$config.red.playit_direccion = $pl
if ($pl) { $config.red.playit_habilitado = $true }

# Guardar sin BOM
Guardar-TextoSinBOM -Ruta $archivoConfig -Contenido ($config | ConvertTo-Json -Depth 5)

Write-Host ""
Write-Host "  Configuracion guardada!" -ForegroundColor Green
Write-Host "  Ya puedes abrir el Panel." -ForegroundColor Green
Write-Host ""
