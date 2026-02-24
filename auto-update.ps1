# Auto Update CLIProxyAPI Docker Image
# Usage: .\auto-update.ps1 [-force]
# -force: Force restart even if no update

param(
    [Alias("f")]
    [switch]$force
)

# Also support --force syntax
if ($args -contains "--force" -or $args -contains "-f") {
    $force = $true
}

$ErrorActionPreference = "Stop"
$IMAGE = if ($env:CLI_PROXY_IMAGE) { $env:CLI_PROXY_IMAGE } else { "eceasy/cli-proxy-api:latest" }

Write-Host "=== CLIProxyAPI Auto Update ===" -ForegroundColor Cyan
Write-Host "Image: $IMAGE" -ForegroundColor Gray
if ($force) {
    Write-Host "[Force mode] Will restart regardless" -ForegroundColor Magenta
}

# Get current image ID (if exists)
$currentId = docker images -q $IMAGE 2>$null

# Pull latest image
Write-Host "Pulling latest image..." -ForegroundColor Yellow
docker pull $IMAGE
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to pull image!" -ForegroundColor Red
    exit 1
}

# Get new image ID
$newId = docker images -q $IMAGE

# Check if update is needed
if ($currentId -eq $newId -and -not $force) {
    Write-Host "Already up to date!" -ForegroundColor Green
    Write-Host "Use --force to restart anyway" -ForegroundColor Gray
    exit 0
}

if ($currentId -ne $newId) {
    Write-Host "New image downloaded!" -ForegroundColor Green
} else {
    Write-Host "No new image, but --force specified" -ForegroundColor Yellow
}

# Restart container with new image
Write-Host "Restarting container..." -ForegroundColor Yellow
docker-compose down
docker-compose up -d

# Clean up old images
Write-Host "Cleaning up old images..." -ForegroundColor Yellow
docker image prune -f

# Show logs
Write-Host "=== Container Logs ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3
docker logs cli-proxy-api --tail 10

Write-Host "=== Update Complete! ===" -ForegroundColor Green
