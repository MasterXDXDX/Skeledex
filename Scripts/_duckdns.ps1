# =====================================================
#  _duckdns.ps1
#  Modulo opcional de DNS dinamico (DuckDNS).
#  Actualiza el dominio con la IP publica actual.
# =====================================================

function Actualizar-DuckDNS {
    if ($config.red.metodo -ne "duckdns") { return }
    $dominio = $config.red.duckdns_dominio
    $token = $config.red.duckdns_token
    if ([string]::IsNullOrWhiteSpace($dominio) -or [string]::IsNullOrWhiteSpace($token)) {
        Escribir-Log "DuckDNS habilitado pero falta dominio o token." "WARN"
        return
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $url = "https://www.duckdns.org/update?domains=$dominio&token=$token&ip="
    try {
        $resp = Invoke-RestMethod -Uri $url -TimeoutSec 15
        if ($resp -match "OK") {
            Escribir-Log "DuckDNS actualizado: $dominio.duckdns.org" "OK"
        } else {
            Escribir-Log "DuckDNS respondio: $resp" "WARN"
        }
    } catch {
        Escribir-Log "Error actualizando DuckDNS: $_" "WARN"
    }
}
