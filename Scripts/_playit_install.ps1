# =====================================================
#  _playit_install.ps1
#  Descarga el agente de Playit (tunel sin abrir puertos)
#  a la carpeta del programa (base\playit.exe).
#  Salida JSON: { ok, ruta } | { ok:false, error }
# =====================================================
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dest = Join-Path $rutaBase "playit.exe"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ua = @{ 'User-Agent' = 'Skeledex' }
$url = "https://github.com/playit-cloud/playit-agent/releases/latest/download/playit-windows-x86_64-signed.exe"
try {
    Invoke-WebRequest $url -OutFile $dest -UseBasicParsing -TimeoutSec 300 -Headers $ua
} catch { Write-Output '{"ok":false,"error":"descarga"}'; return }
if (Test-Path $dest) { (@{ ok = $true; ruta = $dest } | ConvertTo-Json -Compress) }
else { Write-Output '{"ok":false,"error":"no-quedo"}' }
