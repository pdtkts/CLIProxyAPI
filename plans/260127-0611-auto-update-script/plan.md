# Plan: Auto-Update Script

## Overview
This plan implements scripts (`auto-update.sh` and `auto-update.ps1`) to automatically check for git updates, pull them, and rebuild/restart the application using the existing build scripts. This allows the user to keep their local instance synchronized with the remote repository automatically.

## Phases

- [ ] **Phase 1: Create Update Scripts**
    - Implement `auto-update.sh` for Linux/macOS.
    - Implement `auto-update.ps1` for Windows.
    - Scripts will:
        1. Fetch origin.
        2. Check if local branch is behind remote.
        3. If behind: Pull changes, run build script (option 2 - Build from Source).
        4. If up-to-date: Do nothing.

## Dependencies
- Git installed and configured.
- Existing `docker-build.sh` and `docker-build.ps1`.
