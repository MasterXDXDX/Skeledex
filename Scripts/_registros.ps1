# =====================================================
#  _registros.ps1
#  Modulo de logging del sistema.
#  Todos los demas modulos dependen de este.
#  NO EDITAR salvo para cambiar formato de logs.
# =====================================================

function Escribir-Log {
    param(
        [string]$Mensaje,
        [ValidateSet("INFO","OK","WARN","ERROR","SISTEMA")]
        [string]$Nivel = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "[$timestamp] [$Nivel] $Mensaje"

    # Mostrar en consola con color segun nivel
    switch ($Nivel) {
        "OK"      { Write-Host $linea -ForegroundColor Green }
        "WARN"    { Write-Host $linea -ForegroundColor Yellow }
        "ERROR"   { Write-Host $linea -ForegroundColor Red }
        "SISTEMA" { Write-Host $linea -ForegroundColor Cyan }
        default   { Write-Host $linea -ForegroundColor White }
    }

    # Escribir en archivo de registro del dia
    $fecha = Get-Date -Format "yyyy-MM-dd"
    $archivoLog = Join-Path $rutaRegistros "registro_$fecha.log"

    try {
        Add-Content -Path $archivoLog -Value $linea -Encoding UTF8
    } catch {
        Write-Host "[ERROR] No se pudo escribir en el archivo de log: $_" -ForegroundColor Red
    }
}

function Escribir-Separador {
    param([string]$Titulo = "")
    $linea = "=" * 55
    if ($Titulo) {
        Escribir-Log "  $Titulo  " "SISTEMA"
    }
    Escribir-Log $linea "SISTEMA"
}

# Escribe texto a un archivo en UTF-8 SIN BOM (evita romper JSON.parse en otros lectores)
function Guardar-TextoSinBOM {
    param(
        [string]$Ruta,
        [string]$Contenido
    )
    $utf8SinBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Ruta, $Contenido, $utf8SinBom)
}
