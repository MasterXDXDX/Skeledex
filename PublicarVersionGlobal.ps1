# =====================================================
#  PublicarVersionGlobal.ps1  (SOLO DEVELOPER)
#  Empaqueta Scripts + .exe en un .zip de release, sube
#  la version a GitHub (si tienes 'gh') o te da los pasos.
#  Todas las instalaciones la reciben por el canal central.
#  Uso:  PowerShell -File PublicarVersionGlobal.ps1 [-Version 1.2.3]
# =====================================================
param([string]$Version = "")

$rutaBase    = Split-Path -Parent $MyInvocation.MyCommand.Path
$rutaScripts = Join-Path $rutaBase "Scripts"
$exe         = Join-Path $rutaBase "Skeledex.exe"
if (-not (Test-Path $exe)) { $exe = Join-Path $rutaBase "ServidorTecnico.exe" }

# Config (en %APPDATA%)
$archivoCfg = Join-Path $env:APPDATA "Skeledex\config.json"
if (-not (Test-Path $archivoCfg)) { $archivoCfg = Join-Path $rutaBase "Configuracion\config.json" }
$config = Get-Content $archivoCfg -Raw | ConvertFrom-Json

$repo = $config.actualizaciones.repo
if (-not $repo) { Write-Host "ERROR: No has configurado tu repositorio en Ajustes > Actualizaciones." -ForegroundColor Red; exit 1 }

# Calcular nueva version (auto-bump del patch si no se pasa)
$actual = "$($config.identidad.version_sistema)"
if (-not $Version) {
    $p = ($actual -replace '[^0-9.]','').Split('.')
    while ($p.Count -lt 3) { $p += '0' }
    $p[2] = [string]([int]$p[2] + 1)
    $Version = ($p -join '.')
}
Write-Host ""
Write-Host "  Version actual: $actual  ->  nueva: $Version" -ForegroundColor Cyan
Write-Host "  Repositorio: $repo" -ForegroundColor Cyan
Write-Host ""

# El asset es el .exe directamente (autocontenido: lleva los scripts dentro)
if (-not (Test-Path $exe)) { Write-Host "ERROR: no encuentro el .exe ($exe)." -ForegroundColor Red; exit 1 }
$asset = Join-Path $rutaBase "Skeledex.exe"
if ($exe -ne $asset) { Copy-Item $exe $asset -Force }
Write-Host "  Asset: $asset ($([math]::Round((Get-Item $asset).Length/1MB,1)) MB)" -ForegroundColor Green

# Subir la version local del config del developer (para que no se "autoactualice" a si mismo)
$config.identidad.version_sistema = $Version
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($archivoCfg, ($config | ConvertTo-Json -Depth 8), $utf8)

# Publicar
$ghCmd = Get-Command gh -ErrorAction SilentlyContinue
$ghExe = if ($ghCmd) { $ghCmd.Source } elseif (Test-Path "C:\Program Files\GitHub CLI\gh.exe") { "C:\Program Files\GitHub CLI\gh.exe" } elseif (Test-Path "C:\Program Files (x86)\GitHub CLI\gh.exe") { "C:\Program Files (x86)\GitHub CLI\gh.exe" } else { $null }
$gh = $ghExe
if ($gh) {
    Write-Host "  Subiendo release v$Version a GitHub con gh..." -ForegroundColor Cyan
    & $ghExe release create "v$Version" $asset -R $repo -t "Skeledex v$Version" -n "Actualizacion automatica de Skeledex v$Version" --target main 2>&1 | Write-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "  LISTO! Todos los paneles recibiran v$Version al abrirse." -ForegroundColor Green
    } else {
        Write-Host "  gh fallo. Sube el zip manualmente (ver pasos abajo)." -ForegroundColor Yellow
        $gh = $null
    }
}
if (-not $gh) {
    Write-Host ""
    Write-Host "  ----- PASOS PARA PUBLICAR (una vez) -----" -ForegroundColor Yellow
    Write-Host "  1) Entra a: https://github.com/$repo/releases/new"
    Write-Host "  2) Tag version:  v$Version"
    Write-Host "  3) Arrastra el archivo:  $asset"
    Write-Host "  4) Publica la release."
    Write-Host ""
    Write-Host "  (Tip: instala GitHub CLI 'gh' una vez y la proxima sera automatica.)" -ForegroundColor Gray
    try { Start-Process "https://github.com/$repo/releases/new" } catch {}
}
Write-Host ""
