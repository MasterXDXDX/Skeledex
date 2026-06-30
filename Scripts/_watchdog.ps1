# =====================================================
#  _watchdog.ps1
#  Vigila el servidor:
#   - Si otro PC toma el turno (lock nube): apaga y cede.
#   - Si Paper crashea inesperadamente: lo reinicia solo.
#  Revisa Java cada 15s (local, gratis).
#  Revisa lock en nube cada 60s (reduce llamadas a B2).
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaInstancia     = Join-Path $rutaBase "Instancia"
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$archivoEstado     = Join-Path $rutaEstado "estado.json"
$archivoLockLocal  = Join-Path $rutaEstado "servidor.lock"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_rcon.ps1"
. "$rutaScripts\_nube.ps1"
. "$rutaScripts\_discord.ps1"

$rutaRclone = "C:\rclone\rclone.exe"
$estePC = $config.identidad.este_pc

function Leer-Estado {
    return Get-Content $archivoEstado -Raw | ConvertFrom-Json
}
function Guardar-Estado {
    param([object]$Estado)
    Guardar-TextoSinBOM -Ruta $archivoEstado -Contenido ($Estado | ConvertTo-Json -Depth 5)
}

function Reiniciar-PaperCrash {
    param($PidViejo)
    Escribir-Log "WATCHDOG: Paper crasheo (PID $PidViejo). Reiniciando automaticamente..." "WARN"
    Discord-ServidorReiniciando

    $jarPath = Join-Path $rutaInstancia $config.servidor.jar_nombre
    $javaArgs = $config.servidor.java_args -split " "
    $proceso = Start-Process -FilePath $config.servidor.java_exe `
        -ArgumentList ($javaArgs + @("-jar", $jarPath, "nogui")) `
        -WorkingDirectory $rutaInstancia -PassThru

    if ($proceso) {
        Guardar-TextoSinBOM -Ruta $archivoLockLocal -Contenido (@{ pid = $proceso.Id; inicio = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss") } | ConvertTo-Json)
        $estado = Leer-Estado
        $estado.pid_java = $proceso.Id
        $estado.ultimo_evento = "Reinicio automatico tras crash"
        $estado.ultimo_evento_tiempo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado
        Escribir-Log "WATCHDOG: Paper reiniciado con PID $($proceso.Id)." "OK"
        return $proceso.Id
    } else {
        Escribir-Log "WATCHDOG: No se pudo reiniciar Paper." "ERROR"
        return $null
    }
}

Escribir-Log "Watchdog iniciado. Vigilando crashes y traspaso de turno..." "INFO"

$ciclo = 0
$crashes = 0

while ($true) {
    Start-Sleep -Seconds 15
    $ciclo++

    # ----- Chequeo local (gratis): el lock local existe? -----
    $lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($lockContenido)) { break }  # apagado normal
    $lockData = $lockContenido | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $lockData) { break }

    # ----- Auto-restart si Paper crasheo -----
    $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
    if (-not $proc) {
        # No reiniciar si es un apagado/reinicio intencional (el usuario le dio Apagar/Reiniciar)
        if (Test-Path (Join-Path $rutaEstado "apagando.flag")) {
            continue
        }
        # Respetar el toggle de auto-reinicio por crash
        if ($config.avanzado -and $config.avanzado.auto_reinicio_crash -eq $false) {
            Escribir-Log "WATCHDOG: auto-reinicio desactivado en ajustes. No se reinicia." "INFO"
            break
        }
        $crashes++
        if ($crashes -le 3) {
            $nuevoPid = Reiniciar-PaperCrash -PidViejo $lockData.pid
            if (-not $nuevoPid) { break }
            # esperar a que cargue antes de seguir vigilando
            Start-Sleep -Seconds 30
            $crashes = $crashes  # mantener contador
            continue
        } else {
            Escribir-Log "WATCHDOG: Paper crasheo 3 veces seguidas. Deteniendo vigilancia." "ERROR"
            break
        }
    } else {
        # Si lleva un rato estable, resetear contador de crashes
        if ($ciclo % 20 -eq 0) { $crashes = 0 }
    }

    # ----- Chequeo de nube cada 60s (cada 4 ciclos) para reducir B2 -----
    if ($config.local -eq $true) { continue }
    if ($ciclo % 4 -ne 0) { continue }

    $remoto = $config.nube.rclone_remoto
    $bucket = $config.nube.bucket
    $archivoLock = $config.nube.archivo_lock

    $existe = & $rutaRclone lsf "${remoto}:${bucket}/${archivoLock}" 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($existe)) {
        Escribir-Log "WATCHDOG: Lock eliminado por otro PC. Cediendo turno..." "WARN"
        Enviar-RCON -Comando "say El servidor se transfiere a otro PC. Desconectense en 10 segundos!" | Out-Null
        Start-Sleep -Seconds 10
        Enviar-RCON -Comando "save-all" | Out-Null
        Start-Sleep -Seconds 3
        Enviar-RCON -Comando "stop" | Out-Null

        $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
        if ($proc) {
            $proc.WaitForExit(30000) | Out-Null
            if (-not $proc.HasExited) { $proc.Kill() }
        }
        Get-Process -Name "playit","playitd","playitd-tray","playitd-service" -ErrorAction SilentlyContinue | Stop-Process -Force

        Escribir-Log "WATCHDOG: Subiendo mundo antes de soltar..." "INFO"
        Subir-Mundo | Out-Null

        Clear-Content $archivoLockLocal
        $estado = Leer-Estado
        $estado.servidor_activo = $false
        $estado.pid_java = $null
        $estado.turno_actual = $null
        $estado.ultimo_evento = "Servidor traspasado automaticamente"
        $estado.ultimo_evento_tiempo = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
        Guardar-Estado $estado

        Escribir-Log "WATCHDOG: Turno cedido y mundo subido." "OK"
        Discord-ServidorApagado
        break
    }
}

Escribir-Log "Watchdog finalizado." "INFO"
