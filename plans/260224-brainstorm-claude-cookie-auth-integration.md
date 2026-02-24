# Brainstorm: Claude Cookie-Based Auth Integration

**Date:** 2026-02-24
**Status:** Agreed
**Participants:** User + AI Advisor

---

## Problem Statement

cliProxyAPI currently supports Claude account addition only via browser-based OAuth2+PKCE flow. mirrorange_clove has a cookie→OAuth token pipeline that:
1. Accepts a Claude.ai session cookie
2. Programmatically obtains OAuth tokens without browser interaction
3. Auto re-authenticates when refresh_token expires

**Goal:** Integrate clove's cookie→OAuth flow into cliProxyAPI to enable cookie-based account addition and automatic token re-authentication on refresh failure.

---

## Requirements

### Functional
- Add Claude accounts via session cookie (no browser needed)
- Store cookie in auth JSON file for future re-auth
- Auto re-auth via cookie when refresh_token exchange fails
- Fetch account capabilities (free/pro/max) from org info
- Expose via both CLI command and Management API endpoint
- Backward compatible with existing auth files (omitempty fields)

### Non-Functional
- Reuse existing PKCE implementation (`pkce.go`)
- Reuse existing UTLS transport for Cloudflare bypass
- Consistent with existing provider architecture pattern
- No external dependencies (pure Go HTTP calls)

---

## Evaluated Approaches

### Approach 1: Native Go Port (SELECTED)
Port clove's Python flow directly into Go within `internal/auth/claude/`.

**Pros:**
- Single binary, no external dependencies
- Consistent with existing codebase patterns
- Reuses existing PKCE + UTLS transport
- Full control over error handling and retry logic

**Cons:**
- Development effort to port HTTP flow
- Must maintain parity with clove's endpoint knowledge

### Approach 2: Python Subprocess (REJECTED)
Shell out to clove's Python scripts.

**Pros:** Quick integration
**Cons:** Python dependency, process management, defeats Go's advantages

### Approach 3: Microservice (REJECTED)
Run clove as a sidecar service.

**Pros:** Language-agnostic
**Cons:** Unnecessary complexity, network hop, deployment burden

---

## Final Solution: Native Go Port

### Architecture Flow

```
Cookie Input (CLI/API)
       ↓
[1] GET claude.ai/api/organizations  (cookie header)
       → org_uuid, capabilities
       ↓
[2] GeneratePKCE()  (reuse existing pkce.go)
       → verifier, challenge
       ↓
[3] POST claude.ai/v1/oauth/{org_uuid}/authorize  (cookie header + PKCE)
       → redirect_uri → extract authorization_code
       ↓
[4] POST console.anthropic.com/v1/oauth/token  (code + verifier)
       → access_token, refresh_token, expires_in
       ↓
[5] Save to claude-{email}.json  (with cookie, org_uuid, capabilities)
```

### Re-auth Fallback (on refresh_token failure)

```
Normal refresh_token exchange fails (401/expired)
       ↓
Check: does auth file have stored cookie?
       → Yes: re-run steps [1]-[4] using stored cookie
       → No: mark account expired (current behavior)
```

### Key Constants (from clove)

```
client_id:     "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
authorize_url: "https://claude.ai/v1/oauth/{org_uuid}/authorize"
token_url:     "https://console.anthropic.com/v1/oauth/token"
redirect_uri:  "https://console.anthropic.com/oauth/code/callback"
scope:         "user:profile user:inference"
```

### Token JSON Schema (Extended)

```json
{
  "id_token": "...",
  "access_token": "sk-...",
  "refresh_token": "sk-...",
  "last_refresh": "2026-02-24T10:30:00Z",
  "email": "user@example.com",
  "type": "claude",
  "expired": "2026-02-24T11:30:00Z",
  "cookie": "sessionKey=sk-ant-...",
  "organization_uuid": "uuid-here",
  "capabilities": ["chat", "pro"]
}
```

### Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `internal/auth/claude/token.go` | Modify | Add Cookie, OrganizationUUID, Capabilities fields |
| `internal/auth/claude/cookie_auth.go` | Create | Core cookie→OAuth flow functions |
| `internal/auth/claude/cookie_helpers.go` | Create | Cookie validation, org info parsing |
| `internal/cmd/claude_cookie.go` | Create | CLI command for cookie login |
| `internal/api/handlers/management/` | Modify | Management API endpoint for cookie add |
| Token refresh logic | Modify | Fallback to cookie re-auth on refresh failure |

### Core Functions to Implement

```go
// cookie_auth.go
func GetOrganizationInfo(ctx context.Context, cookie string) (*OrgInfo, error)
func AuthorizeWithCookie(ctx context.Context, cookie string, orgUUID string) (authCode string, verifier string, err error)
func ExchangeTokenFromCookie(ctx context.Context, code string, verifier string) (*TokenResponse, error)
func AuthenticateWithCookie(ctx context.Context, cookie string) (*ClaudeTokenStorage, error) // orchestrator

// cookie_helpers.go
func ValidateCookie(cookie string) error
func ExtractSessionKey(cookie string) string
func NormalizeCookie(raw string) string
```

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Cloudflare blocking | High | Medium | Reuse existing UTLS transport with CF bypass |
| Claude.ai endpoint changes | High | Low | Centralize URLs in constants, easy to update |
| Cookie expiry before refresh | Medium | Medium | Log warning, mark account needs new cookie |
| Backward compatibility | Low | Low | omitempty JSON tags, nil checks on new fields |
| Rate limiting on org API | Medium | Low | Cache org_uuid after first successful fetch |

---

## Success Metrics

- [ ] Can add Claude account via cookie through CLI
- [ ] Can add Claude account via cookie through Management API
- [ ] Cookie stored in auth file for re-auth
- [ ] Auto re-auth triggers on refresh_token failure
- [ ] Capabilities (free/pro/max) fetched and stored
- [ ] Existing OAuth browser flow unaffected
- [ ] Old auth files without cookie fields load without errors

---

## Implementation Considerations

1. **HTTP Client**: Use existing UTLS-based HTTP client for Cloudflare bypass
2. **Error Types**: Define specific error types (OrgInfoError, CookieAuthError, etc.)
3. **Logging**: Comprehensive logging for debugging auth failures
4. **Testing**: Unit test each HTTP step with mock responses
5. **Config**: Make OAuth URLs configurable (not just hardcoded constants)

---

## Next Steps

1. Create detailed implementation plan with phases
2. Implement cookie_auth.go (core flow)
3. Extend token struct
4. Add CLI command
5. Add Management API endpoint
6. Modify refresh logic with cookie fallback
7. Test end-to-end flow
