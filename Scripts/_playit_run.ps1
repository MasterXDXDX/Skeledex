# =====================================================
#  _playit_run.ps1
#  Abre Playit en una ventana visible para vincular el
#  tunel (la 1a vez muestra un enlace para autorizar).
#  Salida: OK | NO-INSTALADO
# =====================================================
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$p = Join-Path $rutaBase "playit.exe"
if (-not (Test-Path $p)) { $p = "C:\Program Files\playit_gg\bin\playit.exe" }
if (Test-Path $p) {
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", "`"$p`""
    Write-Output "OK"
} else {
    Start-Process "https://playit.gg/download"
    Write-Output "NO-INSTALADO"
}
