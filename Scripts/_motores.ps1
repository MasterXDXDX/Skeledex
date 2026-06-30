# =====================================================
#  _motores.ps1
#  Gestiona el motor del servidor: listar versiones,
#  instalar y actualizar. Soporta jar unico:
#  purpur, paper, vanilla, fabric. (forge/neoforge/spigot
#  se listan pero requieren motor personalizado.)
#  Acciones: versiones | instalar | actualizar
#  Salida: JSON
# =====================================================
param(
    [string]$Accion = "versiones",
    [string]$Motor = "purpur",
    [string]$Version = "",
    [string]$CarpetaInstancia = "Instancia"
)
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$inst = Join-Path $rutaBase $CarpetaInstancia
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = @{ 'User-Agent' = 'Skeledex/1.0' }

function Lista-Versiones($motor) {
    # Devuelve SIEMPRE mas nuevas primero
    switch ($motor) {
        'purpur'   { $v = @((Invoke-RestMethod 'https://api.purpurmc.org/v2/purpur' -Headers $ua -TimeoutSec 20).versions); [array]::Reverse($v); return $v }
        'paper'    { $v = @((Invoke-RestMethod 'https://api.papermc.io/v2/projects/paper' -Headers $ua -TimeoutSec 20).versions); [array]::Reverse($v); return $v }
        'folia'    { $v = @((Invoke-RestMethod 'https://api.papermc.io/v2/projects/folia' -Headers $ua -TimeoutSec 20).versions); [array]::Reverse($v); return $v }
        'vanilla'  { $r = Invoke-RestMethod 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json' -Headers $ua -TimeoutSec 20; return @($r.versions | Where-Object { $_.type -eq 'release' } | ForEach-Object { $_.id }) }
        'fabric'   { $r = Invoke-RestMethod 'https://meta.fabricmc.net/v2/versions/game' -Headers $ua -TimeoutSec 20; return @($r | Where-Object { $_.stable } | ForEach-Object { $_.version }) }
        'neoforge' { $xml = [xml](Invoke-WebRequest 'https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml' -UseBasicParsing -Headers $ua -TimeoutSec 20).Content; $v = @($xml.metadata.versioning.versions.version); [array]::Reverse($v); return $v }
        'forge'    { $xml = [xml](Invoke-WebRequest 'https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml' -UseBasicParsing -Headers $ua -TimeoutSec 20).Content; $v = @($xml.metadata.versioning.versions.version); [array]::Reverse($v); return $v }
        default    { return @() }
    }
}

function Instalar-Motor($motor, $version) {
    if (-not (Test-Path $inst)) { New-Item $inst -ItemType Directory -Force | Out-Null }
    switch ($motor) {
        'purpur' {
            $dest = Join-Path $inst 'purpur.jar'
            Invoke-WebRequest "https://api.purpurmc.org/v2/purpur/$version/latest/download" -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return 'purpur.jar'
        }
        'paper' {
            $b = ((Invoke-RestMethod "https://api.papermc.io/v2/projects/paper/versions/$version" -Headers $ua -TimeoutSec 20).builds)[-1]
            $dest = Join-Path $inst 'paper.jar'
            Invoke-WebRequest "https://api.papermc.io/v2/projects/paper/versions/$version/builds/$b/downloads/paper-$version-$b.jar" -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return 'paper.jar'
        }
        'folia' {
            $b = ((Invoke-RestMethod "https://api.papermc.io/v2/projects/folia/versions/$version" -Headers $ua -TimeoutSec 20).builds)[-1]
            $dest = Join-Path $inst 'folia.jar'
            Invoke-WebRequest "https://api.papermc.io/v2/projects/folia/versions/$version/builds/$b/downloads/folia-$version-$b.jar" -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return 'folia.jar'
        }
        'vanilla' {
            $r = Invoke-RestMethod 'https://launchermeta.mojang.com/mc/game/version_manifest_v2.json' -Headers $ua -TimeoutSec 20
            $v = $r.versions | Where-Object { $_.id -eq $version } | Select-Object -First 1
            if (-not $v) { throw "version no encontrada" }
            $pkg = Invoke-RestMethod $v.url -Headers $ua -TimeoutSec 20
            $dest = Join-Path $inst 'server.jar'
            Invoke-WebRequest $pkg.downloads.server.url -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return 'server.jar'
        }
        'fabric' {
            $loader = (Invoke-RestMethod "https://meta.fabricmc.net/v2/versions/loader/$version" -Headers $ua -TimeoutSec 20)[0].loader.version
            $inst_v = (Invoke-RestMethod 'https://meta.fabricmc.net/v2/versions/installer' -Headers $ua -TimeoutSec 20)[0].version
            $dest = Join-Path $inst 'fabric-server-launch.jar'
            Invoke-WebRequest "https://meta.fabricmc.net/v2/versions/loader/$version/$loader/$inst_v/server/jar" -OutFile $dest -UseBasicParsing -TimeoutSec 300
            return 'fabric-server-launch.jar'
        }
        default { throw "motor-no-soportado-auto" }
    }
}

try {
    switch ($Accion) {
        'versiones' {
            $vs = @(Lista-Versiones $Motor)
            $vs = $vs | Select-Object -First 80
            $auto = ($Motor -in @('purpur','paper','folia','vanilla','fabric'))
            (@{ ok = $true; motor = $Motor; auto = $auto; versiones = @($vs) } | ConvertTo-Json -Compress)
        }
        'instalar' {
            if (-not $Version) { Write-Output '{"ok":false,"error":"sin-version"}'; return }
            $jar = Instalar-Motor $Motor $Version
            (@{ ok = $true; jar = $jar; version = $Version } | ConvertTo-Json -Compress)
        }
        'actualizar' {
            $vs = @(Lista-Versiones $Motor)
            $ultima = $vs | Select-Object -First 1
            if (-not $ultima) { Write-Output '{"ok":false,"error":"sin-versiones"}'; return }
            $jar = Instalar-Motor $Motor $ultima
            (@{ ok = $true; jar = $jar; version = $ultima } | ConvertTo-Json -Compress)
        }
        default { Write-Output '{"ok":false,"error":"accion-desconocida"}' }
    }
} catch {
    (@{ ok = $false; error = ("$_" -replace '"', "'") } | ConvertTo-Json -Compress)
}
