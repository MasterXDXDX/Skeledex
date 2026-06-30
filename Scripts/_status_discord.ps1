# =====================================================
#  _status_discord.ps1
#  Envia estado del servidor a Discord periodicamente.
#  Se ejecuta en segundo plano al iniciar.
# =====================================================

$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaScripts       = Join-Path $rutaBase "Scripts"
$rutaEstado        = Join-Path $rutaBase "Estado"
$rutaRegistros     = Join-Path $rutaBase "Registros"
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"   # define $archivoConfig (en %APPDATA%, portable)
$archivoLockLocal  = Join-Path $rutaEstado "servidor.lock"

$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json
. "$rutaScripts\_registros.ps1"
. "$rutaScripts\_rcon.ps1"
. "$rutaScripts\_discord.ps1"

# Solo correr si el reporte periodico esta habilitado
if (-not ($config.discord.usar -and $config.discord.status_periodico)) { return }
$intervaloMin = if ($config.discord.status_intervalo_min) { [int]$config.discord.status_intervalo_min } else { 30 }

while ($true) {
    Start-Sleep -Seconds ($intervaloMin * 60)

    # Verificar que el server sigue vivo
    $lockContenido = Get-Content $archivoLockLocal -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($lockContenido)) { break }
    $lockData = $lockContenido | ConvertFrom-Json -ErrorAction SilentlyContinue
    $proc = Get-Process -Id $lockData.pid -ErrorAction SilentlyContinue
    if (-not $proc) { break }

    # Obtener info via RCON
    $resp = Enviar-RCON -Comando "list"
    $conteo = "0 / 20"
    $jugadores = "Nadie"
    if ($resp -match "(\d+) of a max of (\d+)") {
        $conteo = "$($Matches[1]) / $($Matches[2])"
    }
    if ($resp -match ":\s*(.+)$") {
        $nombres = $Matches[1].Trim()
        if ($nombres) { $jugadores = $nombres }
    }

    # Tiempo activo
    $inicio = [datetime]::Parse($lockData.inicio)
    $diff = (Get-Date) - $inicio
    $tiempo = if ($diff.TotalHours -ge 1) { "$([int]$diff.TotalHours)h $($diff.Minutes)m" } else { "$($diff.Minutes)m" }

    # Enviar embed
    $payload = @{
        embeds = @(@{
            title = ":bar_chart: Estado del Servidor"
            color = 3447003
            fields = @(
                @{ name = ":busts_in_silhouette: Jugadores ($conteo)"; value = $jugadores; inline = $false }
                @{ name = ":desktop: Host"; value = $config.identidad.este_pc; inline = $true }
                @{ name = ":clock3: Activo"; value = $tiempo; inline = $true }
            )
            footer = @{ text = "Skeledex" }
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        })
    }
    Enviar-Discord -Payload $payload
}
