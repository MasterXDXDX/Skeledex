# =====================================================
#  _java_install.ps1
#  Descarga e instala un JRE portable (Adoptium Temurin)
#  dentro de la carpeta del programa (base\jre). Devuelve
#  la ruta de java.exe para usarla como java_exe.
#  Salida JSON: { ok, java } | { ok:false, error }
# =====================================================
param([string]$Version = "21")
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dest = Join-Path $rutaBase "jre"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = @{ 'User-Agent' = 'Skeledex' }
$url = "https://api.adoptium.net/v3/binary/latest/$Version/ga/windows/x64/jre/hotspot/normal/eclipse"
$zip = Join-Path $env:TEMP "skeledex_jre.zip"
$tmp = Join-Path $env:TEMP "skeledex_jre_x"
try {
    Invoke-WebRequest $url -OutFile $zip -UseBasicParsing -TimeoutSec 600 -Headers $ua
} catch { Write-Output '{"ok":false,"error":"descarga"}'; return }
if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
try { Expand-Archive $zip $tmp -Force } catch { Write-Output '{"ok":false,"error":"zip"}'; return }
$java = Get-ChildItem $tmp -Recurse -Filter "java.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $java) { Write-Output '{"ok":false,"error":"sin-java"}'; return }
# La raiz del JRE es el padre de 'bin'
$jreRoot = $java.Directory.Parent.FullName
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue }
try { Move-Item $jreRoot $dest -Force } catch { Copy-Item $jreRoot $dest -Recurse -Force }
Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
$javaPath = Join-Path $dest "bin\java.exe"
if (Test-Path $javaPath) { (@{ ok = $true; java = $javaPath } | ConvertTo-Json -Compress) }
else { Write-Output '{"ok":false,"error":"no-quedo"}' }
