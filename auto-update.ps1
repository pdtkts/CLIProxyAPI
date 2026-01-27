# Auto Update CLIProxyAPI from upstream
# Usage: .\auto-update.ps1

$ErrorActionPreference = "Stop"
$UPSTREAM = "https://github.com/router-for-me/CLIProxyAPIPlus.git"

Write-Host "=== CLIProxyAPI Auto Update ===" -ForegroundColor Cyan

# Add upstream if not exists
$remotes = git remote
if ($remotes -notcontains "upstream") {
    Write-Host "Adding upstream remote..." -ForegroundColor Yellow
    git remote add upstream $UPSTREAM
}

# Fetch upstream
Write-Host "Fetching upstream..." -ForegroundColor Yellow
git fetch upstream

# Check for updates
$commits = git rev-list HEAD..upstream/main --count
if ($commits -eq 0) {
    Write-Host "Already up to date!" -ForegroundColor Green
    exit 0
}

Write-Host "Found $commits new commits from upstream" -ForegroundColor Yellow

# Merge upstream
Write-Host "Merging upstream/main..." -ForegroundColor Yellow
git merge upstream/main --no-edit

# Push to origin
Write-Host "Pushing to origin..." -ForegroundColor Yellow
git push origin main

# Rebuild Docker
Write-Host "Rebuilding Docker image..." -ForegroundColor Yellow
docker-compose build --no-cache

# Restart container
Write-Host "Restarting container..." -ForegroundColor Yellow
docker-compose down
docker-compose up -d

# Show logs
Write-Host "=== Container Logs ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3
docker logs cli-proxy-api-plus --tail 10

Write-Host "=== Update Complete! ===" -ForegroundColor Green
