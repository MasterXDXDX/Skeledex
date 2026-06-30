# =====================================================
#  _primer_servidor.ps1
#  Prepara una instancia vacia: descarga Purpur, acepta
#  el EULA y crea server.properties con el RCON que usa
#  el panel. Idempotente: no pisa lo que ya existe.
#  Salida: JSON { ok, jar, mensaje }
# =====================================================
$rutaBase          = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$rutaConfiguracion = Join-Path $rutaBase "Configuracion"
. "$PSScriptRoot\_config_path.ps1"
$config = Get-Content $archivoConfig -Raw | ConvertFrom-Json

$carpeta = if ($config.servidor.carpeta_instancia) { $config.servidor.carpeta_instancia } else { "Instancia" }
$inst = Join-Path $rutaBase $carpeta
if (-not (Test-Path $inst)) { New-Item $inst -ItemType Directory -Force | Out-Null }

$mensajes = @()

# 1) Descargar Purpur si no hay ningun .jar
$jars = Get-ChildItem $inst -Filter *.jar -ErrorAction SilentlyContinue
if (-not $jars -or @($jars).Count -eq 0) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $v = (Invoke-RestMethod 'https://api.purpurmc.org/v2/purpur' -TimeoutSec 20).versions[-1]
        $dest = Join-Path $inst ($config.servidor.jar_nombre)
        if (-not $dest.EndsWith('.jar')) { $dest = Join-Path $inst 'purpur.jar' }
        Invoke-WebRequest "https://api.purpurmc.org/v2/purpur/$v/latest/download" -OutFile $dest -UseBasicParsing -TimeoutSec 300
        $mensajes += "Purpur $v descargado"
    } catch { Write-Output ('{"ok":false,"error":"descarga-jar"}'); return }
} else {
    $mensajes += "Ya habia un .jar"
}

# 2) EULA
$eula = Join-Path $inst "eula.txt"
if (-not (Test-Path $eula) -or -not (Select-String -Path $eula -Pattern 'eula=true' -Quiet)) {
    Set-Content -Path $eula -Value "eula=true" -Encoding ASCII
    $mensajes += "EULA aceptado"
}

# 3) server.properties con RCON acorde al panel
$props = Join-Path $inst "server.properties"
$puerto = if ($config.servidor.puerto) { $config.servidor.puerto } else { 25565 }
$rconP  = if ($config.servidor.rcon_puerto) { $config.servidor.rcon_puerto } else { 25575 }
$rconPw = $config.servidor.rcon_password
if (-not (Test-Path $props)) {
    $contenido = @(
        "server-port=$puerto",
        "enable-rcon=true",
        "rcon.port=$rconP",
        "rcon.password=$rconPw",
        "motd=Skeledex Server",
        "max-players=20",
        "online-mode=true",
        "pvp=true",
        "difficulty=normal",
        "gamemode=survival",
        "view-distance=10",
        "spawn-protection=0"
    ) -join "`n"
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($props, $contenido + "`n", $utf8)
    $mensajes += "server.properties creado con RCON"
} else {
    # Asegurar que el RCON coincide para que el panel pueda hablar con el server
    $txt = Get-Content $props -Raw
    if ($txt -notmatch 'enable-rcon=true') {
        $txt = $txt -replace 'enable-rcon=false', 'enable-rcon=true'
        if ($txt -notmatch 'enable-rcon') { $txt += "`nenable-rcon=true" }
        Set-Content $props $txt -Encoding UTF8
        $mensajes += "RCON habilitado"
    }
}

(@{ ok = $true; mensaje = ($mensajes -join "; ") } | ConvertTo-Json -Compress)
