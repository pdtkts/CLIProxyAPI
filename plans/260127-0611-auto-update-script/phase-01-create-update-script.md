# Phase 1: Create Update Scripts

## Context Links
- Plan: [Overview](./plan.md)
- Existing Build Scripts: `docker-build.sh`, `docker-build.ps1`

## Overview
**Priority:** High
**Status:** Planned
**Description:** Create scripts that detect git updates and trigger a rebuild.

## Requirements
1.  **Update Detection:**
    - Run `git fetch`.
    - Compare `HEAD` with `@{u}` (upstream).
2.  **Trigger Rebuild:**
    - If updates found: `git pull`.
    - Run `docker-build.sh` (or .ps1) with "Build from Source" option automatically selected (non-interactive mode if possible, or passing input).
    - Since existing scripts use `read` for input, we might need to modify them or pipe input.
    - **Optimization:** We can simply invoke the docker compose commands directly in the update script to avoid interactive prompts, duplicating the logic from "Option 2" of the build scripts to ensure automation.
3.  **Platform Support:**
    - Bash (Linux/macOS).
    - PowerShell (Windows).

## Implementation Steps

1.  **Create `auto-update.sh`:**
    - Shebang `#!/bin/bash`.
    - `git fetch origin`.
    - Check status: `LOCAL=$(git rev-parse @)`, `REMOTE=$(git rev-parse @{u})`.
    - If `$LOCAL != $REMOTE`:
        - `git pull`
        - Run build logic (Option 2 from `docker-build.sh`):
            - Get version info.
            - `docker compose build ...`
            - `docker compose up -d ...`
    - Else: Echo "Up to date".

2.  **Create `auto-update.ps1`:**
    - Similar logic in PowerShell.
    - `git fetch origin`
    - Compare hashes.
    - If changed:
        - `git pull`
        - Run build logic (Option 2 from `docker-build.ps1`).

## Todo List
- [ ] Create `auto-update.sh`
- [ ] Create `auto-update.ps1`
- [ ] Test scripts (simulate outdated branch).

## Success Criteria
- Running the script updates the repo and rebuilds the container if changes exist.
- Does nothing if already up-to-date.
