# =====================================================
#  _nube_conectar.ps1
#  Genera rclone.conf para el proveedor elegido y prueba la conexion.
#  Lee credenciales desde un JSON temporal (escrito por el panel),
#  asi no quedan en logs ni en config.json.
#  Temp esperado: %TEMP%\st_nube.json
#    { tipo, remoto, bucket, cuenta, clave, region, endpoint }
#  tipo: b2 | s3
#  Salida: OK | ERROR:<motivo>
# =====================================================
$rclone = "C:\rclone\rclone.exe"
if (-not (Test-Path $rclone)) {
    # Auto-instalar rclone si no esta (asi el usuario no necesita instaladores)
    try {
        $url = 'https://downloads.rclone.org/current/rclone-current-windows-amd64.zip'
        $zip = Join-Path $env:TEMP 'rclone.zip'
        $tmp = Join-Path $env:TEMP 'rclone_tmp'
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Path 'C:\rclone' -Force | Out-Null
        Get-ChildItem $tmp -Recurse -Filter 'rclone.exe' | Select-Object -First 1 | Copy-Item -Destination 'C:\rclone'
        Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
    } catch {}
    if (Test-Path 'C:\rclone\rclone.exe') { $rclone = 'C:\rclone\rclone.exe' } else { $rclone = 'rclone' }
}
$rutaBase = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$tmp = Join-Path $rutaBase "Estado\_nube_tmp.json"
if (-not (Test-Path $tmp)) { Write-Output "ERROR:sin-datos"; return }

try { $d = Get-Content $tmp -Raw | ConvertFrom-Json } catch { Write-Output "ERROR:json"; return }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

$remoto = $d.remoto
if (-not $remoto) { Write-Output "ERROR:remoto-vacio"; return }

# Construir bloque de configuracion segun tipo
$lineas = @("[$remoto]")
switch ($d.tipo) {
    "b2" {
        $lineas += "type = b2"
        $lineas += "account = $($d.cuenta)"
        $lineas += "key = $($d.clave)"
        $lineas += "hard_delete = false"
    }
    "s3" {
        $lineas += "type = s3"
        $lineas += "provider = $($d.proveedor_s3)"
        $lineas += "access_key_id = $($d.cuenta)"
        $lineas += "secret_access_key = $($d.clave)"
        if ($d.region)   { $lineas += "region = $($d.region)" }
        if ($d.endpoint) { $lineas += "endpoint = $($d.endpoint)" }
    }
    default { Write-Output "ERROR:tipo-no-soportado"; return }
}

# Ubicacion de rclone.conf
$confPath = & $rclone config file 2>$null | Select-String -Pattern "rclone.conf" | ForEach-Object { $_.Line.Trim() } | Select-Object -Last 1
if (-not $confPath -or -not (Test-Path (Split-Path $confPath -ErrorAction SilentlyContinue) -ErrorAction SilentlyContinue)) {
    $confPath = Join-Path $env:APPDATA "rclone\rclone.conf"
}
$dir = Split-Path $confPath
if (-not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }

# Leer conf existente, quitar bloque previo del mismo remoto, agregar el nuevo
$existente = @()
if (Test-Path $confPath) { $existente = Get-Content $confPath }
$nuevo = New-Object System.Collections.Generic.List[string]
$saltando = $false
foreach ($l in $existente) {
    if ($l -match '^\[(.+)\]') {
        $saltando = ($Matches[1] -eq $remoto)
    }
    if (-not $saltando) { $nuevo.Add($l) }
}
if ($nuevo.Count -gt 0 -and $nuevo[$nuevo.Count-1].Trim() -ne "") { $nuevo.Add("") }
foreach ($l in $lineas) { $nuevo.Add($l) }

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($confPath, ($nuevo -join "`n") + "`n", $utf8)

# Probar conexion
$bucket = $d.bucket
& $rclone lsd "${remoto}:${bucket}" 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { Write-Output "OK" } else {
    # Intentar crear el bucket si no existe
    & $rclone mkdir "${remoto}:${bucket}" 2>$null | Out-Null
    & $rclone lsd "${remoto}:${bucket}" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { Write-Output "OK" } else { Write-Output "ERROR:conexion" }
}
