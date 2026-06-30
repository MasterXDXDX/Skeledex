# =====================================================
#  _backup.ps1
#  Modulo de gestion de copias de seguridad.
#  Maneja todos los niveles de backup del sistema.
#  NO EDITAR salvo para cambiar politicas de retencion.
# =====================================================

function Crear-Backup {
    param(
        [ValidateSet("AntesDeIniciar","DespuesDeApagar","Diario","Emergencia","Manual")]
        [string]$Tipo
    )

    Escribir-Log "Creando backup tipo: $Tipo..." "INFO"

    $timestamp   = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $nombreZip   = "${timestamp}_${Tipo}.zip"
    $carpetaDest = Join-Path $rutaBackups $Tipo
    $rutaZip     = Join-Path $carpetaDest $nombreZip

    # Asegurar que la carpeta destino existe
    if (-not (Test-Path $carpetaDest)) { New-Item -ItemType Directory -Path $carpetaDest -Force | Out-Null }

    # Carpetas del mundo a incluir en el backup
    $carpetasABackup = @("world", "world_nether", "world_the_end") |
        ForEach-Object { Join-Path $rutaInstancia $_ } |
        Where-Object { Test-Path $_ }

    if ($carpetasABackup.Count -eq 0) {
        Escribir-Log "No se encontraron carpetas de mundo para hacer backup." "ERROR"
        return $false
    }

    try {
        # Comprimir usando .NET (sin dependencias externas)
        Add-Type -Assembly System.IO.Compression.FileSystem

        $archivoZip = [System.IO.Compression.ZipFile]::Open($rutaZip, 'Create')

        foreach ($carpeta in $carpetasABackup) {
            $nombreBase = Split-Path $carpeta -Leaf
            $archivos = Get-ChildItem $carpeta -Recurse -File

            foreach ($archivo in $archivos) {
                $rutaRelativa = $nombreBase + "\" + $archivo.FullName.Substring($carpeta.Length).TrimStart("\")
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archivoZip,
                    $archivo.FullName,
                    $rutaRelativa,
                    [System.IO.Compression.CompressionLevel]::Optimal
                ) | Out-Null
            }
        }

        $archivoZip.Dispose()

        $tamano = [math]::Round((Get-Item $rutaZip).Length / 1MB, 2)
        Escribir-Log "Backup creado: $nombreZip ($tamano MB)" "OK"

        # Rotar backups viejos
        $maximos = switch ($Tipo) {
            "AntesDeIniciar"  { $config.backups.max_antes_de_iniciar }
            "DespuesDeApagar" { $config.backups.max_despues_de_apagar }
            "Diario"          { $config.backups.max_diarios }
            "Emergencia"      { 10 }
        }

        Rotar-Backups -Carpeta $carpetaDest -Maximo $maximos

        # Actualizar estado
        $estado = Leer-Estado
        $estado.ultimo_backup = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado

        return $true

    } catch {
        Escribir-Log "Error creando backup: $_" "ERROR"
        if (Test-Path $rutaZip) { Remove-Item $rutaZip -Force }
        return $false
    }
}

function Rotar-Backups {
    param(
        [string]$Carpeta,
        [int]$Maximo
    )

    $backups = Get-ChildItem $Carpeta -Filter "*.zip" |
        Sort-Object CreationTime -Descending

    if ($backups.Count -le $Maximo) { return }

    $aMovera = $backups | Select-Object -Skip $Maximo
    $papelera = Join-Path $rutaBackups "Papelera"

    foreach ($backup in $aMovera) {
        $destino = Join-Path $papelera $backup.Name
        Move-Item $backup.FullName $destino -Force
        Escribir-Log "Backup antiguo movido a Papelera: $($backup.Name)" "INFO"
    }

    Limpiar-Papelera
}

function Limpiar-Papelera {
    $papelera = Join-Path $rutaBackups "Papelera"
    $maxPapelera = $config.backups.max_papelera

    $archivos = Get-ChildItem $papelera -Filter "*.zip" |
        Sort-Object CreationTime -Descending

    if ($archivos.Count -le $maxPapelera) { return }

    $aEliminar = $archivos | Select-Object -Skip $maxPapelera

    foreach ($archivo in $aEliminar) {
        Remove-Item $archivo.FullName -Force
        Escribir-Log "Backup eliminado definitivamente de Papelera: $($archivo.Name)" "INFO"
    }
}

function Listar-Backups {
    $tipos = @("AntesDeIniciar", "DespuesDeApagar", "Diario", "Emergencia", "Manual")
    $todos = @()

    foreach ($tipo in $tipos) {
        $carpeta = Join-Path $rutaBackups $tipo
        $archivos = Get-ChildItem $carpeta -Filter "*.zip" -ErrorAction SilentlyContinue |
            Sort-Object CreationTime -Descending

        foreach ($archivo in $archivos) {
            $todos += [PSCustomObject]@{
                Tipo     = $tipo
                Nombre   = $archivo.Name
                Ruta     = $archivo.FullName
                Fecha    = $archivo.CreationTime
                TamanoMB = [math]::Round($archivo.Length / 1MB, 2)
            }
        }
    }

    return $todos | Sort-Object Fecha -Descending
}

function Restaurar-Backup {
    param([string]$RutaZip)

    Escribir-Log "Iniciando restauracion desde: $RutaZip" "WARN"

    if (-not (Test-Path $RutaZip)) {
        Escribir-Log "Archivo de backup no encontrado: $RutaZip" "ERROR"
        return $false
    }

    # Crear backup de emergencia del estado actual antes de restaurar
    Escribir-Log "Creando backup de emergencia del estado actual..." "INFO"
    Crear-Backup -Tipo "Emergencia"

    # Eliminar mundos actuales moviendolos a Papelera primero
    $carpetasAEliminar = @("world", "world_nether", "world_the_end") |
        ForEach-Object { Join-Path $rutaInstancia $_ } |
        Where-Object { Test-Path $_ }

    $papelera = Join-Path $rutaBackups "Papelera"
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

    foreach ($carpeta in $carpetasAEliminar) {
        $nombreBase = Split-Path $carpeta -Leaf
        $destinoPapelera = Join-Path $papelera "${timestamp}_mundo_reemplazado_${nombreBase}"
        Move-Item $carpeta $destinoPapelera -Force
        Escribir-Log "Mundo actual movido a Papelera: $nombreBase" "INFO"
    }

    # Descomprimir backup
    try {
        Add-Type -Assembly System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($RutaZip, $rutaInstancia)
        Escribir-Log "Backup restaurado correctamente." "OK"
        return $true
    } catch {
        Escribir-Log "Error al descomprimir backup: $_" "ERROR"
        return $false
    }
}
