# =====================================================
#  _rcon.ps1
#  Modulo RCON para comunicarse con Paper.
#  Envia comandos como /save-all y /stop.
# =====================================================

function Enviar-RCON {
    param(
        [string]$Comando,
        [string]$Servidor = "127.0.0.1",
        [int]$Puerto = $config.servidor.rcon_puerto,
        [string]$Password = $config.servidor.rcon_password
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $client.Connect($Servidor, $Puerto)
        $stream = $client.GetStream()
        $stream.ReadTimeout = 5000

        # Login packet (type 3)
        $loginPayload = Construir-PaqueteRCON -Id 1 -Tipo 3 -Body $Password
        $stream.Write($loginPayload, 0, $loginPayload.Length)
        Start-Sleep -Milliseconds 500

        $respLogin = Leer-PaqueteRCON -Stream $stream
        if ($respLogin.Id -eq -1) {
            Escribir-Log "RCON: password incorrecta." "ERROR"
            $client.Close()
            return $null
        }

        # Command packet (type 2)
        $cmdPayload = Construir-PaqueteRCON -Id 2 -Tipo 2 -Body $Comando
        $stream.Write($cmdPayload, 0, $cmdPayload.Length)
        Start-Sleep -Milliseconds 500

        $respCmd = Leer-PaqueteRCON -Stream $stream
        $client.Close()

        return $respCmd.Body
    } catch {
        Escribir-Log "RCON error: $_" "WARN"
        return $null
    }
}

function Construir-PaqueteRCON {
    param([int]$Id, [int]$Tipo, [string]$Body)

    $bodyBytes = [System.Text.Encoding]::ASCII.GetBytes($Body)
    $length = 4 + 4 + $bodyBytes.Length + 2  # id + type + body + 2 null bytes

    $packet = New-Object byte[] ($length + 4)  # +4 for the length field itself
    $ms = [System.IO.MemoryStream]::new($packet, $true)
    $bw = [System.IO.BinaryWriter]::new($ms)

    $bw.Write([int]$length)
    $bw.Write([int]$Id)
    $bw.Write([int]$Tipo)
    $bw.Write($bodyBytes)
    $bw.Write([byte]0)
    $bw.Write([byte]0)

    $bw.Close()
    return $packet
}

function Leer-PaqueteRCON {
    param($Stream)

    $header = New-Object byte[] 4
    $Stream.Read($header, 0, 4) | Out-Null
    $length = [BitConverter]::ToInt32($header, 0)

    $data = New-Object byte[] $length
    $totalRead = 0
    while ($totalRead -lt $length) {
        $read = $Stream.Read($data, $totalRead, $length - $totalRead)
        if ($read -eq 0) { break }
        $totalRead += $read
    }

    $id   = [BitConverter]::ToInt32($data, 0)
    $tipo = [BitConverter]::ToInt32($data, 4)
    $body = [System.Text.Encoding]::ASCII.GetString($data, 8, $length - 10)

    return @{ Id = $id; Tipo = $tipo; Body = $body }
}
