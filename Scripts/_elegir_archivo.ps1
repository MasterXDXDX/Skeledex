# =====================================================
#  _elegir_archivo.ps1
#  Abre el explorador de Windows para elegir un archivo.
#  Devuelve la ruta seleccionada (o vacio si cancela).
#  Uso: -Filtro "Archivos JAR (*.jar)|*.jar" -Titulo "..." -Inicial "C:\..."
# =====================================================
param(
    [string]$Filtro = "Todos (*.*)|*.*",
    [string]$Titulo = "Selecciona un archivo",
    [string]$Inicial = ""
)
Add-Type -AssemblyName System.Windows.Forms | Out-Null
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Title = $Titulo
$dlg.Filter = $Filtro
if ($Inicial -and (Test-Path $Inicial)) { $dlg.InitialDirectory = $Inicial }
# Form duenia con TopMost para que el dialogo salga al frente
$owner = New-Object System.Windows.Forms.Form
$owner.TopMost = $true
$owner.ShowInTaskbar = $false
$owner.Opacity = 0
$res = $dlg.ShowDialog($owner)
$owner.Dispose()
if ($res -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $dlg.FileName } else { Write-Output "" }
