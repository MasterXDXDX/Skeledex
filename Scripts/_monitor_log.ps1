# =====================================================
#  _monitor_log.ps1
#  Lee latest.log en tiempo real y notifica a Discord
#  cuando un jugador entra o sale.
#  Corre en segundo plano, lanzado al iniciar.
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaInstancia     = Join-Path $rutaBase "Instancia"
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$archivoLockLocal  = Join-Path $rutaEstado "servidor.lock"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_discord.ps1"

if (-not $config.discord.notificar_jugadores) { return }

$logFile = Join-Path $rutaInstancia "logs\latest.log"
if (-not (Test-Path $logFile)) { return }

# Empezar desde el final del archivo actual
$ultimaPos = (Get-Item $logFile).Length

while ($true) {
    Start-Sleep -Seconds 5

    # Salir si el server se apago
    $lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($lockContenido)) { break }

    if (-not (Test-Path $logFile)) { continue }
    $tam = (Get-Item $logFile).Length
    # Si el log se rote (mas pequeno), reiniciar posicion
    if ($tam -lt $ultimaPos) { $ultimaPos = 0 }
    if ($tam -eq $ultimaPos) { continue }

    $fs = [System.IO.File]::Open($logFile, 'Open', 'Read', 'ReadWrite')
    $fs.Seek($ultimaPos, 'Begin') | Out-Null
    $sr = New-Object System.IO.StreamReader($fs)
    $nuevo = $sr.ReadToEnd()
    $sr.Close(); $fs.Close()
    $ultimaPos = $tam

    foreach ($linea in ($nuevo -split "`n")) {
        if ($linea -match "\]: (\w+) joined the game") {
            $jug = $Matches[1]
            $plantilla = if ($config.discord.mensaje_join) { $config.discord.mensaje_join } else { "{jugador} entro al servidor" }
            $titulo = $plantilla.Replace("{jugador}", $jug)
            Enviar-Discord -Payload @{
                embeds = @(@{
                    title = ":inbox_tray: $titulo"
                    color = 3066993
                    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                })
            }
        }
        elseif ($linea -match "\]: (\w+) left the game") {
            $jug = $Matches[1]
            $plantilla = if ($config.discord.mensaje_leave) { $config.discord.mensaje_leave } else { "{jugador} salio del servidor" }
            $titulo = $plantilla.Replace("{jugador}", $jug)
            Enviar-Discord -Payload @{
                embeds = @(@{
                    title = ":outbox_tray: $titulo"
                    color = 10070709
                    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                })
            }
        }
    }
}
