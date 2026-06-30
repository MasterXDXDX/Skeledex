# =====================================================
#  _nube_export.ps1
#  Lee del rclone.conf las credenciales de un remoto y
#  las devuelve en JSON, para el "codigo completo".
#  Uso: _nube_export.ps1 -Remoto <nombre>
# =====================================================
param([string]$Remoto)

$confPath = Join-Path $env:APPDATA "rclone\rclone.conf"
if (-not (Test-Path $confPath)) { Write-Output '{"ok":false,"error":"sin-conf"}'; return }

$lines = Get-Content $confPath
$inb = $false
$b = @{}
foreach ($l in $lines) {
    if ($l -match '^\[(.+)\]') { $inb = ($Matches[1] -eq $Remoto); continue }
    if ($inb -and $l -match '^\s*([^=#]+?)\s*=\s*(.+)$') { $b[$Matches[1].Trim()] = $Matches[2].Trim() }
}
if ($b.Count -eq 0) { Write-Output '{"ok":false,"error":"remoto-no-encontrado"}'; return }

$cuenta = if ($b.ContainsKey('account')) { $b['account'] } elseif ($b.ContainsKey('access_key_id')) { $b['access_key_id'] } else { '' }
$clave  = if ($b.ContainsKey('key')) { $b['key'] } elseif ($b.ContainsKey('secret_access_key')) { $b['secret_access_key'] } else { '' }

$out = [ordered]@{
    ok           = $true
    tipo         = $b['type']
    cuenta       = $cuenta
    clave        = $clave
    region       = if ($b.ContainsKey('region')) { $b['region'] } else { '' }
    endpoint     = if ($b.ContainsKey('endpoint')) { $b['endpoint'] } else { '' }
    proveedor_s3 = if ($b.ContainsKey('provider')) { $b['provider'] } else { '' }
}
$out | ConvertTo-Json -Compress
