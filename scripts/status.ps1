
$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker-compose" }

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
$ErrorActionPreference = "Stop"

Write-Host "`n📊 Estado de Contenedores" -ForegroundColor Cyan
Write-Host "========================"

$composeFile = "docker-compose.generated.yml"
if (-not (Test-Path $composeFile)) {
    $composeFile = "docker-compose.yml"
}

$labComposeFiles = Get-ChildItem -Path suites -Recurse -Filter docker-compose.lab.yml -ErrorAction SilentlyContinue |
    Sort-Object FullName |
    ForEach-Object { "-f $($_.FullName)" }
$composeArgs = "-f $composeFile " + ($labComposeFiles -join " ")
$format = 'table {{.Name}}\t{{.Status}}\t{{.Ports}}'
$output = Invoke-Expression "$DOCKER_COMPOSE_BIN $composeArgs ps --format '$format'"

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
