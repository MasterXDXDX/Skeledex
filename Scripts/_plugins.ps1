# =====================================================
#  _plugins.ps1
#  Gestor de plugins via Modrinth API.
#  Acciones: buscar | instalar | listar | eliminar
#  Salida: JSON
# =====================================================
param(
    [string]$Accion = "listar",
    [string]$Query = "",
    [string]$ProjectId = "",
    [string]$Nombre = "",
    [string]$CarpetaInstancia = "Instancia"
)
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$plugins  = Join-Path $rutaBase (Join-Path $CarpetaInstancia "plugins")
$ua = @{ 'User-Agent' = 'Skeledex/1.0 (minecraft control panel)' }

switch ($Accion) {
    "buscar" {
        $q = [uri]::EscapeDataString($Query)
        $u = "https://api.modrinth.com/v2/search?query=$q&facets=%5B%5B%22project_type:plugin%22%5D%5D&limit=12"
        try { $r = Invoke-RestMethod $u -Headers $ua -TimeoutSec 15 } catch { Write-Output '{"ok":false,"error":"conexion"}'; return }
        $hits = $r.hits | ForEach-Object { [ordered]@{ id=$_.project_id; titulo=$_.title; desc=$_.description; autor=$_.author; descargas=$_.downloads; icono=$_.icon_url } }
        (@{ ok=$true; resultados=@($hits) } | ConvertTo-Json -Depth 6 -Compress)
    }
    "instalar" {
        $u = "https://api.modrinth.com/v2/project/$ProjectId/version?loaders=%5B%22purpur%22,%22paper%22,%22spigot%22,%22bukkit%22%5D"
        try { $vs = Invoke-RestMethod $u -Headers $ua -TimeoutSec 15 } catch { Write-Output '{"ok":false,"error":"conexion"}'; return }
        if (-not $vs -or @($vs).Count -eq 0) { Write-Output '{"ok":false,"error":"sin-version-compatible"}'; return }
        $ver = @($vs)[0]
        $file = $ver.files | Where-Object { $_.primary } | Select-Object -First 1
        if (-not $file) { $file = $ver.files | Select-Object -First 1 }
        if (-not $file) { Write-Output '{"ok":false,"error":"sin-archivo"}'; return }
        if (-not (Test-Path $plugins)) { New-Item $plugins -ItemType Directory -Force | Out-Null }
        $dest = Join-Path $plugins $file.filename
        try { Invoke-WebRequest $file.url -OutFile $dest -Headers $ua -TimeoutSec 180 -UseBasicParsing } catch { Write-Output '{"ok":false,"error":"descarga"}'; return }
        (@{ ok=$true; archivo=$file.filename } | ConvertTo-Json -Compress)
    }
    "listar" {
        if (-not (Test-Path $plugins)) { Write-Output '{"ok":true,"plugins":[]}'; return }
        $list = Get-ChildItem $plugins -Filter *.jar -ErrorAction SilentlyContinue | ForEach-Object { [ordered]@{ nombre=$_.Name; mb=[math]::Round($_.Length/1MB,2) } }
        (@{ ok=$true; plugins=@($list) } | ConvertTo-Json -Depth 5 -Compress)
    }
    "eliminar" {
        $f = Join-Path $plugins $Nombre
        # Seguridad: asegurar que esta dentro de la carpeta plugins
        $full = [System.IO.Path]::GetFullPath($f)
        if (-not $full.StartsWith([System.IO.Path]::GetFullPath($plugins))) { Write-Output '{"ok":false,"error":"ruta-invalida"}'; return }
        if (Test-Path $full) { Remove-Item $full -Force; Write-Output '{"ok":true}' } else { Write-Output '{"ok":false,"error":"no-existe"}' }
    }
    default { Write-Output '{"ok":false,"error":"accion-desconocida"}' }
}
