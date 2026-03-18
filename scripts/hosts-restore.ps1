$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "El script debe ejecutarse como Administrador para restaurar el archivo hosts."
    Exit 1
}

$hostsFile = "$env:windir\System32\drivers\etc\hosts"
$backupPath = "$hostsFile.original"

Write-Host "🌐 Restaurando hosts en $hostsFile..."

if (-not (Test-Path $backupPath)) {
    Write-Host "ℹ️  No se encontró respaldo ($backupPath). Archivo hosts no fue modificado."
    Exit 0
}

Move-Item -Path $backupPath -Destination $hostsFile -Force

Write-Host "✅ hosts file restaurado a su estado original"
