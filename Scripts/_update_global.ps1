# =====================================================
#  _update_global.ps1
#  Canal CENTRAL de actualizaciones del PROGRAMA (Skeledex).
#  Lo controla el developer via GitHub Releases.
#  Compara la version local con la ultima release; si hay una
#  mas nueva, descarga el .zip, aplica los Scripts y deja el
#  .exe nuevo listo para el proximo arranque.
#  El mundo/turnos/backups NO pasan por aqui (eso es por grupo).
#  Salidas: OFF | SIN-REPO | SIN-CONEXION | AL-DIA:<v> |
#           SIN-ASSET | ACTUALIZADO:<v> | ERROR:<msg>
# =====================================================
$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaEstado        = Join-Path $rutaBase "Estado"
. "$PSScriptRoot\_config_path.ps1"
. "$PSScriptRoot\_registros.ps1"

function Es-VersionMayor {
    param([string]$Nueva, [string]$Actual)
    $n = ($Nueva -replace '[^0-9.]','').Split('.') | ForEach-Object { [int]($_ -as [int]) }
    $a = ($Actual -replace '[^0-9.]','').Split('.') | ForEach-Object { [int]($_ -as [int]) }
    for ($i=0; $i -lt [Math]::Max($n.Count,$a.Count); $i++) {
        $vn = if ($i -lt $n.Count) { $n[$i] } else { 0 }
        $va = if ($i -lt $a.Count) { $a[$i] } else { 0 }
        if ($vn -gt $va) { return $true }
        if ($vn -lt $va) { return $false }
    }
    return $false
}

try { $config = Get-Content $archivoConfig -Raw | ConvertFrom-Json } catch { Write-Output "ERROR:config"; return }

$au = $config.actualizaciones
if (-not $au -or -not $au.auto) { Write-Output "OFF"; return }
# Repositorio OFICIAL del desarrollador (canal unico de actualizaciones).
# Si la config trae uno, se respeta; si no, se usa este.
$repoOficial = "MasterXDXDX/Skeledex"
$repo = if ($au.repo) { $au.repo } else { $repoOficial }
if (-not $repo -or $repo -eq "MasterXDXDX/Skeledex") { Write-Output "SIN-REPO"; return }

$verActual = $config.identidad.version_sistema
try {
    $r = Invoke-WebRequest "https://api.github.com/repos/$repo/releases/latest" -UseBasicParsing -TimeoutSec 12 -Headers @{ 'User-Agent' = 'Skeledex' }
    $rel = $r.Content | ConvertFrom-Json
} catch { Write-Output "SIN-CONEXION"; return }

$verNueva = "$($rel.tag_name)" -replace '^v',''
if (-not (Es-VersionMayor $verNueva $verActual)) { Write-Output "AL-DIA:$verActual"; return }

# Buscar el asset .zip de la release (preferir el de Skeledex/Update)
$asset = $rel.assets | Where-Object { $_.name -match '(?i)(skeledex|update).*\.zip$' } | Select-Object -First 1
if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -like '*.zip' } | Select-Object -First 1 }
if (-not $asset) { Write-Output "SIN-ASSET"; return }

$zip = Join-Path $env:TEMP "skeledex_update.zip"
$tmp = Join-Path $env:TEMP "skeledex_update_x"
try {
    Invoke-WebRequest $asset.browser_download_url -OutFile $zip -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = 'Skeledex' }
} catch { Write-Output "ERROR:descarga"; return }
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
try { Expand-Archive $zip $tmp -Force } catch { Write-Output "ERROR:zip"; return }

# Aplicar Scripts (copy: nunca borra el mundo ni datos locales)
$srcScripts = Get-ChildItem $tmp -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Scripts' } | Select-Object -First 1
if ($srcScripts) {
    Copy-Item "$($srcScripts.FullName)\*" $rutaScripts -Recurse -Force
} else {
    # Si el zip trae los scripts en la raiz
    Get-ChildItem $tmp -Filter '*.ps1' -ErrorAction SilentlyContinue | Copy-Item -Destination $rutaScripts -Force
}

# Aplicar el .exe (queda como _nuevo y se aplica al proximo arranque)
$hayExe = $false
$srcExe = Get-ChildItem $tmp -Recurse -Filter 'ServidorTecnico.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($srcExe) { Copy-Item $srcExe.FullName (Join-Path $rutaBase "ServidorTecnico_nuevo.exe") -Force; $hayExe = $true }

# Actualizar version local + sello de chequeo
$config.identidad.version_sistema = $verNueva
if (-not $config.actualizaciones) { $config | Add-Member -NotePropertyName actualizaciones -NotePropertyValue ([pscustomobject]@{}) -Force }
$config.actualizaciones.ultimo_chequeo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
Guardar-TextoSinBOM -Ruta $archivoConfig -Contenido ($config | ConvertTo-Json -Depth 8)

Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Escribir-Log "Programa actualizado a v$verNueva desde GitHub ($repo)." "OK"
if ($hayExe) { Write-Output "ACTUALIZADO-EXE:$verNueva" } else { Write-Output "ACTUALIZADO:$verNueva" }
