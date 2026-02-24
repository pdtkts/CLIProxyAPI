# cliProxyAPI Pattern Research: Claude Auth Integration

## Executive Summary
cliProxyAPI has established patterns for OAuth, token storage, CLI commands, and management APIs. Claude auth already uses PKCE OAuth flow with custom UTLS HTTP client for Cloudflare bypass. Cookie auth can integrate as alternative auth mechanism following existing patterns.

## 1. Token Storage Struct (Reusable)

**Location:** `internal/auth/claude/token.go`

```go
type ClaudeTokenStorage struct {
	IDToken      string `json:"id_token"`
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	LastRefresh  string `json:"last_refresh"`
	Email        string `json:"email"`
	Type         string `json:"type"`
	Expire       string `json:"expired"`  // Note: JSON key is "expired"
}

// SaveTokenToFile serializes tokens to JSON file at specified path
// Creates directory structure (mode 0700) and encodes as JSON
func (ts *ClaudeTokenStorage) SaveTokenToFile(authFilePath string) error
```

**Key observations:**
- Type field always set to "claude"
- Uses RFC3339 format for timestamps (see anthropic_auth.go line 198)
- Expire field JSON key is `"expired"` (not "expire")
- LastRefresh format: `time.Now().Format(time.RFC3339)`

## 2. PKCE Functions

**Location:** `internal/auth/claude/pkce.go`

```go
// GeneratePKCECodes() (*PKCECodes, error)
// - Generates 96 random bytes → 128 base64 URL-safe chars
// - Returns verifier and S256 challenge
// Reusable for cookie auth flow if needed for additional security

type PKCECodes struct {
	CodeVerifier  string
	CodeChallenge string
}
```

## 3. CLI Command Pattern

**Location:** `internal/cmd/anthropic_login.go` and `internal/cmd/iflow_cookie.go`

Pattern:
```go
// Function signature (no cobra/cli framework)
func DoClaudeLogin(cfg *config.Config, options *LoginOptions)
func DoIFlowCookieAuth(cfg *config.Config, options *LoginOptions)

// LoginOptions struct
type LoginOptions struct {
	Prompt       func(string) (string, error)  // Prompting function
	NoBrowser    bool
	CallbackPort int
}

// Implementation flow:
// 1. Process options (nil → create defaults)
// 2. Prompt user for auth input (cookie/code)
// 3. Create auth service and call auth method
// 4. Save tokens using tokenStorage.SaveTokenToFile(authFilePath)
```

**Key pattern from iflow_cookie.go:**
- No command structure - functions called directly from main
- File path generation: `fmt.Sprintf("%s/%s-%s-%d.json", cfg.AuthDir, provider, fileName, time.Now().Unix())`
- Duplicate checking before saving
- Error handling via log + fmt.Printf return

## 4. HTTP Client Pattern (Cloudflare Bypass)

**Location:** `internal/auth/claude/utls_transport.go`

```go
// Creates HTTP client with UTLS (uTLS) for Firefox TLS fingerprint bypass
func NewAnthropicHttpClient(cfg *config.SDKConfig) *http.Client

// utlsRoundTripper implements http.RoundTripper
// - HTTP/2 connection pooling with per-host locking
// - Firefox TLS fingerprint: tls.HelloFirefox_Auto
// - Proxy support via SDKConfig.ProxyURL
```

**Used in:** `NewClaudeAuth()` at line 65 in anthropic_auth.go

## 5. OAuth Flow Implementation

**Location:** `internal/auth/claude/anthropic_auth.go`

```go
// OAuth endpoints
AuthURL    = "https://claude.ai/oauth/authorize"
TokenURL   = "https://api.anthropic.com/v1/oauth/token"
ClientID   = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
RedirectURI = "http://localhost:54545/callback"

// ClaudeAuth methods:
GenerateAuthURL(state string, pkceCodes *PKCECodes) (url, state string, error)
ExchangeCodeForTokens(ctx, code, state string, pkceCodes) (*ClaudeAuthBundle, error)
RefreshTokens(ctx, refreshToken string) (*ClaudeTokenData, error)
CreateTokenStorage(bundle *ClaudeAuthBundle) *ClaudeTokenStorage
UpdateTokenStorage(storage *ClaudeTokenStorage, tokenData *ClaudeTokenData)
```

## 6. Token Refresh Logic

**Location:** `internal/auth/claude/anthropic_auth.go` (lines 210-334)

```go
// Simple refresh
RefreshTokens(ctx, refreshToken string) (*ClaudeTokenData, error)
  - POST to TokenURL with grant_type="refresh_token"
  - Returns new ClaudeTokenData (access, refresh, email, expire)

// Resilient refresh with retry
RefreshTokensWithRetry(ctx, refreshToken string, maxRetries int) (*ClaudeTokenData, error)
  - Exponential backoff: wait(attempt * 1 second)
  - Returns error after all retries exhausted
```

## 7. Management API Auth Endpoint Pattern

**Location:** `internal/api/handlers/management/auth_files.go` (first 150 lines)

Callback port configuration (line 45):
```go
const anthropicCallbackPort = 54545

// startCallbackForwarder(port, provider, targetBase) for proxy auth flows
// extractLastRefreshTimestamp() helper for parsing various time formats
```

## 8. OAuth Server for Callback Handling

**Location:** `internal/auth/claude/oauth_server.go`

```go
// OAuthServer handles local HTTP callback server
type OAuthServer struct {
	port       int
	resultChan chan *OAuthResult
	errorChan  chan error
}

type OAuthResult struct {
	Code  string  // Authorization code from OAuth provider
	State string  // CSRF protection state
	Error string  // Error message if flow failed
}

// Methods
Start() error  // Listen on port, setup /callback and /success handlers
Stop(ctx) error
WaitForCallback(timeout) (*OAuthResult, error)  // Block until callback received
```

## Key Integration Points for Cookie Auth

1. **Reuse ClaudeTokenStorage** - already has all needed fields
2. **HTTP Client** - use NewAnthropicHttpClient() for Cloudflare bypass
3. **CLI Command** - follow DoIFlowCookieAuth() pattern (no cobra framework)
4. **File path** - use same pattern: `{authDir}/{provider}-{sanitized-email}-{timestamp}.json`
5. **Token refresh** - use RefreshTokens() method on ClaudeAuth
6. **Management API** - integrate callback forwarder if needed (anthropicCallbackPort = 54545)

## Unresolved Questions

- Does cookie auth require management API endpoint registration for token refresh?
- Should cookie auth use same callback port (54545) or separate port for HTTP server?
