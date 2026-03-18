param(
    [int]$SHARDS = 3
)
if ($env:SHARDS) { $SHARDS = $env:SHARDS }
$TOTAL_NODES = $SHARDS * 2

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "El script debe ejecutarse como Administrador para modificar el archivo hosts."
    Exit 1
}

$hostsFile = "$env:windir\System32\drivers\etc\hosts"
$backupPath = "$hostsFile.original"

$nuevosHosts = "`n# --- Redis Cluster Lab (inicio) ---`n"

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $nuevosHosts += "127.0.0.1   redis-node-$i`n"
}

$nuevosHosts += "127.0.0.1   master.local`n"
$nuevosHosts += "127.0.0.1   clustercfg.local`n"
$nuevosHosts += "# --- Redis Cluster Lab (fin) ---`n"

Write-Host "🌐 Configurando hosts en $hostsFile..."

if (Test-Path $backupPath) {
    Write-Host "⚠️  Ya existe un respaldo en $backupPath."
    Write-Host "   Restaurando primero antes de re-aplicar..."
    Move-Item -Path $backupPath -Destination $hostsFile -Force
}

Copy-Item -Path $hostsFile -Destination $backupPath

Add-Content -Path $hostsFile -Value $nuevosHosts -Encoding Ascii

Write-Host "✅ Hosts del cluster agregados a hosts file"
