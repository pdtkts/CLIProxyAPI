# Phase 1: Setup Sync Workflow

## Context Links
- Plan: [Overview](./plan.md)
- Fork: https://github.com/pdtkts/CLIProxyAPI
- Upstream: https://github.com/router-for-me/CLIProxyAPIPlus

## Overview
**Priority:** High
**Status:** Planned
**Description:** Create a GitHub Actions workflow to automatically sync the fork with the upstream repository.

## Requirements
1.  **Workflow Trigger:**
    - Schedule (e.g., every hour or day).
    - Manual trigger (`workflow_dispatch`).
2.  **Sync Logic:**
    - Fetch changes from `upstream/main`.
    - Merge or rebase into `origin/main`.
    - Push changes to `origin/main`.
3.  **Conflict Handling:**
    - If conflicts exist, the workflow should fail (notification via GitHub).

## Implementation Steps

1.  **Create Workflow File:**
    - Create `.github/workflows/sync-upstream.yml`.
    - Define `upstream_sync_repo` as `router-for-me/CLIProxyAPIPlus`.
    - Define `upstream_sync_branch` as `main`.
    - Define `target_sync_branch` as `main`.
    - Set schedule (e.g., `0 0 * * *` - daily).

2.  **Workflow Content:**
    - Use `actions/checkout` to checkout the fork.
    - Use a sync action (e.g., `aormsby/Fork-Sync-With-Upstream-action` or raw git commands). Given the requirements for simplicity and control, we will use raw git commands or a well-maintained action. We will use `git` commands for maximum control and "KISS".

3.  **Permissions:**
    - Ensure `contents: write` permission is set in the workflow.

## Todo List
- [ ] Create `.github/workflows/sync-upstream.yml`
- [ ] Commit and push the workflow

## Success Criteria
- Workflow appears in GitHub Actions tab.
- Manual trigger successfully syncs (or reports up-to-date).
- Scheduled trigger runs as expected.
