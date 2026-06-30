# =====================================================
#  _discord.ps1
#  Notificaciones a Discord via webhook.
#  Mensajes personalizables con placeholders:
#   {usuario} {pc} {puerto} {jugadores} {conteo} {ip} {jugador}
# =====================================================

function Discord-Activo {
    if ($null -eq $config.discord) { return $false }
    # Si existe la propiedad 'usar' y es false, desactivado
    if ($null -ne $config.discord.usar -and -not $config.discord.usar) { return $false }
    if ([string]::IsNullOrWhiteSpace($config.discord.webhook_url)) { return $false }
    return $true
}

function Reemplazar-Placeholders {
    param([string]$Texto, [hashtable]$Datos)
    if (-not $Texto) { return "" }
    foreach ($k in $Datos.Keys) {
        $Texto = $Texto.Replace("{$k}", [string]$Datos[$k])
    }
    return $Texto
}

function Direccion-Publica {
    if ($null -eq $config.red) { return "" }
    if ($config.red.direccion_publica) { return $config.red.direccion_publica }
    switch ($config.red.metodo) {
        "playit"  { return $config.red.playit_direccion }
        "duckdns" { if ($config.red.duckdns_dominio) { return "$($config.red.duckdns_dominio).duckdns.org" } }
        "manual"  { return $config.red.ip_manual }
    }
    return ""
}

function Enviar-Discord {
    param([hashtable]$Payload)
    if (-not (Discord-Activo)) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Payload.username = $config.discord.nombre_bot
    $json = $Payload | ConvertTo-Json -Depth 5
    try {
        Invoke-WebRequest -Uri $config.discord.webhook_url -Method Post -ContentType "application/json" -Body ([System.Text.Encoding]::UTF8.GetBytes($json)) -UseBasicParsing | Out-Null
    } catch {
        Escribir-Log "Discord webhook error: $_" "WARN"
    }
}

function Discord-ServidorIniciado {
    $jugadoresTexto = "Ninguno"; $conteo = "0 / 20"
    $resp = Enviar-RCON -Comando "list"
    if ($resp -match "(\d+) of a max of (\d+)") { $conteo = "$($Matches[1]) / $($Matches[2])" }
    if ($resp -match ":\s*(.+)$") { $n = $Matches[1].Trim(); if ($n) { $jugadoresTexto = $n } }

    $datos = @{
        usuario = $config.identidad.nombre_usuario; pc = $config.identidad.este_pc
        puerto = $config.servidor.puerto; jugadores = $jugadoresTexto; conteo = $conteo; ip = (Direccion-Publica)
    }
    $plantilla = if ($config.discord.mensaje_inicio) { $config.discord.mensaje_inicio } else { "**{usuario}** ha iniciado el servidor." }
    $desc = Reemplazar-Placeholders $plantilla $datos

    $fields = @(
        @{ name = ":busts_in_silhouette: Jugadores ($conteo)"; value = $jugadoresTexto; inline = $false }
        @{ name = ":desktop: Iniciado desde"; value = $config.identidad.este_pc; inline = $true }
        @{ name = ":clock3: Hora"; value = (Get-Date -Format "hh:mm tt"); inline = $true }
    )
    $ip = Direccion-Publica
    if ($ip) { $fields += @{ name = ":globe_with_meridians: IP"; value = $ip; inline = $true } }

    Enviar-Discord -Payload @{
        embeds = @(@{
            title = ":green_circle: Servidor ONLINE"; description = $desc; color = 3066993
            fields = $fields
            footer = @{ text = "ServidorTecnico v$($config.identidad.version_sistema)" }
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        })
    }
}

function Discord-ServidorApagado {
    $datos = @{ usuario = $config.identidad.nombre_usuario; pc = $config.identidad.este_pc }
    $plantilla = if ($config.discord.mensaje_apagado) { $config.discord.mensaje_apagado } else { "**{usuario}** ha apagado el servidor." }
    $desc = Reemplazar-Placeholders $plantilla $datos
    Enviar-Discord -Payload @{
        embeds = @(@{
            title = ":red_circle: Servidor OFFLINE"; description = $desc; color = 15158332
            fields = @(
                @{ name = ":floppy_disk: Estado"; value = "Mundo sincronizado"; inline = $true }
                @{ name = ":unlock: Turno"; value = "Libre"; inline = $true }
            )
            footer = @{ text = "ServidorTecnico v$($config.identidad.version_sistema)" }
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        })
    }
}

function Discord-ServidorReiniciando {
    $datos = @{ usuario = $config.identidad.nombre_usuario; pc = $config.identidad.este_pc }
    $plantilla = if ($config.discord.mensaje_reinicio) { $config.discord.mensaje_reinicio } else { "**{usuario}** esta reiniciando el servidor." }
    $desc = Reemplazar-Placeholders $plantilla $datos
    Enviar-Discord -Payload @{
        embeds = @(@{
            title = ":arrows_counterclockwise: Servidor REINICIANDO"; description = $desc; color = 16760576
            footer = @{ text = "ServidorTecnico v$($config.identidad.version_sistema)" }
            timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        })
    }
}
