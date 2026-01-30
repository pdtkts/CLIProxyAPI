# Auto Update CLIProxyAPI from upstream
# Usage: .\auto-update.ps1

$ErrorActionPreference = "Stop"
$UPSTREAM = "https://github.com/router-for-me/CLIProxyAPI.git"

Write-Host "=== CLIProxyAPI Auto Update ===" -ForegroundColor Cyan

# Add or update upstream remote
$remotes = git remote
if ($remotes -notcontains "upstream") {
    Write-Host "Adding upstream remote..." -ForegroundColor Yellow
    git remote add upstream $UPSTREAM
} else {
    # Ensure upstream URL is correct
    $currentUrl = git remote get-url upstream
    if ($currentUrl -ne $UPSTREAM) {
        Write-Host "Updating upstream URL..." -ForegroundColor Yellow
        git remote set-url upstream $UPSTREAM
    }
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
$mergeResult = git merge upstream/main --no-edit 2>&1
if ($LASTEXITCODE -ne 0) {
    # Check if there are unmerged files (conflicts)
    $unmerged = git diff --name-only --diff-filter=U
    if ($unmerged) {
        Write-Host "Merge conflict detected in files:" -ForegroundColor Red
        Write-Host $unmerged -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Please resolve conflicts manually, then run:" -ForegroundColor Cyan
        Write-Host "  git add <resolved-files>" -ForegroundColor White
        Write-Host "  git commit" -ForegroundColor White
        Write-Host "  .\auto-update.ps1" -ForegroundColor White
        exit 1
    }
    Write-Host "Merge failed: $mergeResult" -ForegroundColor Red
    exit 1
}

# Push to origin
Write-Host "Pushing to origin..." -ForegroundColor Yellow
git push origin main

# Rebuild Docker
Write-Host "Rebuilding Docker image..." -ForegroundColor Yellow
docker-compose build --no-cache

# Clean up old/dangling images
Write-Host "Cleaning up old images..." -ForegroundColor Yellow
docker image prune -f

# Restart container
Write-Host "Restarting container..." -ForegroundColor Yellow
docker-compose down
docker-compose up -d

# Show logs
Write-Host "=== Container Logs ===" -ForegroundColor Cyan
Start-Sleep -Seconds 3
docker logs cli-proxy-api --tail 10

Write-Host "=== Update Complete! ===" -ForegroundColor Green
