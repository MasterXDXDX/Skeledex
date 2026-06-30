# =====================================================
#  _config_path.ps1
#  Resuelve la ruta CANONICA de config.json.
#  La config vive FUERA de la carpeta del programa
#  (%APPDATA%\Skeledex) para que la carpeta sea portable
#  y cada PC tenga su propia identidad aunque compartan carpeta.
#  Migra automaticamente una config local antigua.
#  Requiere que $rutaConfiguracion ya este definida.
#  Define: $archivoConfig
# =====================================================
$rutaConfigUsuario   = Join-Path $env:APPDATA "Skeledex"
if (-not (Test-Path $rutaConfigUsuario)) { New-Item $rutaConfigUsuario -ItemType Directory -Force | Out-Null }
$archivoConfigUsuario = Join-Path $rutaConfigUsuario "config.json"
$archivoConfigLocal   = Join-Path $rutaConfiguracion "config.json"

# Migracion: si no existe la de usuario pero si una local, copiarla
if ((-not (Test-Path $archivoConfigUsuario)) -and (Test-Path $archivoConfigLocal)) {
    try { Copy-Item $archivoConfigLocal $archivoConfigUsuario -Force } catch {}
}

if (Test-Path $archivoConfigUsuario) {
    $archivoConfig = $archivoConfigUsuario
} else {
    $archivoConfig = $archivoConfigLocal
}
