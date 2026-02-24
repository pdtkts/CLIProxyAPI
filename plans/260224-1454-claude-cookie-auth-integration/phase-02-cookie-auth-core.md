# Phase 02: Cookie Auth Core

## Context Links
- Clove flow: [researcher-01-clove-oauth-flow.md](research/researcher-01-clove-oauth-flow.md)
- Existing auth: `internal/auth/claude/anthropic_auth.go`
- PKCE: `internal/auth/claude/pkce.go`
- UTLS transport: `internal/auth/claude/utls_transport.go`
- Types: `internal/auth/claude/anthropic.go`

## Overview
- **Priority:** P1 (blocks phases 3, 4, 5)
- **Status:** pending
- **Effort:** 2h
- **Description:** Implement core cookie->OAuth token flow. Two new files: `cookie_auth.go` (main flow) and `cookie_helpers.go` (validation/parsing).

## Key Insights

### Endpoint Differences (CRITICAL)
The cookie flow uses DIFFERENT endpoints than the browser flow:
- **authorize_url**: `https://claude.ai/v1/oauth/{org_uuid}/authorize` (NOT `https://claude.ai/oauth/authorize`)
- **token_url**: `https://console.anthropic.com/v1/oauth/token` (NOT `https://api.anthropic.com/v1/oauth/token`)
- **redirect_uri**: `https://console.anthropic.com/oauth/code/callback` (NOT `http://localhost:54545/callback`)
- **scope**: `user:profile user:inference` (NOT `org:create_api_key user:profile user:inference`)
- **client_id**: Same `9d1c250a-e61b-44d9-88ed-5944d1962f5e`

### PKCE Difference
- Existing `GeneratePKCECodes()` uses 96 random bytes -> 128-char verifier
- Clove uses 32 random bytes -> 43-char verifier
- Need separate `generateCookiePKCE()` function (do NOT modify existing PKCE)
- Challenge generation is identical (SHA256 + base64url no-padding)

### HTTP Headers for Cookie Requests
Steps 1 and 2 require specific headers with the session cookie:
```
Cookie: {cookie_value}
Accept: application/json
Content-Type: application/json  (for POST only)
Origin: https://claude.ai
Referer: https://claude.ai/new
```

### Token Exchange (Step 3) Does NOT Need Cookie
<!-- Updated: Validation Session 1 - dual-endpoint token exchange -->
Try `api.anthropic.com/v1/oauth/token` first (may return `account.email_address`), fallback to `console.anthropic.com/v1/oauth/token` if first fails. Neither needs cookie.

### Organization Response Structure
```json
[
  {
    "uuid": "org-uuid-here",
    "name": "Personal",
    "capabilities": ["chat", "pro"],
    ...
  }
]
```
Select first org that has `"chat"` in capabilities.

## Requirements

### Functional
- Fetch organization info (UUID + capabilities) from cookie
- Generate PKCE codes with 32-byte verifier
- Authorize via cookie to get auth code
- Exchange auth code for OAuth tokens
- Orchestrator function that chains all steps

### Non-Functional
- Reuse existing UTLS HTTP client (`NewAnthropicHttpClient`)
- Reuse existing `ClaudeAuth` struct or create parallel struct
- Return `*ClaudeTokenStorage` with cookie, org UUID, capabilities populated
- Comprehensive error handling with typed errors

## Architecture

### File: `internal/auth/claude/cookie_auth.go`

```go
package claude

// Constants
<!-- Updated: Validation Session 1 - dual-endpoint, capability extraction -->
const (
    CookieOAuthAuthorizeURLTemplate = "https://claude.ai/v1/oauth/%s/authorize"
    CookieOAuthTokenURLPrimary      = "https://api.anthropic.com/v1/oauth/token"      // try first (may return email)
    CookieOAuthTokenURLFallback     = "https://console.anthropic.com/v1/oauth/token"  // fallback (proven, no email)
    CookieOAuthRedirectURI          = "https://console.anthropic.com/oauth/code/callback"
    CookieOAuthScope                = "user:profile user:inference"
    OrganizationsURL                = "https://claude.ai/api/organizations"
)

// OrgInfo holds organization data from the organizations API
type OrgInfo struct {
    UUID         string   `json:"uuid"`
    Name         string   `json:"name"`
    Capabilities []string `json:"capabilities"`
}

// CookieAuthService handles cookie-based OAuth flow
type CookieAuthService struct {
    httpClient *http.Client
}

func NewCookieAuthService(cfg *config.Config) *CookieAuthService
func (s *CookieAuthService) GetOrganizationInfo(ctx, cookie) (*OrgInfo, error)
func (s *CookieAuthService) AuthorizeWithCookie(ctx, cookie, orgUUID string) (code, state, verifier string, err error)
func (s *CookieAuthService) ExchangeTokenFromCookie(ctx, code, verifier, state string) (*ClaudeTokenData, error)  // tries primary then fallback
func (s *CookieAuthService) AuthenticateWithCookie(ctx, cookie string) (*ClaudeTokenStorage, error)
func ExtractPrimaryCapability(capabilities []string) string  // returns highest tier: claude_max > pro > free
```

### File: `internal/auth/claude/cookie_helpers.go`

```go
package claude

func ValidateCookie(cookie string) error
func NormalizeCookie(raw string) string
func SanitizeClaudeFileName(email string) string
```

## Related Code Files
- **Create:** `internal/auth/claude/cookie_auth.go`
- **Create:** `internal/auth/claude/cookie_helpers.go`
- **Read (reference):** `internal/auth/claude/anthropic_auth.go`
- **Read (reference):** `internal/auth/claude/pkce.go`
- **Read (reference):** `internal/auth/claude/utls_transport.go`

## Implementation Steps

### cookie_helpers.go

1. Create `internal/auth/claude/cookie_helpers.go` with package declaration

2. Implement `ValidateCookie(cookie string) error`:
   - Check non-empty
   - Check contains `sessionKey=` (the required cookie field for Claude.ai)
   - Return descriptive error if invalid

3. Implement `NormalizeCookie(raw string) string`:
   - Trim whitespace
   - If input is just a token value (no `sessionKey=` prefix), prepend `sessionKey=`
   - Return normalized cookie string

4. Implement `SanitizeClaudeFileName(email string) string`:
   - Replace `@` with `_at_`
   - Replace non-alphanumeric chars with `_`
   - Lowercase
   - Follow same pattern as `iflow.SanitizeIFlowFileName`

<!-- Updated: Validation Session 1 - capability tier extraction -->
4b. Implement `ExtractPrimaryCapability(capabilities []string) string`:
   - Priority order: "claude_max" > "pro" > "free" > first capability > "unknown"
   - Returns the highest tier found in the capabilities list
   - Used for file naming: `claude-{org_uuid}-{capability}.json`

### cookie_auth.go

5. Create `internal/auth/claude/cookie_auth.go` with constants block:
   ```go
   const (
       CookieOAuthAuthorizeURLTemplate = "https://claude.ai/v1/oauth/%s/authorize"
       CookieOAuthTokenURL             = "https://console.anthropic.com/v1/oauth/token"
       CookieOAuthRedirectURI          = "https://console.anthropic.com/oauth/code/callback"
       CookieOAuthScope                = "user:profile user:inference"
       OrganizationsURL                = "https://claude.ai/api/organizations"
   )
   ```

6. Define `OrgInfo` struct and `CookieAuthService` struct:
   ```go
   type OrgInfo struct {
       UUID         string   `json:"uuid"`
       Name         string   `json:"name"`
       Capabilities []string `json:"capabilities"`
   }

   type CookieAuthService struct {
       httpClient *http.Client
   }

   func NewCookieAuthService(cfg *config.Config) *CookieAuthService {
       return &CookieAuthService{
           httpClient: NewAnthropicHttpClient(&cfg.SDKConfig),
       }
   }
   ```

7. Implement `generateCookiePKCE() (*PKCECodes, error)`:
   - Generate 32 random bytes (NOT 96 like existing PKCE)
   - Base64url encode without padding -> ~43-char verifier
   - SHA256 hash + base64url encode -> challenge
   - Return `*PKCECodes` (reuse existing struct)

8. Implement `generateRandomState() (string, error)`:
   - Generate 32 random bytes
   - Base64url encode without padding
   - Return as state string

9. Implement `GetOrganizationInfo(ctx context.Context, cookie string) (*OrgInfo, error)`:
   - GET `OrganizationsURL`
   - Set headers: `Cookie: {cookie}`, `Accept: application/json`, `Origin: https://claude.ai`, `Referer: https://claude.ai/new`
   - Parse response as `[]OrgInfo`
   - Find first org where capabilities contains `"chat"`
   - Return org info or error if none found
   - Handle non-200 status (Cloudflare block = 302/403)

10. Implement `AuthorizeWithCookie(ctx, cookie, orgUUID string) (code, state, verifier string, err error)`:
    - Generate PKCE via `generateCookiePKCE()`
    - Generate state via `generateRandomState()`
    - Build authorize URL: `fmt.Sprintf(CookieOAuthAuthorizeURLTemplate, orgUUID)`
    - POST with JSON body:
      ```json
      {
        "response_type": "code",
        "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        "organization_uuid": "{orgUUID}",
        "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
        "scope": "user:profile user:inference",
        "state": "{state}",
        "code_challenge": "{challenge}",
        "code_challenge_method": "S256"
      }
      ```
    - Set headers: `Cookie: {cookie}`, `Content-Type: application/json`, `Accept: application/json`, `Origin: https://claude.ai`, `Referer: https://claude.ai/new`
    - Parse response JSON for `redirect_uri` field
    - Parse redirect_uri as URL, extract `code` and `state` query params
    - Return code, state (from response), verifier

<!-- Updated: Validation Session 1 - dual-endpoint with fallback -->
11. Implement `ExchangeTokenFromCookie(ctx, code, verifier, state string) (*ClaudeTokenData, error)`:
    - **Try CookieOAuthTokenURLPrimary first** (`api.anthropic.com/v1/oauth/token`):
      - May return `account.email_address` in response (same struct as browser flow)
      - If succeeds: extract email, return with email populated
    - **On failure, fallback to CookieOAuthTokenURLFallback** (`console.anthropic.com/v1/oauth/token`):
      - Proven working endpoint from clove
      - Returns access_token, refresh_token, expires_in (no email)
      - Email field left empty
    - JSON body (same for both endpoints):
      ```json
      {
        "code": "{code}",
        "grant_type": "authorization_code",
        "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
        "code_verifier": "{verifier}"
      }
      ```
    - Add `"state"` field if state is non-empty
    - Set headers: `Content-Type: application/json`, `Accept: application/json` (NO cookie)
    - Parse response using `tokenResponse` struct (handles both account.email_address and flat responses)
    - Return `*ClaudeTokenData` with computed Expire (RFC3339), email may be empty

12. Implement `AuthenticateWithCookie(ctx context.Context, cookie string) (*ClaudeTokenStorage, error)`:
    - Validate cookie via `ValidateCookie(cookie)`
    - Normalize cookie via `NormalizeCookie(cookie)`
    - Call `GetOrganizationInfo(ctx, cookie)` -> orgInfo
    - Call `AuthorizeWithCookie(ctx, cookie, orgInfo.UUID)` -> code, state, verifier
    - Call `ExchangeTokenFromCookie(ctx, code, verifier, state)` -> tokenData
    - Build and return `*ClaudeTokenStorage`:
      ```go
      &ClaudeTokenStorage{
          AccessToken:      tokenData.AccessToken,
          RefreshToken:     tokenData.RefreshToken,
          LastRefresh:      time.Now().Format(time.RFC3339),
          Email:            tokenData.Email,
          Expire:           tokenData.Expire,
          Cookie:           cookie,
          OrganizationUUID: orgInfo.UUID,
          Capabilities:     orgInfo.Capabilities,
      }
      ```

13. Verify compilation: `go build ./internal/auth/claude/...`

## Todo List
- [ ] Create cookie_helpers.go with ValidateCookie, NormalizeCookie, SanitizeClaudeFileName
- [ ] Create cookie_auth.go with constants
- [ ] Implement OrgInfo struct and CookieAuthService
- [ ] Implement generateCookiePKCE (32-byte verifier)
- [ ] Implement generateRandomState
- [ ] Implement GetOrganizationInfo
- [ ] Implement AuthorizeWithCookie
- [ ] Implement ExchangeTokenFromCookie
- [ ] Implement AuthenticateWithCookie (orchestrator)
- [ ] Verify compilation
- [ ] Test with real cookie (manual verification)

## Success Criteria
- `AuthenticateWithCookie(ctx, cookie)` returns populated `*ClaudeTokenStorage` with tokens, cookie, org UUID, capabilities
- All four HTTP steps execute in sequence
- Proper error messages for each failure point
- PKCE uses 32-byte verifier (not 96-byte)
- Existing browser OAuth flow unaffected

## Risk Assessment
| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Cloudflare blocking cookie requests | High | Medium | Reuse UTLS transport with Firefox fingerprint |
| Clove endpoints change | High | Low | Constants centralized, easy to update |
| Cookie format variations | Medium | Medium | NormalizeCookie handles common formats |
| Organization without "chat" capability | Low | Low | Clear error message, skip org |

## Security Considerations
- Cookie is equivalent to a session token; treat with same security as refresh_token
- Cookie transmitted only to claude.ai domain (steps 1-2), never to console.anthropic.com (step 3)
- PKCE prevents auth code interception
- State parameter prevents CSRF

## Next Steps
- Phases 3, 4, 5 can proceed in parallel after this phase completes
