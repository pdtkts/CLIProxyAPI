# Phase 05: Token Refresh Fallback

## Context Links
- Claude executor refresh: `internal/runtime/executor/claude_executor.go` -> `Refresh()` (line 493)
- Existing refresh logic: `internal/auth/claude/anthropic_auth.go` -> `RefreshTokens()` (line 221)
- Token storage: `internal/auth/claude/token.go`
- Auth metadata flow: `sdk/cliproxy/auth` package

## Overview
- **Priority:** P2
- **Status:** pending
- **Effort:** 1.5h
- **Description:** When `RefreshTokens()` fails in the Claude executor, check if the auth metadata contains a cookie. If yes, re-run the full cookie->OAuth flow to obtain fresh tokens. Single retry only (prevent auth loop).

## Key Insights

### Current Refresh Flow (claude_executor.go:493-525)
```go
func (e *ClaudeExecutor) Refresh(ctx, auth) (*cliproxyauth.Auth, error) {
    refreshToken := auth.Metadata["refresh_token"]
    svc := claudeauth.NewClaudeAuth(e.cfg)
    td, err := svc.RefreshTokens(ctx, refreshToken)
    if err != nil {
        return nil, err  // <-- Currently fails here with no fallback
    }
    // Update metadata with new tokens...
}
```

### Desired Flow
```
RefreshTokens(refreshToken) fails
  |
  v
Check: auth.Metadata["cookie"] exists and non-empty?
  |-> No:  return original error (current behavior)
  |-> Yes: AuthenticateWithCookie(ctx, cookie)
            |-> Success: update auth.Metadata with new tokens + return
            |-> Failure: return original refresh error
```

### Auth Metadata Keys
The executor reads/writes these metadata keys:
- `access_token`, `refresh_token`, `email`, `expired`, `type`, `last_refresh`
- New keys from cookie auth: `cookie`, `organization_uuid`, `capabilities`
- These are populated when saving via Management API (Phase 04) or loaded from file

### Token File Update After Re-auth
After successful cookie re-auth, the new tokens must be persisted back to the auth file. The executor's `Refresh()` method returns updated `*cliproxyauth.Auth` which the runtime saves automatically. But we also need to ensure the cookie, org UUID, and capabilities are preserved in metadata.

## Requirements

### Functional
- On refresh failure, attempt cookie-based re-auth if cookie exists in metadata
- Update all token fields (access, refresh, expire, last_refresh) on success
- Preserve cookie, org UUID, capabilities in metadata
- Single retry only (if cookie re-auth fails, return error)

### Non-Functional
- Minimal changes to existing Refresh() function
- No import cycle concerns (cookie_auth.go is in same package)
- Log warning when falling back to cookie re-auth
- Log error when cookie re-auth also fails

## Architecture

```
ClaudeExecutor.Refresh(ctx, auth)
  |
  |-> Extract refreshToken from metadata
  |-> RefreshTokens(ctx, refreshToken)
  |     |-> Success: update metadata, return
  |     |-> Failure: continue to fallback
  |
  |-> Extract cookie from metadata
  |     |-> Empty: return original error
  |
  |-> log.Warn("refresh failed, attempting cookie re-auth")
  |-> NewCookieAuthService(cfg).AuthenticateWithCookie(ctx, cookie)
  |     |-> Failure: return original refresh error
  |
  |-> Update metadata with new tokens from cookie auth
  |-> Return updated auth
```

## Related Code Files
- **Modify:** `internal/runtime/executor/claude_executor.go` -> `Refresh()` method

## Implementation Steps

1. Modify the `Refresh()` method in `claude_executor.go` (lines 493-525):

```go
func (e *ClaudeExecutor) Refresh(ctx context.Context, auth *cliproxyauth.Auth) (*cliproxyauth.Auth, error) {
    log.Debugf("claude executor: refresh called")
    if auth == nil {
        return nil, fmt.Errorf("claude executor: auth is nil")
    }
    var refreshToken string
    if auth.Metadata != nil {
        if v, ok := auth.Metadata["refresh_token"].(string); ok && v != "" {
            refreshToken = v
        }
    }
    if refreshToken == "" {
        return auth, nil
    }
    svc := claudeauth.NewClaudeAuth(e.cfg)
    td, err := svc.RefreshTokens(ctx, refreshToken)
    if err != nil {
        // Fallback: attempt cookie-based re-authentication
        td, fallbackErr := e.attemptCookieReauth(ctx, auth)
        if fallbackErr != nil {
            // Cookie re-auth also failed; return original refresh error
            log.Warnf("claude executor: cookie re-auth fallback also failed: %v", fallbackErr)
            return nil, err
        }
        // Cookie re-auth succeeded; use those tokens
        log.Infof("claude executor: cookie re-auth succeeded for %s", td.Email)
        err = nil
        // Fall through to metadata update below
        if auth.Metadata == nil {
            auth.Metadata = make(map[string]any)
        }
        auth.Metadata["access_token"] = td.AccessToken
        if td.RefreshToken != "" {
            auth.Metadata["refresh_token"] = td.RefreshToken
        }
        auth.Metadata["email"] = td.Email
        auth.Metadata["expired"] = td.Expire
        auth.Metadata["type"] = "claude"
        auth.Metadata["last_refresh"] = time.Now().Format(time.RFC3339)
        return auth, nil
    }
    if auth.Metadata == nil {
        auth.Metadata = make(map[string]any)
    }
    auth.Metadata["access_token"] = td.AccessToken
    if td.RefreshToken != "" {
        auth.Metadata["refresh_token"] = td.RefreshToken
    }
    auth.Metadata["email"] = td.Email
    auth.Metadata["expired"] = td.Expire
    auth.Metadata["type"] = "claude"
    now := time.Now().Format(time.RFC3339)
    auth.Metadata["last_refresh"] = now
    return auth, nil
}
```

2. Add helper method `attemptCookieReauth` to `ClaudeExecutor`:

```go
// attemptCookieReauth tries to re-authenticate using a stored cookie
// when the normal refresh token flow fails. Returns nil if no cookie
// is available or if cookie re-auth fails.
func (e *ClaudeExecutor) attemptCookieReauth(ctx context.Context, auth *cliproxyauth.Auth) (*claudeauth.ClaudeTokenData, error) {
    if auth.Metadata == nil {
        return nil, fmt.Errorf("no metadata available")
    }

    cookie, ok := auth.Metadata["cookie"].(string)
    if !ok || strings.TrimSpace(cookie) == "" {
        return nil, fmt.Errorf("no cookie stored for re-authentication")
    }

    log.Warnf("claude executor: refresh token expired, attempting cookie re-auth")

    svc := claudeauth.NewCookieAuthService(e.cfg)
    tokenStorage, err := svc.AuthenticateWithCookie(ctx, cookie)
    if err != nil {
        return nil, fmt.Errorf("cookie re-auth failed: %w", err)
    }

    return &claudeauth.ClaudeTokenData{
        AccessToken:  tokenStorage.AccessToken,
        RefreshToken: tokenStorage.RefreshToken,
        Email:        tokenStorage.Email,
        Expire:       tokenStorage.Expire,
    }, nil
}
```

3. Ensure the import for `claudeauth` already exists (it does at line 18):
   ```go
   claudeauth "github.com/router-for-me/CLIProxyAPI/v6/internal/auth/claude"
   ```

4. Verify compilation: `go build ./internal/runtime/executor/...`

5. Verify existing tests: `go test ./internal/runtime/executor/...`

## Todo List
- [ ] Add `attemptCookieReauth` method to ClaudeExecutor
- [ ] Modify `Refresh()` to call `attemptCookieReauth` on refresh failure
- [ ] Ensure cookie/org_uuid/capabilities preserved in metadata after re-auth
- [ ] Verify compilation
- [ ] Verify existing tests pass
- [ ] Manual test: expire a refresh token and verify cookie re-auth triggers

## Success Criteria
- Normal refresh flow unchanged (fast path still works)
- When refresh fails AND cookie exists in metadata: cookie re-auth is attempted
- When refresh fails AND no cookie: original error returned (no regression)
- When cookie re-auth succeeds: new tokens returned in metadata
- When cookie re-auth fails: original refresh error returned (not cookie error)
- No auth loop (single fallback attempt only)

## Risk Assessment
| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Cookie expired when re-auth attempted | Medium | Medium | Return original error; user must re-add account |
| Auth loop (re-auth triggers refresh which triggers re-auth) | High | Low | Single attempt in Refresh(); attemptCookieReauth returns ClaudeTokenData, not auth object |
| Metadata key mismatch | Medium | Low | Use same keys as existing Refresh() code |

## Security Considerations
- Cookie read from metadata (already stored in auth file)
- No additional exposure; cookie is already persisted
- Cookie only sent to claude.ai domain during re-auth (same as initial flow)

## Next Steps
- Consider adding cookie update in metadata after re-auth (cookie itself doesn't change, but org UUID or capabilities might)
- Monitor re-auth frequency in production logs to detect cookie expiry patterns

## Unresolved Questions
<!-- Updated: Validation Session 1 - verify runtime persistence during implementation -->
- **[Verify during implementation]** Should we update the auth JSON file on disk after successful cookie re-auth? The runtime saves the updated `*cliproxyauth.Auth` back, but we should verify this includes the `cookie` metadata key. If the runtime only saves changed keys, the cookie might be lost. Need to verify the runtime's auth persistence behavior.
- **Decision:** Verify runtime behavior first. If cookie gets lost after re-auth, add explicit file save in Refresh().
