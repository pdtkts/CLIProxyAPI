# Email Extraction Research Report

**Date:** 2026-02-24
**Researcher:** Claude Code
**Context:** Cookie→OAuth flow integration for cliProxyAPI and mirrorange_clove

---

## Executive Summary

The existing Anthropic OAuth2 token response **INCLUDES email directly** in the token exchange response. The cookie-based flow from clove needs to either:
1. Make a separate API call to get user info (recommended if available)
2. Decode the id_token JWT to extract email claims (fallback)

---

## Finding 1: cliProxyAPI OAuth Token Response Structure

**Location:** `internal/auth/claude/anthropic_auth.go`

The Anthropic OAuth2 token endpoint returns:

```go
type tokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int    `json:"expires_in"`
	Organization struct {
		UUID string `json:"uuid"`
		Name string `json:"name"`
	} `json:"organization"`
	Account struct {
		UUID         string `json:"uuid"`
		EmailAddress string `json:"email_address"`  // EMAIL IS HERE!
	} `json:"account"`
}
```

**Key Insight:** Email comes from `response.account.email_address` directly in the token response - NO JWT decoding needed for standard OAuth flow.

---

## Finding 2: JWT Parsing Available for ID Token

**Location:** `internal/auth/codex/jwt_parser.go`

cliProxyAPI has a complete JWT parser for extracting email from id_token:

```go
type JWTClaims struct {
	Email         string `json:"email"`           // Email in JWT
	EmailVerified bool   `json:"email_verified"`
	CodexAuthInfo CodexAuthInfo `json:"https://api.openai.com/auth"`
	// ... other claims
}

// ParseJWTToken parses a JWT token string without signature verification
func ParseJWTToken(token string) (*JWTClaims, error) { ... }

// GetUserEmail extracts the user's email address from JWT claims
func (c *JWTClaims) GetUserEmail() string {
	return c.Email
}
```

**Use Case:** If Anthropic API returns an id_token (like OpenAI/Codex does), email can be extracted via JWT parsing.

---

## Finding 3: mirrorange_clove Account Model

**Location:** `app/core/account.py`

mirrorange_clove's Account class:
- Has `organization_uuid` (available from cookie auth)
- Has `oauth_token` with `access_token` and `refresh_token`
- **Does NOT have email field** - email is not being stored or tracked

The OAuthToken dataclass:
```python
@dataclass
class OAuthToken:
    access_token: str
    refresh_token: str
    expires_at: float  # Unix timestamp
```

**Issue:** No email field in the model, so clove is not currently using email from OAuth.

---

## Finding 4: Email Usage in cliProxyAPI

**Location:** Multiple files show id_token and email handling

- `internal/api/handlers/management/api_tools.go`: Stores id_token in metadata
- `internal/api/handlers/management/auth_files.go`: Extracts JWT claims from id_token
- `internal/auth/claude/token.go`: Has IDToken in response struct

**Pattern:** cliProxyAPI extracts email via:
1. Direct field from OAuth response (`account.email_address`)
2. JWT decoding if id_token is present

---

## Cookie Auth Flow Problem

When using cookie-based authentication from clove, we have:
- ✅ `access_token` (from cookie exchange)
- ✅ `refresh_token` (from cookie exchange)
- ✅ `organization_uuid` (from cookie exchange)
- ❌ `email` (NOT returned from cookie endpoint)
- ❌ `id_token` (NOT returned from cookie endpoint)

**Root Cause:** The cookie→OAuth conversion flow does not return the same data structure as direct OAuth. It only returns tokens and organization UUID.

---

## Solutions for Getting Email in Cookie Auth Flow

### Option 1: User Info API Endpoint (RECOMMENDED)
If Anthropic has a `/v1/me` or similar userinfo endpoint:
```
GET https://api.anthropic.com/v1/me
Authorization: Bearer {access_token}
```

**Pros:**
- Standard OAuth pattern
- Always reliable regardless of token format
- Can get additional user info in one call

**Cons:**
- Requires API call per authentication
- Adds latency

**Status:** ⚠️ **UNKNOWN** - needs verification if Anthropic provides this endpoint

### Option 2: JWT Decoding from Access Token
If access_token is a JWT containing email claims (unlikely for access tokens):

**Status:** ⚠️ **UNLIKELY** - access tokens are typically opaque, not JWTs with email claims

### Option 3: JWT Decoding from ID Token
If cookie exchange returns an id_token alongside access_token:

**Status:** ⚠️ **NEEDS VERIFICATION** - check if cookie endpoint returns id_token

### Option 4: Store Email on Initial Cookie Auth
When user initially authenticates with cookie from web UI:
- Extract email from web session/cookie data
- Store in clove database along with other account info
- Use stored email instead of fetching each time

**Status:** ✅ **VIABLE** - if email is available during initial setup

### Option 5: Make Email Optional
Allow accounts without email:
- Use `organization_uuid` as unique identifier instead
- Store email as optional field (nullable)
- Fall back to organization info when email unavailable

**Status:** ✅ **VIABLE** - requires schema change in mirrorange_clove

---

## Architecture Recommendation

**Best approach for cookie auth:**

1. **First:** Implement User Info API call to fetch email (Option 1)
   - Code pattern: `GET /v1/me` with Bearer token
   - Reuse cliProxyAPI's HTTP client with Cloudflare bypass
   - Cache email in OAuthToken or separate cache

2. **Fallback:** Make email optional in Account model
   - Change mirrorange_clove Account to accept `email: Optional[str]`
   - Allow accounts to function without email
   - Use organization_uuid as primary identifier

3. **Future:** Support id_token if returned
   - Keep JWT parser ready
   - Use for email extraction if available

---

## Implementation Steps

### For cliProxyAPI:
1. Check if Anthropic API has `/v1/me` endpoint
2. If yes: Create `GetUserInfo()` method in `anthropic_auth.go`
3. Call after token exchange to get email

### For mirrorange_clove:
1. Update `OAuthToken` to include email field (optional)
2. Update `Account` to track email
3. Implement `fetch_user_email()` after token exchange
4. Store email in OAuth token data

---

## Unresolved Questions

1. **Does Anthropic API have a userinfo/profile endpoint?** (Critical)
   - Need to check Anthropic API documentation or test with actual token
   - If no endpoint exists, email extraction is blocked for cookie auth flow

2. **What is returned by cookie→OAuth exchange endpoint?** (Critical)
   - Confirmed: access_token, refresh_token, organization_uuid
   - Unknown: Does it include id_token? Does it include email directly?

3. **How is email currently used in clove?** (Important)
   - Account model has no email field
   - Is email required for any functionality?
   - Can system work without email?

4. **Can we decode access_token as JWT to get email?** (Low probability)
   - Unlikely, but worth testing with actual token
   - Most systems use opaque access tokens

---

## References

- cliProxyAPI: `internal/auth/claude/anthropic_auth.go` - Token response structure
- cliProxyAPI: `internal/auth/codex/jwt_parser.go` - JWT parsing capability
- mirrorange_clove: `app/core/account.py` - Account and OAuthToken models
- cliProxyAPI: `internal/auth/claude/token.go` - Token struct with IDToken field
