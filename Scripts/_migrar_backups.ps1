# =====================================================
#  _migrar_backups.ps1
#  Mueve los backups antiguos (base\Backups) a la carpeta
#  de la instancia activa (instancia\Backups). Idempotente.
#  Salida: MIGRADOS:<n> | NADA
# =====================================================
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"
try { $config = Get-Content $archivoConfig -Raw | ConvertFrom-Json } catch { Write-Output "NADA"; return }
$carp = if ($config.servidor.carpeta_instancia) { $config.servidor.carpeta_instancia } else { "Instancia" }
$inst = Join-Path $rutaBase $carp
$nuevo = Join-Path $inst "Backups"
$old = Join-Path $rutaBase "Backups"
if ((Test-Path $old) -and ((Resolve-Path $old).Path -ne (Resolve-Path -ErrorAction SilentlyContinue $nuevo).Path)) {
    $movidos = 0
    foreach ($t in (Get-ChildItem $old -Directory -ErrorAction SilentlyContinue)) {
        $destT = Join-Path $nuevo $t.Name
        if (-not (Test-Path $destT)) { New-Item $destT -ItemType Directory -Force | Out-Null }
        foreach ($z in (Get-ChildItem $t.FullName -Filter *.zip -ErrorAction SilentlyContinue)) {
            $d = Join-Path $destT $z.Name
            if (-not (Test-Path $d)) { Move-Item $z.FullName $d -Force; $movidos++ }
        }
    }
    Write-Output "MIGRADOS:$movidos"
} else { Write-Output "NADA" }
