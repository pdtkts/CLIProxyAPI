# Phase 04: Management API Endpoint

## Context Links
- Pattern to follow: `internal/api/handlers/management/auth_files.go` -> `RequestIFlowCookieToken` (line 1906)
- Route registration: `internal/api/server.go` -> `registerManagementRoutes()` (line 631)
- Token save: `saveTokenRecord` (line 940 in auth_files.go)
- Core auth types: `sdk/cliproxy/auth` package

## Overview
- **Priority:** P2
- **Status:** pending
- **Effort:** 1h
- **Description:** Add Management API endpoint `POST /v0/management/claude-cookie` that accepts a cookie via JSON body, authenticates via cookie->OAuth flow, saves the token file, and returns account info. Follows `RequestIFlowCookieToken` pattern.

## Key Insights
- Management API uses gin framework with JSON request/response
- Auth files handler (`Handler`) has `cfg *config.Config` and `saveTokenRecord` method
- `saveTokenRecord` accepts `*coreauth.Auth` record and persists via token store
- Route pattern: endpoint registered at `/v0/management/{path}` in `server.go`
- iFlow cookie endpoint is `POST /v0/management/iflow-auth-url` (reuses same path with POST method)
- For Claude, a dedicated path `POST /v0/management/claude-cookie` is cleaner

## Requirements

### Functional
- Accept JSON body: `{"cookie": "sessionKey=..."}`
- Validate cookie (non-empty, contains sessionKey)
- Call `AuthenticateWithCookie` from Phase 02
- Check for duplicate accounts by email
- Save token record via `saveTokenRecord`
- Return JSON: `{status, saved_path, email, organization_uuid, capabilities, expired, type}`

### Non-Functional
- Follow `RequestIFlowCookieToken` handler pattern exactly
- Use same error response format: `{"status": "error", "error": "..."}`
- Require management secret key auth (via existing middleware)

## Architecture

```
POST /v0/management/claude-cookie
  |
  v
Handler.RequestClaudeCookieToken(c *gin.Context)
  |-> Parse JSON body {cookie}
  |-> Validate cookie
  |-> AuthenticateWithCookie(ctx, cookie)
  |-> Build coreauth.Auth record
  |-> saveTokenRecord(ctx, record)
  |-> Return {status, saved_path, email, ...}
```

## Related Code Files
- **Modify:** `internal/api/handlers/management/auth_files.go` (add handler method)
- **Modify:** `internal/api/server.go` (register route)

## Implementation Steps

### auth_files.go

1. Add handler method `RequestClaudeCookieToken` to `Handler` in `auth_files.go`. Place it after `RequestIFlowCookieToken` (around line 1999):

```go
func (h *Handler) RequestClaudeCookieToken(c *gin.Context) {
    ctx := context.Background()

    var payload struct {
        Cookie string `json:"cookie"`
    }
    if err := c.ShouldBindJSON(&payload); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "cookie is required"})
        return
    }

    cookieValue := strings.TrimSpace(payload.Cookie)
    if cookieValue == "" {
        c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": "cookie is required"})
        return
    }

    // Normalize cookie
    cookieValue = claude.NormalizeCookie(cookieValue)
    if err := claude.ValidateCookie(cookieValue); err != nil {
        c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": err.Error()})
        return
    }

    // Authenticate via cookie->OAuth flow
    svc := claude.NewCookieAuthService(h.cfg)
    tokenStorage, errAuth := svc.AuthenticateWithCookie(ctx, cookieValue)
    if errAuth != nil {
        c.JSON(http.StatusBadRequest, gin.H{"status": "error", "error": errAuth.Error()})
        return
    }

    // <!-- Updated: Validation Session 1 - org_uuid + capability naming, email optional -->
    orgUUID := tokenStorage.OrganizationUUID
    capability := claude.ExtractPrimaryCapability(tokenStorage.Capabilities)
    fileName := fmt.Sprintf("claude-%s-%s", orgUUID, capability)
    email := tokenStorage.Email  // may be empty from cookie flow

    record := &coreauth.Auth{
        ID:       fmt.Sprintf("%s.json", fileName),
        Provider: "claude",
        FileName: fmt.Sprintf("%s.json", fileName),
        Storage:  tokenStorage,
        Metadata: map[string]any{
            "email":             email,
            "access_token":      tokenStorage.AccessToken,
            "refresh_token":     tokenStorage.RefreshToken,
            "expired":           tokenStorage.Expire,
            "cookie":            tokenStorage.Cookie,
            "organization_uuid": tokenStorage.OrganizationUUID,
            "capabilities":      tokenStorage.Capabilities,
            "type":              tokenStorage.Type,
            "last_refresh":      tokenStorage.LastRefresh,
        },
        Attributes: map[string]string{
            "access_token": tokenStorage.AccessToken,
        },
    }

    savedPath, errSave := h.saveTokenRecord(ctx, record)
    if errSave != nil {
        c.JSON(http.StatusInternalServerError, gin.H{
            "status": "error",
            "error":  "failed to save authentication tokens",
        })
        return
    }

    log.Infof("Claude cookie authentication successful. Token saved to %s", savedPath)
    c.JSON(http.StatusOK, gin.H{
        "status":            "ok",
        "saved_path":        savedPath,
        "email":             email,
        "organization_uuid": tokenStorage.OrganizationUUID,
        "capabilities":      tokenStorage.Capabilities,
        "expired":           tokenStorage.Expire,
        "type":              "claude",
    })
}
```

### server.go

2. Register the route in `registerManagementRoutes()` in `server.go`. Add after the existing iflow cookie line (~line 631):

```go
mgmt.POST("/claude-cookie", s.mgmt.RequestClaudeCookieToken)
```

3. Verify compilation: `go build ./...`

## Todo List
- [ ] Implement `RequestClaudeCookieToken` handler in auth_files.go
- [ ] Register `POST /v0/management/claude-cookie` in server.go
- [ ] Verify compilation
- [ ] Manual test via curl:
  ```
  curl -X POST http://localhost:{port}/v0/management/claude-cookie \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer {secret}" \
    -d '{"cookie":"sessionKey=sk-ant-..."}'
  ```

## Success Criteria
- `POST /v0/management/claude-cookie` with valid cookie returns 200 with account info
- Token file saved to auth directory
- Missing/invalid cookie returns 400 with error message
- Auth failure returns 400 with descriptive error
- Requires management secret key (401 without it)

## Risk Assessment
| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Large auth_files.go file | Low | Certain | File is already large; this adds ~80 lines. Future refactor can extract. |
| Race condition on duplicate save | Low | Low | saveTokenRecord handles atomically |

## Security Considerations
- Endpoint protected by management middleware (secret key required)
- Cookie value stored in auth file but not logged (use log.Infof, not log.Debugf for cookie)
- Response does not echo back the cookie value

## Next Steps
- Independent of Phase 03 and Phase 05
