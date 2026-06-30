# =====================================================
#  _nube.ps1
#  Modulo de comunicacion con Backblaze B2 via Rclone.
#  Toda interaccion con la nube pasa por aqui.
#  NO EDITAR salvo para cambiar proveedor de nube.
# =====================================================

$rutaRclone = "C:\rclone\rclone.exe"

function Crear-LockNube {
    Escribir-Log "Creando lock en la nube..." "INFO"

    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $archivoLock = $config.nube.archivo_lock
    $estePC      = $config.identidad.este_pc
    $lockTmp     = Join-Path $env:TEMP "turno.lock"

    $lockData = @{
        ocupado_por = $estePC
        desde       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    } | ConvertTo-Json

    Guardar-TextoSinBOM -Ruta $lockTmp -Contenido $lockData

    $resultado = & $rutaRclone copyto $lockTmp "${remoto}:${bucket}/${archivoLock}" 2>&1
    Remove-Item $lockTmp -Force

    if ($LASTEXITCODE -eq 0) {
        Escribir-Log "Lock creado en nube. Turno tomado por $estePC." "OK"
        return $true
    } else {
        Escribir-Log "Error al crear lock en nube: $resultado" "ERROR"
        return $false
    }
}

function Eliminar-LockNube {
    Escribir-Log "Eliminando lock de la nube..." "INFO"

    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $archivoLock = $config.nube.archivo_lock

    $resultado = & $rutaRclone deletefile "${remoto}:${bucket}/${archivoLock}" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Escribir-Log "Lock eliminado de la nube. Turno liberado." "OK"
        return $true
    } else {
        # Si no existe el archivo, igual es exito (ya estaba libre)
        if ($resultado -match "not found|no such|404") {
            Escribir-Log "Lock ya no existia en nube (ya estaba libre)." "WARN"
            return $true
        }
        Escribir-Log "Error al eliminar lock de nube: $resultado" "ERROR"
        return $false
    }
}

function Subir-Mundo {
    Escribir-Log "Subiendo datos del servidor a Backblaze B2..." "INFO"

    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $carpetaNube = $config.nube.carpeta_mundo
    $ci = $config.servidor.carpeta_instancia
    if ($ci -and $ci -ne "Instancia") { $carpetaNube = "$($config.nube.carpeta_mundo)/$ci" }
    $reintentos  = $config.sincronizacion.reintentos

    # Carpetas importantes
    $carpetas = @("world", "plugins", "config") |
        ForEach-Object { Join-Path $rutaInstancia $_ } |
        Where-Object { Test-Path $_ }

    # Archivos sueltos importantes
    $archivosSueltos = @(
        "server.properties", "bukkit.yml", "spigot.yml", "purpur.yml",
        "ops.json", "whitelist.json", "banned-players.json", "banned-ips.json"
    )

    # Subir carpetas
    foreach ($carpeta in $carpetas) {
        $nombre = Split-Path $carpeta -Leaf
        Escribir-Log "Subiendo $nombre..." "INFO"

        $intento = 0
        $exito = $false
        while ($intento -lt $reintentos -and -not $exito) {
            $intento++
            if ($intento -gt 1) {
                Escribir-Log "Reintento $intento de $reintentos..." "WARN"
                Start-Sleep -Seconds 5
            }
            $resultado = & $rutaRclone sync $carpeta "${remoto}:${bucket}/${carpetaNube}/${nombre}" 2>&1
            if ($LASTEXITCODE -eq 0) { $exito = $true }
            else { Escribir-Log "Error subiendo $nombre (intento $intento): $resultado" "WARN" }
        }
        if (-not $exito) {
            Escribir-Log "Fallo al subir $nombre despues de $reintentos intentos." "ERROR"
            return $false
        }
    }

    # Subir archivos sueltos
    foreach ($archivo in $archivosSueltos) {
        $ruta = Join-Path $rutaInstancia $archivo
        if (Test-Path $ruta) {
            & $rutaRclone copyto $ruta "${remoto}:${bucket}/${carpetaNube}/${archivo}" 2>&1 | Out-Null
        }
    }

    $estado = Leer-Estado
    $estado.ultima_sincronizacion = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    Guardar-Estado $estado

    Escribir-Log "Datos del servidor subidos a B2 correctamente." "OK"
    return $true
}

function Descargar-Mundo {
    Escribir-Log "Descargando datos del servidor desde Backblaze B2..." "INFO"

    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $carpetaNube = $config.nube.carpeta_mundo
    $ci = $config.servidor.carpeta_instancia
    if ($ci -and $ci -ne "Instancia") { $carpetaNube = "$($config.nube.carpeta_mundo)/$ci" }
    $reintentos  = $config.sincronizacion.reintentos

    # Carpetas importantes
    $carpetas = @("world", "plugins", "config")

    foreach ($nombre in $carpetas) {
        $destinoLocal = Join-Path $rutaInstancia $nombre
        # Verificar si existe en nube
        $existe = & $rutaRclone lsd "${remoto}:${bucket}/${carpetaNube}/${nombre}" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Escribir-Log "$nombre no existe en la nube, omitiendo." "INFO"
            continue
        }

        Escribir-Log "Descargando $nombre..." "INFO"
        $intento = 0
        $exito = $false
        while ($intento -lt $reintentos -and -not $exito) {
            $intento++
            if ($intento -gt 1) {
                Escribir-Log "Reintento $intento de $reintentos..." "WARN"
                Start-Sleep -Seconds 5
            }
            $resultado = & $rutaRclone sync "${remoto}:${bucket}/${carpetaNube}/${nombre}" $destinoLocal 2>&1
            if ($LASTEXITCODE -eq 0) { $exito = $true }
            else { Escribir-Log "Error descargando $nombre (intento $intento): $resultado" "WARN" }
        }
        if (-not $exito) {
            Escribir-Log "Fallo al descargar $nombre despues de $reintentos intentos." "ERROR"
            return $false
        }
    }

    # Descargar archivos sueltos
    $archivosSueltos = @(
        "server.properties", "bukkit.yml", "spigot.yml", "purpur.yml",
        "ops.json", "whitelist.json", "banned-players.json", "banned-ips.json"
    )
    foreach ($archivo in $archivosSueltos) {
        $existe = & $rutaRclone lsf "${remoto}:${bucket}/${carpetaNube}/${archivo}" 2>&1
        if ($LASTEXITCODE -eq 0 -and $existe) {
            $destino = Join-Path $rutaInstancia $archivo
            & $rutaRclone copyto "${remoto}:${bucket}/${carpetaNube}/${archivo}" $destino 2>&1 | Out-Null
        }
    }

    $estado = Leer-Estado
    $estado.ultima_sincronizacion = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    Guardar-Estado $estado

    Escribir-Log "Datos del servidor descargados desde B2 correctamente." "OK"
    return $true
}

function Verificar-MundoEnNube {
    # Comprueba si ya existe un mundo subido en B2
    Escribir-Log "Verificando si hay mundo en la nube..." "INFO"

    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $carpetaNube = $config.nube.carpeta_mundo
    $ci = $config.servidor.carpeta_instancia
    if ($ci -and $ci -ne "Instancia") { $carpetaNube = "$($config.nube.carpeta_mundo)/$ci" }

    $resultado = & $rutaRclone lsd "${remoto}:${bucket}/${carpetaNube}" 2>&1

    if ($LASTEXITCODE -eq 0 -and $resultado) {
        Escribir-Log "Mundo encontrado en la nube." "OK"
        return $true
    } else {
        Escribir-Log "No hay mundo en la nube todavia." "INFO"
        return $false
    }
}
