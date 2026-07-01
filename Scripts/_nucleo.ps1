# =====================================================
#  _nucleo.ps1
#  Orquestador principal del sistema.
#  Es invocado por todos los .bat
#  Coordina el resto de modulos.
#  NO EDITAR salvo para cambiar flujos principales.
# =====================================================

param(
    [ValidateSet("iniciar","apagar","emergencia","restaurar","reiniciar")]
    [string]$Accion = "iniciar",
    [string]$Backup = ""
)

# --------------------------------------------------
# RUTAS ABSOLUTAS (calculadas desde ubicacion del script)
# --------------------------------------------------
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

# --------------------------------------------------
# CARGAR CONFIGURACION
# --------------------------------------------------
$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json

# Multi-instancia: usar la carpeta configurada (por defecto "Instancia")
if ($config.servidor.carpeta_instancia) {
    $rutaInstancia = Join-Path $rutaBase $config.servidor.carpeta_instancia
}
# Backups por instancia (cada instancia guarda sus propias copias)
$rutaBackups = Join-Path $rutaInstancia "Backups"

# --------------------------------------------------
# CARGAR MODULOS
# --------------------------------------------------
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_verificar.ps1"
. "$rutaScripts\_backup.ps1"
. "$rutaScripts\_nube.ps1"
. "$rutaScripts\_rcon.ps1"
. "$rutaScripts\_discord.ps1"
. "$rutaScripts\_autoupdate.ps1"
. "$rutaScripts\_duckdns.ps1"

# --------------------------------------------------
# FUNCIONES DE ESTADO LOCAL
# --------------------------------------------------
function Leer-Estado {
    return Get-Content $archivoEstado -Raw | ConvertFrom-Json
}

function Guardar-Estado {
    param([object]$Estado)
    Guardar-TextoSinBOM -Ruta $archivoEstado -Contenido ($Estado | ConvertTo-Json -Depth 5)
}

# --------------------------------------------------
# FLUJO: INICIAR
# --------------------------------------------------
function Flujo-Iniciar {
    Escribir-Separador "INICIANDO SERVIDOR"
    Escribir-Log "PC: $($config.identidad.este_pc)" "INFO"

    # Limpiar archivos residuales
    $residuales = @("stdin.pipe") | ForEach-Object { Join-Path $rutaEstado $_ }
    $residuales | Where-Object { Test-Path $_ } | ForEach-Object { Remove-Item $_ -Force }
    # Limpiar bandera de apagado (nuevo arranque = el watchdog vuelve a vigilar crashes)
    Remove-Item (Join-Path $rutaEstado "apagando.flag") -Force -ErrorAction SilentlyContinue

    # Auto-actualizar el programa: canal central (GitHub) + respaldo por grupo
    try { & "$rutaScripts\_update_global.ps1" | Out-Null } catch { Escribir-Log "Update global fallo (no critico): $_" "WARN" }
    try { Ejecutar-AutoUpdate } catch { Escribir-Log "AutoUpdate grupo fallo (no critico): $_" "WARN" }

    try {
        # PASO 1: Verificaciones de herramientas
        if (-not (Ejecutar-VerificacionesInicio)) {
            Escribir-Log "Abortando inicio por errores en verificaciones." "ERROR"
            return
        }

        # PASO 2: Verificar lock local
        $lockLocal = Verificar-LockLocal
        if ($lockLocal -eq "ocupado") {
            Escribir-Log "El servidor ya esta corriendo en este PC!" "ERROR"
            Escribir-Log "Usa el boton Apagar en el Panel para detenerlo." "INFO"
            return
        }

        # PASO 3: Verificar lock en nube
        $esLocal = ($config.local -eq $true)
        $lockNube = if ($esLocal) { "libre" } else { Verificar-LockNube }
        if ($lockNube -eq "ocupado_por_otro") {
            Escribir-Log "El servidor lo esta usando $($config.identidad.otro_pc) ahora mismo." "WARN"
            Write-Host ""
            Write-Host "  Quieres tomar el control del servidor?" -ForegroundColor Yellow
            Write-Host "  Esto apagara el servidor en el otro PC remotamente." -ForegroundColor Yellow
            Write-Host ""
            $confirmar = Read-Host "  Escribir SI para tomar el control"
            if ($confirmar -ne "SI") {
                Escribir-Log "Inicio cancelado." "INFO"
                return
            }
            Escribir-Log "Tomando control del servidor..." "WARN"
            Eliminar-LockNube
            # Esperar a que el otro PC detecte que perdio el lock
            Start-Sleep -Seconds 5
        }
        if ($lockNube -eq "ocupado_por_mi") {
            Escribir-Log "Sesion anterior no cerrada correctamente. Limpiando lock..." "WARN"
            Eliminar-LockNube
        }

        # PASO 4: Descargar mundo desde nube (si existe)
        $hayMundoEnNube = if ($esLocal) { $false } else { Verificar-MundoEnNube }
        if ($hayMundoEnNube) {
            Escribir-Log "Descargando mundo actualizado desde la nube..." "INFO"
            if (-not (Descargar-Mundo)) {
                Escribir-Log "Error al descargar el mundo. Abortando." "ERROR"
                return
            }
        } else {
            Escribir-Log "No hay mundo en la nube. Usando mundo local (primera vez)." "WARN"
        }

        # PASO 5: Verificar integridad
        Verificar-IntegridadMundo

        # PASO 5.5: Si es miembro, ocultar carpeta del mundo (anti-trampa casual)
        if ($config.identidad.rol -eq "miembro" -and (-not $config.avanzado -or $config.avanzado.ocultar_carpeta_miembros)) {
            $wp = Join-Path $rutaInstancia "world"
            if (Test-Path $wp) {
                try { (Get-Item $wp -Force).Attributes = "Hidden" } catch {}
            }
        }

        # PASO 6: Backup antes de iniciar
        Escribir-Log "Creando backup de seguridad antes de iniciar..." "INFO"
        if (-not (Crear-Backup -Tipo "AntesDeIniciar")) {
            Escribir-Log "Error al crear backup. Abortando por seguridad." "ERROR"
            return
        }

        # PASO 7: Tomar turno en la nube
        if (-not $esLocal) {
            if (-not (Crear-LockNube)) {
                Escribir-Log "Error al tomar turno en la nube. Abortando." "ERROR"
                return
            }
        } else {
            Escribir-Log "Modo local: sin nube ni turnos." "INFO"
        }

        # PASO 8: Iniciar Paper
        Escribir-Log "Iniciando servidor Paper..." "INFO"
        $jarPath  = Join-Path $rutaInstancia $config.servidor.jar_nombre
        # Sanear RAM: si -Xms es mayor que -Xmx la JVM no arranca (consola queda vacia)
        $argsStr = $config.servidor.java_args
        $mXms = [regex]::Match($argsStr, '-Xms(\d+)G'); $mXmx = [regex]::Match($argsStr, '-Xmx(\d+)G')
        if ($mXms.Success -and $mXmx.Success) {
            $vXms = [int]$mXms.Groups[1].Value; $vXmx = [int]$mXmx.Groups[1].Value
            if ($vXms -gt $vXmx) {
                $argsStr = [regex]::Replace($argsStr, '-Xms\d+G', ("-Xms" + $vXmx + "G"))
                Escribir-Log "Ajustada la RAM inicial a $vXmx GB (no puede superar la maxima)." "AVISO"
            }
        }
        $javaArgs = $argsStr -split " "

        $proceso = Start-Process -FilePath $config.servidor.java_exe `
            -ArgumentList ($javaArgs + @("-jar", $jarPath, "nogui")) `
            -WorkingDirectory $rutaInstancia `
            -WindowStyle Hidden `
            -PassThru

        if (-not $proceso) {
            Escribir-Log "Error al iniciar el proceso de Java." "ERROR"
            Eliminar-LockNube
            return
        }

        # PASO 9: Guardar lock local con PID
        Guardar-TextoSinBOM -Ruta $archivoLockLocal -Contenido (@{ pid = $proceso.Id; inicio = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss") } | ConvertTo-Json)

        # PASO 9.5: Esperar a que Paper este listo (RCON responda)
        Escribir-Log "Esperando a que Paper termine de cargar..." "INFO"
        $maxEspera = $config.servidor.tiempo_espera_inicio_seg
        $esperado = 0
        $listo = $false

        while ($esperado -lt $maxEspera -and -not $listo) {
            Start-Sleep -Seconds 3
            $esperado += 3

            # Verificar que java siga vivo
            $proc = Get-Process -Id $proceso.Id -ErrorAction SilentlyContinue
            if (-not $proc) {
                Escribir-Log "Java termino inesperadamente durante el arranque." "ERROR"
                Eliminar-LockNube
                Clear-Content $archivoLockLocal
                return
            }

            $resp = Enviar-RCON -Comando "list"
            if ($resp -ne $null) { $listo = $true }
        }

        if (-not $listo) {
            Escribir-Log "Paper no respondio por RCON despues de $maxEspera seg. Puede estar aun cargando." "WARN"
        } else {
            Escribir-Log "Paper listo. $resp" "OK"
        }

        # PASO 9.8: Iniciar Playit (si el metodo de red es playit)
        $playitExe = "C:\Program Files\playit_gg\bin\playit.exe"; if (-not (Test-Path $playitExe)) { $playitExe = Join-Path $rutaBase "playit.exe" }
        if ($config.red.metodo -eq "playit" -and (Test-Path $playitExe)) {
            Escribir-Log "Iniciando Playit..." "INFO"
            Start-Process -FilePath $playitExe -WindowStyle Hidden
            Escribir-Log "Playit iniciado." "OK"
        }

        # PASO 9.85: Actualizar DuckDNS (si el metodo es duckdns)
        Actualizar-DuckDNS

        # PASO 9.9: Iniciar Watchdog (monitorea traspaso de turno y crashes)
        $watchdogScript = Join-Path $rutaScripts "_watchdog.ps1"
        Start-Process -FilePath "PowerShell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdogScript`"" `
            -WindowStyle Hidden

        # PASO 9.95: Iniciar reporte de estado a Discord (cada 5-15 min)
        $statusScript = Join-Path $rutaScripts "_status_discord.ps1"
        Start-Process -FilePath "PowerShell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$statusScript`"" `
            -WindowStyle Hidden

        # PASO 9.96: Iniciar auto-save cada 15 min (proteccion contra crash)
        $autosaveScript = Join-Path $rutaScripts "_autosave.ps1"
        Start-Process -FilePath "PowerShell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$autosaveScript`"" `
            -WindowStyle Hidden

        # PASO 9.97: Iniciar monitor de log (notifica join/leave a Discord)
        $monitorScript = Join-Path $rutaScripts "_monitor_log.ps1"
        Start-Process -FilePath "PowerShell.exe" `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitorScript`"" `
            -WindowStyle Hidden

        # PASO 10: Actualizar estado
        $estado = Leer-Estado
        $estado.servidor_activo  = $true
        $estado.pid_java         = $proceso.Id
        $estado.inicio_sesion    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        $estado.turno_actual     = $config.identidad.este_pc
        $estado.ultimo_evento    = "Servidor iniciado"
        $estado.ultimo_evento_tiempo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado

        Escribir-Separador
        Escribir-Log "Servidor LISTO! Ya pueden conectarse." "OK"
        Escribir-Log "Cuando terminen, apaga desde el Panel o con Apagar.bat" "INFO"

        # Notificar a Discord
        if ($config.discord.notificar_inicio) { Discord-ServidorIniciado }

    } catch {
        Escribir-Log "Error inesperado durante el inicio: $_" "ERROR"
        Eliminar-LockNube
    }
}

# --------------------------------------------------
# FLUJO: APAGAR
# --------------------------------------------------
function Flujo-Apagar {
    Escribir-Separador "APAGANDO SERVIDOR"

    # Bandera de apagado intencional: el watchdog NO debe reiniciar
    $archivoApagando = Join-Path $rutaEstado "apagando.flag"
    Set-Content -Path $archivoApagando -Value "1" -ErrorAction SilentlyContinue

    try {
        # PASO 1: Verificar que el servidor esta activo
        $lockLocal = Verificar-LockLocal
        if ($lockLocal -eq "libre") {
            Escribir-Log "El servidor no esta corriendo. No hay nada que apagar." "WARN"
            Remove-Item $archivoApagando -Force -ErrorAction SilentlyContinue
            return
        }

        $lockData = Get-Content $archivoLockLocal -Raw | ConvertFrom-Json
        $pidJava  = $lockData.pid
        Escribir-Log "Servidor activo con PID: $pidJava" "INFO"

        # PASO 2: Enviar /save-all y /stop via RCON
        Escribir-Log "Enviando /save-all via RCON..." "INFO"
        $respSave = Enviar-RCON -Comando "save-all"
        if ($respSave -ne $null) {
            Escribir-Log "Respuesta: $respSave" "OK"
            Start-Sleep -Seconds 5
            Escribir-Log "Enviando /stop via RCON..." "INFO"
            $respStop = Enviar-RCON -Comando "stop"
            if ($respStop -ne $null) {
                Escribir-Log "Respuesta: $respStop" "OK"
            }
        } else {
            Escribir-Log "RCON no responde. El servidor puede haber crasheado." "WARN"
            Escribir-Log "Forzando cierre del proceso..." "WARN"
        }

        # Esperar que Java termine
        Escribir-Log "Esperando que Java termine..." "INFO"
        $proceso = Get-Process -Id $pidJava -ErrorAction SilentlyContinue
        if ($proceso) {
            $termino = $proceso.WaitForExit(30000)
            if (-not $termino) {
                Escribir-Log "Java no termino en 30 seg. Forzando cierre..." "WARN"
                $proceso.Kill()
                Start-Sleep -Seconds 3
            }
        }

        Escribir-Log "Java terminado." "OK"

        # PASO 3: Backup despues de apagar
        Escribir-Log "Creando backup post-apagado..." "INFO"
        Crear-Backup -Tipo "DespuesDeApagar"

        # PASO 3.5: Notificar a Discord que el servidor se apago (ya esta off)
        if ($config.discord.notificar_apagado) { Discord-ServidorApagado }

        # PASO 4: Cerrar Playit
        $playitProcs = Get-Process -Name "playit","playitd","playitd-tray","playitd-service" -ErrorAction SilentlyContinue
        if ($playitProcs) {
            Escribir-Log "Cerrando Playit ($($playitProcs.Count) procesos)..." "INFO"
            $playitProcs | Stop-Process -Force
            Escribir-Log "Playit cerrado." "OK"
        }

        # PASO 5: Subir mundo a la nube (solo si no es local)
        $esLocal = ($config.local -eq $true)
        if (-not $esLocal) {
            Escribir-Log "Sincronizando con la nube..." "INFO"
            if (-not (Subir-Mundo)) {
                Escribir-Log "ERROR: No se pudo sincronizar con la nube." "ERROR"
                Escribir-Log "El turno NO se liberara hasta que la subida sea exitosa." "ERROR"
                Escribir-Log "Verifica tu conexion e intenta apagar de nuevo." "WARN"
                return
            }
        } else {
            Escribir-Log "Modo local: no se sube nada a la nube." "INFO"
        }

        # PASO 6: Liberar turno en la nube
        if (-not $esLocal) { Eliminar-LockNube }

        # PASO 7: Limpiar lock local
        Clear-Content $archivoLockLocal

        # PASO 8: Actualizar estado
        $estado = Leer-Estado

        # Registrar sesion en el historial (estadisticas)
        try {
            if ($estado.inicio_sesion) {
                $ini = [datetime]::Parse($estado.inicio_sesion)
                $durMin = [math]::Round(((Get-Date) - $ini).TotalMinutes, 1)
                $histPath = Join-Path $rutaEstado "historial.json"
                $hist = @()
                if (Test-Path $histPath) {
                    $raw = Get-Content $histPath -Raw -ErrorAction SilentlyContinue
                    if ($raw) { $hist = @($raw | ConvertFrom-Json) }
                }
                $hist += [PSCustomObject]@{
                    pc = $config.identidad.este_pc
                    usuario = $config.identidad.nombre_usuario
                    inicio = $estado.inicio_sesion
                    fin = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
                    duracion_min = $durMin
                }
                if ($hist.Count -gt 500) { $hist = $hist[-500..-1] }
                Guardar-TextoSinBOM -Ruta $histPath -Contenido ($hist | ConvertTo-Json -Depth 5)
            }
        } catch { Escribir-Log "No se pudo registrar sesion: $_" "WARN" }

        $estado.servidor_activo      = $false
        $estado.pid_java             = $null
        $estado.turno_actual         = $null
        $estado.ultimo_evento        = "Servidor apagado correctamente"
        $estado.ultimo_evento_tiempo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado

        Escribir-Separador
        Escribir-Log "Servidor apagado y mundo guardado en la nube." "OK"
        Escribir-Log "$($config.identidad.otro_pc) ya puede iniciar cuando quiera." "INFO"

        # PROTECCION DE MIEMBROS: borrar archivos del mundo localmente (anti-trampa)
        if ($config.identidad.rol -eq "miembro" -and (-not $config.avanzado -or $config.avanzado.borrar_mundo_miembros)) {
            Escribir-Log "Limpiando archivos locales (rol miembro)..." "INFO"
            $aBorrar = @("world","plugins","config") |
                ForEach-Object { Join-Path $rutaInstancia $_ } |
                Where-Object { Test-Path $_ }
            foreach ($carpeta in $aBorrar) {
                Remove-Item $carpeta -Recurse -Force -ErrorAction SilentlyContinue
            }
            Escribir-Log "Archivos del mundo eliminados localmente." "OK"
        }

    } catch {
        Escribir-Log "Error inesperado durante el apagado: $_" "ERROR"
        Escribir-Log "Usa el modo Emergencia para limpiar el estado." "WARN"
    }
}

# --------------------------------------------------
# FLUJO: EMERGENCIA
# --------------------------------------------------
function Flujo-Emergencia {
    Escribir-Separador "MODO EMERGENCIA"
    Escribir-Log "Usa esto SOLO si el servidor crasheo y los .bat normales no responden." "WARN"
    Write-Host ""

    # Mostrar estado actual
    $estado = Leer-Estado
    Escribir-Log "Estado guardado: servidor_activo=$($estado.servidor_activo), PID=$($estado.pid_java)" "INFO"

    # Verificar si java sigue vivo
    $javaVivo = $false
    if ($estado.pid_java) {
        $proceso = Get-Process -Id $estado.pid_java -ErrorAction SilentlyContinue
        $javaVivo = $null -ne $proceso
        Escribir-Log "Java (PID $($estado.pid_java)) vivo en sistema: $javaVivo" "INFO"
    }

    Write-Host ""
    Write-Host "Que deseas hacer?" -ForegroundColor Yellow
    Write-Host "  [1] Forzar cierre de Java y limpiar locks (servidor crasheo)"
    Write-Host "  [2] Solo limpiar lock local (lock fantasma)"
    Write-Host "  [3] Solo limpiar lock en nube (quedaste bloqueado remotamente)"
    Write-Host "  [4] Limpiar todos los locks (reset completo)"
    Write-Host "  [5] Salir sin hacer nada"
    Write-Host ""
    $opcion = Read-Host "Opcion"

    switch ($opcion) {
        "1" {
            if ($javaVivo) {
                Get-Process -Id $estado.pid_java | Stop-Process -Force
                Escribir-Log "Java forzado a cerrar." "OK"
            }
            Clear-Content $archivoLockLocal
            Eliminar-LockNube
            $estado.servidor_activo = $false
            $estado.pid_java = $null
            $estado.turno_actual = $null
            $estado.ultimo_evento = "Emergencia: cierre forzado"
            Guardar-Estado $estado
            Escribir-Log "Locks limpiados. RECUERDA: sube el mundo manualmente si habia progreso." "WARN"
        }
        "2" {
            Clear-Content $archivoLockLocal
            Escribir-Log "Lock local limpiado." "OK"
        }
        "3" {
            Eliminar-LockNube
            Escribir-Log "Lock en nube eliminado." "OK"
        }
        "4" {
            Clear-Content $archivoLockLocal
            Eliminar-LockNube
            $estado.servidor_activo = $false
            $estado.pid_java = $null
            $estado.turno_actual = $null
            Guardar-Estado $estado
            Escribir-Log "Reset completo de locks." "OK"
        }
        default {
            Escribir-Log "Saliendo sin cambios." "INFO"
        }
    }
}

# --------------------------------------------------
# FLUJO: RESTAURAR
# --------------------------------------------------
function Flujo-Restaurar {
    Escribir-Separador "RESTAURAR BACKUP"

    # Verificar que el servidor esta apagado
    $lockLocal = Verificar-LockLocal
    if ($lockLocal -eq "ocupado") {
        Escribir-Log "No puedes restaurar mientras el servidor esta activo. Apagalo primero." "ERROR"
        return
    }

    # Listar backups disponibles
    $backups = Listar-Backups
    if ($backups.Count -eq 0) {
        Escribir-Log "No hay backups disponibles para restaurar." "WARN"
        return
    }

    # Modo no interactivo: si se paso -Backup (nombre de archivo), restaurar ese directamente
    if ($Backup) {
        $elegidoDirecto = $backups | Where-Object { $_.Nombre -eq $Backup -or $_.Ruta -eq $Backup } | Select-Object -First 1
        if (-not $elegidoDirecto) {
            Escribir-Log "No se encontro el backup: $Backup" "ERROR"
            return
        }
        Escribir-Log "Restaurando (panel): $($elegidoDirecto.Nombre)" "WARN"
        if (Restaurar-Backup -RutaZip $elegidoDirecto.Ruta) {
            Escribir-Log "Restauracion completada. Ya puedes iniciar el servidor." "OK"
        } else {
            Escribir-Log "La restauracion fallo. Revisa los logs." "ERROR"
        }
        return
    }

    Write-Host ""
    Write-Host "Backups disponibles:" -ForegroundColor Cyan
    Write-Host ""

    for ($i = 0; $i -lt [Math]::Min($backups.Count, 15); $i++) {
        $b = $backups[$i]
        Write-Host "  [$($i+1)] $($b.Fecha.ToString('yyyy-MM-dd HH:mm')) | $($b.Tipo) | $($b.TamanoMB) MB | $($b.Nombre)"
    }

    Write-Host ""
    $seleccion = Read-Host "Numero de backup a restaurar (0 para cancelar)"

    if ($seleccion -eq "0" -or [string]::IsNullOrWhiteSpace($seleccion)) {
        Escribir-Log "Restauracion cancelada." "INFO"
        return
    }

    $idx = [int]$seleccion - 1
    if ($idx -lt 0 -or $idx -ge $backups.Count) {
        Escribir-Log "Seleccion invalida." "ERROR"
        return
    }

    $backupElegido = $backups[$idx]
    Escribir-Log "Restaurando: $($backupElegido.Nombre)" "WARN"
    Write-Host ""
    $confirmar = Read-Host "Estas seguro? Esto reemplazara el mundo actual. Escribe SI para confirmar"

    if ($confirmar -ne "SI") {
        Escribir-Log "Restauracion cancelada por el usuario." "INFO"
        return
    }

    if (Restaurar-Backup -RutaZip $backupElegido.Ruta) {
        Escribir-Log "Restauracion completada. Ya puedes iniciar el servidor." "OK"
    } else {
        Escribir-Log "La restauracion fallo. Revisa los logs." "ERROR"
    }
}

# --------------------------------------------------
# FLUJO: REINICIAR (rapido, sin sincronizar nube)
# --------------------------------------------------
function Flujo-Reiniciar {
    Escribir-Separador "REINICIANDO SERVIDOR"
    $archivoApagando = Join-Path $rutaEstado "apagando.flag"
    Set-Content -Path $archivoApagando -Value "1" -ErrorAction SilentlyContinue

    try {
        # PASO 1: Verificar que esta activo
        $lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($lockContenido)) {
            Escribir-Log "El servidor no esta corriendo. Usa Iniciar." "WARN"
            Remove-Item $archivoApagando -Force -ErrorAction SilentlyContinue
            return
        }

        $lockData = $lockContenido | ConvertFrom-Json
        $pidJava = $lockData.pid

        # PASO 2: save-all + stop via RCON
        Escribir-Log "Guardando mundo..." "INFO"
        Enviar-RCON -Comando "save-all" | Out-Null
        Start-Sleep -Seconds 3
        Escribir-Log "Deteniendo servidor..." "INFO"
        Enviar-RCON -Comando "stop" | Out-Null

        # PASO 3: Esperar que Java termine
        $proceso = Get-Process -Id $pidJava -ErrorAction SilentlyContinue
        if ($proceso) {
            $proceso.WaitForExit(20000) | Out-Null
            if (-not $proceso.HasExited) { $proceso.Kill(); Start-Sleep -Seconds 2 }
        }
        Escribir-Log "Servidor detenido." "OK"

        # PASO 4: Backup rapido
        Escribir-Log "Creando backup..." "INFO"
        Crear-Backup -Tipo "AntesDeIniciar" | Out-Null

        # PASO 5: Iniciar Paper de nuevo
        Escribir-Log "Iniciando servidor..." "INFO"
        $jarPath = Join-Path $rutaInstancia $config.servidor.jar_nombre
        $javaArgs = $config.servidor.java_args -split " "

        $proceso = Start-Process -FilePath $config.servidor.java_exe `
            -ArgumentList ($javaArgs + @("-jar", $jarPath, "nogui")) `
            -WorkingDirectory $rutaInstancia `
            -WindowStyle Hidden `
            -PassThru

        # PASO 6: Actualizar lock con nuevo PID
        Guardar-TextoSinBOM -Ruta $archivoLockLocal -Contenido (@{ pid = $proceso.Id; inicio = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss") } | ConvertTo-Json)
        # Nuevo PID vivo: el watchdog ya puede volver a vigilar normalmente
        Remove-Item $archivoApagando -Force -ErrorAction SilentlyContinue

        # PASO 7: Esperar RCON
        Escribir-Log "Esperando a que Paper cargue..." "INFO"
        $esperado = 0
        $listo = $false
        while ($esperado -lt $config.servidor.tiempo_espera_inicio_seg -and -not $listo) {
            Start-Sleep -Seconds 3
            $esperado += 3
            $proc = Get-Process -Id $proceso.Id -ErrorAction SilentlyContinue
            if (-not $proc) {
                Escribir-Log "Java termino inesperadamente." "ERROR"
                Clear-Content $archivoLockLocal
                return
            }
            $resp = Enviar-RCON -Comando "list"
            if ($resp -ne $null) { $listo = $true }
        }

        # PASO 8: Playit
        $playitExe = "C:\Program Files\playit_gg\bin\playit.exe"; if (-not (Test-Path $playitExe)) { $playitExe = Join-Path $rutaBase "playit.exe" }
        if (Test-Path $playitExe) {
            $playitRunning = Get-Process -Name "playit" -ErrorAction SilentlyContinue
            if (-not $playitRunning) {
                Start-Process -FilePath $playitExe -WindowStyle Hidden
            }
        }

        # PASO 9: Actualizar estado
        $estado = Leer-Estado
        $estado.servidor_activo = $true
        $estado.pid_java = $proceso.Id
        $estado.inicio_sesion = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        $estado.ultimo_evento = "Servidor reiniciado"
        $estado.ultimo_evento_tiempo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado

        Escribir-Log "Servidor reiniciado correctamente." "OK"

        if ($config.discord.notificar_inicio) { Discord-ServidorIniciado }

    } catch {
        Escribir-Log "Error durante el reinicio: $_" "ERROR"
    }
}

# --------------------------------------------------
# PUNTO DE ENTRADA
# --------------------------------------------------
Write-Host ""
Write-Host "  ======================================" -ForegroundColor Cyan
Write-Host "   ServidorTecnico v$($config.identidad.version_sistema)" -ForegroundColor Cyan
Write-Host "   PC: $($config.identidad.este_pc)" -ForegroundColor Cyan
Write-Host "  ======================================" -ForegroundColor Cyan
Write-Host ""

$opLock = Join-Path $rutaEstado "operacion.lock"

# Candado: evitar dos operaciones pesadas a la vez (iniciar/apagar/reiniciar)
if ($Accion -in @("iniciar","apagar","reiniciar")) {
    if (Test-Path $opLock) {
        $edad = (Get-Date) - (Get-Item $opLock).LastWriteTime
        if ($edad.TotalMinutes -lt 5) {
            Escribir-Log "Ya hay una operacion en curso. Espera a que termine." "WARN"
            return
        }
    }
    Set-Content -Path $opLock -Value $Accion
}

try {
    switch ($Accion) {
        "iniciar"    { Flujo-Iniciar }
        "apagar"     { Flujo-Apagar }
        "reiniciar"  { Flujo-Reiniciar }
        "emergencia" { Flujo-Emergencia }
        "restaurar"  { Flujo-Restaurar }
    }
} finally {
    if ($Accion -in @("iniciar","apagar","reiniciar")) {
        Remove-Item $opLock -Force -ErrorAction SilentlyContinue
    }
}
