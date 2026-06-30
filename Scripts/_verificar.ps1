# =====================================================
#  _verificar.ps1
#  Modulo de verificaciones del sistema.
#  Comprueba condiciones antes de iniciar o apagar.
#  NO EDITAR salvo para agregar nuevas verificaciones.
# =====================================================

function Verificar-JavaInstalado {
    Escribir-Log "Verificando instalacion de Java..." "INFO"
    try {
        $version = & java -version 2>&1
        Escribir-Log "Java encontrado: $($version[0])" "OK"
        return $true
    } catch {
        Escribir-Log "Java no encontrado. Instala Java y agrega al PATH." "ERROR"
        return $false
    }
}

function Verificar-RcloneInstalado {
    Escribir-Log "Verificando instalacion de Rclone..." "INFO"
    $rutaRclone = "C:\rclone\rclone.exe"

    if (Test-Path $rutaRclone) {
        Escribir-Log "Rclone encontrado en: $rutaRclone" "OK"
        return $true
    } else {
        Escribir-Log "Rclone no encontrado en: $rutaRclone" "ERROR"
        return $false
    }
}

function Verificar-ConexionB2 {
    Escribir-Log "Verificando conexion con Backblaze B2..." "INFO"
    $rutaRclone = "C:\rclone\rclone.exe"
    $remoto     = $config.nube.rclone_remoto
    $bucket     = $config.nube.bucket

    try {
        $resultado = & $rutaRclone lsd "${remoto}:${bucket}" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Escribir-Log "Conexion con B2 exitosa." "OK"
            return $true
        } else {
            Escribir-Log "Error conectando con B2: $resultado" "ERROR"
            return $false
        }
    } catch {
        Escribir-Log "Error ejecutando rclone: $_" "ERROR"
        return $false
    }
}

function Verificar-LockLocal {
    # Retorna: "libre" o "ocupado"
    Escribir-Log "Verificando lock local..." "INFO"

    $contenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($contenido)) {
        Escribir-Log "Lock local: libre." "OK"
        return "libre"
    }

    try {
        $lockData = $contenido | ConvertFrom-Json
        $pidGuardado = $lockData.pid

        $proceso = Get-Process -Id $pidGuardado -ErrorAction SilentlyContinue
        if ($proceso) {
            Escribir-Log "Lock local: servidor activo con PID $pidGuardado." "WARN"
            return "ocupado"
        } else {
            Escribir-Log "Lock local fantasma detectado (PID $pidGuardado no existe). Limpiando..." "WARN"
            Clear-Content $archivoLockLocal
            return "libre"
        }
    } catch {
        Escribir-Log "Lock local corrupto. Limpiando..." "WARN"
        Clear-Content $archivoLockLocal
        return "libre"
    }
}

function Verificar-LockNube {
    # Retorna: "libre", "ocupado_por_mi", "ocupado_por_otro"
    Escribir-Log "Verificando lock en la nube..." "INFO"

    $rutaRclone  = "C:\rclone\rclone.exe"
    $remoto      = $config.nube.rclone_remoto
    $bucket      = $config.nube.bucket
    $archivoLock = $config.nube.archivo_lock
    $estePC      = $config.identidad.este_pc
    $lockTmp     = Join-Path $env:TEMP "turno.lock"

    # Primero verificar si el archivo existe en B2 (lsf no falla silenciosamente)
    $listar = & $rutaRclone lsf "${remoto}:${bucket}/${archivoLock}" 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($listar)) {
        Escribir-Log "Lock en nube: libre. Nadie tiene el turno." "OK"
        return "libre"
    }

    # El archivo existe, descargarlo
    if (Test-Path $lockTmp) { Remove-Item $lockTmp -Force }
    $resultado = & $rutaRclone copyto "${remoto}:${bucket}/${archivoLock}" $lockTmp 2>&1

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $lockTmp)) {
        Escribir-Log "Error al descargar lock de nube: $resultado" "ERROR"
        throw "No se pudo verificar el estado de la nube."
    }

    $contenido = Get-Content $lockTmp -Raw -ErrorAction SilentlyContinue
    Remove-Item $lockTmp -Force

    if ([string]::IsNullOrWhiteSpace($contenido)) {
        Escribir-Log "Lock en nube existe pero esta vacio. Tratando como libre." "WARN"
        return "libre"
    }

    try {
        $lockData = $contenido | ConvertFrom-Json

        if ($lockData.ocupado_por -eq $estePC) {
            Escribir-Log "Lock en nube: ocupado por este PC ($estePC). Sesion anterior no cerrada limpiamente." "WARN"
            return "ocupado_por_mi"
        } else {
            Escribir-Log "Lock en nube: ocupado por $($lockData.ocupado_por) desde $($lockData.desde)." "WARN"
            return "ocupado_por_otro"
        }
    } catch {
        Escribir-Log "Lock en nube corrupto o ilegible: $_" "ERROR"
        throw "Lock en nube en estado invalido."
    }
}

function Verificar-IntegridadMundo {
    Escribir-Log "Verificando integridad del mundo..." "INFO"

    $rutaMundo = Join-Path $rutaInstancia "world"

    if (-not (Test-Path $rutaMundo)) {
        Escribir-Log "Carpeta world no encontrada en Instancia\." "ERROR"
        return $false
    }

    # ANTI-CORRUPCION: verificar que level.dat exista y no este vacio
    $levelDat = Join-Path $rutaMundo "level.dat"
    if (Test-Path $levelDat) {
        $tam = (Get-Item $levelDat).Length
        if ($tam -lt 1) {
            Escribir-Log "ADVERTENCIA: level.dat esta vacio (posible corrupcion)." "WARN"
            $levelOld = Join-Path $rutaMundo "level.dat_old"
            if (Test-Path $levelOld -and (Get-Item $levelOld).Length -gt 0) {
                Escribir-Log "Restaurando level.dat desde level.dat_old..." "WARN"
                Copy-Item $levelOld $levelDat -Force
            }
        } else {
            Escribir-Log "level.dat OK ($tam bytes)." "OK"
        }
    } else {
        Escribir-Log "ADVERTENCIA: level.dat no existe en el mundo." "WARN"
    }

    $hashActual = Get-ChildItem $rutaMundo -Recurse -File |
        Sort-Object FullName |
        ForEach-Object { Get-FileHash $_.FullName -Algorithm MD5 } |
        ForEach-Object { $_.Hash } |
        Out-String

    $hashFinal = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new(
        [System.Text.Encoding]::UTF8.GetBytes($hashActual)
    )) -Algorithm MD5).Hash

    $estado = Leer-Estado
    $hashAnterior = $estado.version_mundo_local

    if ([string]::IsNullOrWhiteSpace($hashAnterior)) {
        Escribir-Log "Primera vez - guardando hash del mundo: $hashFinal" "INFO"
        $estado.version_mundo_local = $hashFinal
        Guardar-Estado $estado
        return $true
    }

    Escribir-Log "Hash del mundo actualizado." "INFO"
    $estado.version_mundo_local = $hashFinal
    Guardar-Estado $estado
    return $true
}

function Ejecutar-VerificacionesInicio {
    Escribir-Log "Iniciando verificaciones previas..." "SISTEMA"
    $errores = 0

    if (-not (Verificar-JavaInstalado))   { $errores++ }
    if (-not ($config.local -eq $true)) {
        if (-not (Verificar-RcloneInstalado)) { $errores++ }
        if (-not (Verificar-ConexionB2))      { $errores++ }
    } else {
        Escribir-Log "Modo local: se omiten verificaciones de nube." "INFO"
    }
    if (-not (Verificar-EspacioDisco))    { $errores++ }

    if ($errores -gt 0) {
        Escribir-Log "$errores verificacion(es) fallaron. No se puede iniciar." "ERROR"
        return $false
    }

    Escribir-Log "Todas las verificaciones pasaron." "OK"
    return $true
}

function Verificar-EspacioDisco {
    Escribir-Log "Verificando espacio en disco..." "INFO"
    $drive = (Get-Item $rutaBase).PSDrive.Name
    $disco = Get-PSDrive $drive
    $libresGB = [math]::Round($disco.Free / 1GB, 1)

    if ($libresGB -lt 2) {
        Escribir-Log "Espacio insuficiente: solo $libresGB GB libres. Se necesitan al menos 2 GB." "ERROR"
        return $false
    }

    Escribir-Log "Espacio en disco: $libresGB GB libres." "OK"
    return $true
}
