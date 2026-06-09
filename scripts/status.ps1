$ErrorActionPreference = "Stop"

Write-Host "`n📊 Estado de Contenedores" -ForegroundColor Cyan
Write-Host "========================"

$composeFile = "docker-compose.generated.yml"
if (-not (Test-Path $composeFile)) {
    $composeFile = "docker-compose.yml"
}

$output = docker compose -f $composeFile ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

foreach ($line in $output) {
    # Remove IPv4 bindings and destination ports
    $line = $line -replace '0\.0\.0\.0:', ''
    $line = $line -replace '->[0-9-]*\/tcp', ''
    # Remove IPv6 bindings
    $line = $line -replace ', \[::\]:[0-9-]*', ''
    # Remove remaining /tcp labels for unmapped ports (like 6379)
    $line = $line -replace ', [0-9]*\/tcp', ''
    
    Write-Host $line
}
