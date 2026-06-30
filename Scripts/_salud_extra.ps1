# =====================================================
#  _salud_extra.ps1
#  Devuelve JSON con el estado de las herramientas:
#  { java, java_version, rclone, ram_libre_gb }
# =====================================================
$java = $false; $jver = ""
$javaExe = "java"
try {
    $rb = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $rutaConfiguracion = Join-Path $rb "Configuracion"
    . "$PSScriptRoot\_config_path.ps1"
    $cfg = Get-Content $archivoConfig -Raw | ConvertFrom-Json
    if ($cfg.servidor.java_exe) { $javaExe = $cfg.servidor.java_exe }
} catch {}
try {
    $o = & $javaExe -version 2>&1 | Out-String
    if ($o -match 'version "([^"]+)"') { $java = $true; $jver = $Matches[1] }
    elseif ($o -match 'version') { $java = $true }
} catch {}

$rclone = (Test-Path 'C:\rclone\rclone.exe') -or [bool](Get-Command rclone -ErrorAction SilentlyContinue)

# Playit instalado?
$playit = $false
try {
    $rbp = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $playit = (Test-Path (Join-Path $rbp "playit.exe")) -or (Test-Path "C:\Program Files\playit_gg\bin\playit.exe")
} catch {}

# Hay un .jar en la instancia activa?
$jar = $false
try {
    $rb2 = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $cfg2 = Get-Content $archivoConfig -Raw | ConvertFrom-Json
    $carp = if ($cfg2.servidor.carpeta_instancia) { $cfg2.servidor.carpeta_instancia } else { "Instancia" }
    $inst = Join-Path $rb2 $carp
    if (Test-Path $inst) { $jar = [bool](Get-ChildItem $inst -Filter *.jar -ErrorAction SilentlyContinue | Select-Object -First 1) }
} catch {}

$ramLibre = 0.0
$ramTotal = 0.0
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { $ramLibre = [math]::Round($os.FreePhysicalMemory / 1MB, 1); $ramTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1) }
} catch {}

@{ java = $java; java_version = $jver; rclone = $rclone; jar = $jar; playit = $playit; ram_libre_gb = $ramLibre; ram_total_gb = $ramTotal } | ConvertTo-Json -Compress
