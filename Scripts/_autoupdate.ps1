# =====================================================
#  _autoupdate.ps1
#  Auto-actualiza scripts y .bat desde B2.
#  Se ejecuta al abrir el Panel o antes de Iniciar.
# =====================================================

$rutaRclone = "C:\rclone\rclone.exe"

function Ejecutar-AutoUpdate {
    # El owner no se auto-actualiza (el es quien publica los cambios)
    if ($config.identidad.rol -eq "owner") { return }

    $remoto = $config.nube.rclone_remoto
    $bucket = $config.nube.bucket
    $carpetaUpdate = "sistema-update"

    Escribir-Log "Verificando actualizaciones..." "INFO"

    # Verificar si existe la carpeta de updates en B2
    $existe = & $rutaRclone lsd "${remoto}:${bucket}/${carpetaUpdate}" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Escribir-Log "No hay actualizaciones disponibles." "INFO"
        return
    }

    # Descargar Scripts/ (copy = solo agrega/actualiza, NUNCA borra archivos locales)
    $resultado = & $rutaRclone copy "${remoto}:${bucket}/${carpetaUpdate}/Scripts" (Join-Path $rutaBase "Scripts") 2>&1
    if ($LASTEXITCODE -ne 0) {
        Escribir-Log "Error descargando scripts: $resultado" "WARN"
        return
    }

    # Descargar .bat files
    $bats = & $rutaRclone lsf "${remoto}:${bucket}/${carpetaUpdate}" --include "*.bat" 2>&1
    if ($LASTEXITCODE -eq 0 -and $bats) {
        foreach ($bat in ($bats -split "`n" | Where-Object { $_ })) {
            $bat = $bat.Trim()
            & $rutaRclone copyto "${remoto}:${bucket}/${carpetaUpdate}/${bat}" (Join-Path $rutaBase $bat) 2>&1 | Out-Null
        }
    }

    # Descargar el .exe del panel (a archivo .nuevo; se aplica en el proximo arranque)
    $exeNuevo = Join-Path $rutaBase "ServidorTecnico_nuevo.exe"
    & $rutaRclone copyto "${remoto}:${bucket}/${carpetaUpdate}/ServidorTecnico.exe" $exeNuevo 2>&1 | Out-Null
    if (Test-Path $exeNuevo) {
        $exeActual = Join-Path $rutaBase "ServidorTecnico.exe"
        # Si el exe actual no esta en uso, reemplazarlo
        try {
            if (Test-Path $exeActual) { Remove-Item $exeActual -Force -ErrorAction Stop }
            Move-Item $exeNuevo $exeActual -Force
            Escribir-Log "Panel actualizado." "OK"
        } catch {
            Escribir-Log "Panel nuevo descargado (se aplicara al cerrar el panel actual)." "INFO"
        }
    }

    Escribir-Log "Sistema actualizado." "OK"
}

function Publicar-Update {
    # Solo el owner puede publicar (protege contra sobrescribir desde otro PC)
    if ($config.identidad.rol -ne "owner") {
        Escribir-Log "Solo el owner puede publicar actualizaciones." "WARN"
        return
    }
    $remoto = $config.nube.rclone_remoto
    $bucket = $config.nube.bucket
    $carpetaUpdate = "sistema-update"

    Escribir-Log "Publicando actualizacion del sistema..." "INFO"

    # Subir Scripts/
    & $rutaRclone sync (Join-Path $rutaBase "Scripts") "${remoto}:${bucket}/${carpetaUpdate}/Scripts" 2>&1 | Out-Null

    # Subir .bat files
    $bats = Get-ChildItem $rutaBase -Filter "*.bat"
    foreach ($bat in $bats) {
        & $rutaRclone copyto $bat.FullName "${remoto}:${bucket}/${carpetaUpdate}/$($bat.Name)" 2>&1 | Out-Null
    }

    # Subir el .exe del panel
    $exe = Join-Path $rutaBase "ServidorTecnico.exe"
    if (Test-Path $exe) {
        Escribir-Log "Subiendo panel (.exe)..." "INFO"
        & $rutaRclone copyto $exe "${remoto}:${bucket}/${carpetaUpdate}/ServidorTecnico.exe" 2>&1 | Out-Null
    }

    Escribir-Log "Actualizacion publicada. Los demas PCs la recibiran al iniciar." "OK"
}
