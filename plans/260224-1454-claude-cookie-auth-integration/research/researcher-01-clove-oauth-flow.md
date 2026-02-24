# Research: Cookie→OAuth Token Flow in mirrorange_clove

## 1. OAuth Flow Steps & HTTP Requests

### Step 1: GetOrganizationInfo
- **URL**: `https://claude.ai/api/organizations`
- **Method**: GET
- **Headers**:
  - Cookie from user (passed in request)
  - Accept: application/json
  - Origin: claude.ai
  - Referer: claude.ai/new
- **Response**: JSON array of org objects
- **Parsing**: Extract first org with "chat" capability; return `uuid` and `capabilities` list
- **Error**: If no org with "chat", raise `OrganizationInfoError`

### Step 2: AuthorizeWithCookie
- **URL**: `https://claude.ai/v1/oauth/{organization_uuid}/authorize` (template substitution)
- **Method**: POST
- **Headers**: Same base headers + Content-Type: application/json
- **Payload** (JSON):
  ```
  {
    "response_type": "code",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    "organization_uuid": "{org_uuid}",
    "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
    "scope": "user:profile user:inference",
    "state": "{base64_32_bytes}",
    "code_challenge": "{base64_sha256(verifier)}",
    "code_challenge_method": "S256"
  }
  ```
- **PKCE**: Generate 32-byte verifier, SHA256 it, base64url-encode (no padding)
- **Response**: JSON with `redirect_uri` field
- **Extraction**: Parse redirect_uri as URL, extract query params:
  - `code` (required) → auth_code
  - `state` (optional) → response_state
  - Return combined: `"code#state"` if state present, else just `code`
- **Error**: If no code in redirect, raise `CookieAuthorizationError`

### Step 3: ExchangeToken
- **URL**: `https://console.anthropic.com/v1/oauth/token`
- **Method**: POST
- **Headers**: Content-Type: application/json (no cookie)
- **Payload** (JSON):
  ```
  {
    "code": "{auth_code}",
    "grant_type": "authorization_code",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    "redirect_uri": "https://console.anthropic.com/oauth/code/callback",
    "code_verifier": "{verifier}"
  }
  ```
  - Add optional `"state"` field if present
- **Response**: JSON with required fields:
  - `access_token` (string)
  - `refresh_token` (string)
  - `expires_in` (seconds, integer)
- **Error**: If any required field missing, raise `OAuthExchangeError`

### Step 4: RefreshAccessToken
- **URL**: `https://console.anthropic.com/v1/oauth/token`
- **Method**: POST
- **Headers**: Content-Type: application/json
- **Payload** (JSON):
  ```
  {
    "grant_type": "refresh_token",
    "refresh_token": "{refresh_token}",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  }
  ```
- **Response**: Same as ExchangeToken (access_token, refresh_token, expires_in)
- **Error Handling**: Returns `None` on any error (no exception)

## 2. OAuthToken Dataclass

```python
@dataclass
class OAuthToken:
    access_token: str          # JWT token for API auth
    refresh_token: str         # Persistent token for refresh
    expires_at: float          # Unix timestamp (current_time + expires_in)
```

## 3. Account Class Key Fields

```python
class Account:
    organization_uuid: str                      # UUID from org info
    capabilities: List[str]                     # From org response
    cookie_value: Optional[str]                 # Session cookie
    oauth_token: Optional[OAuthToken]           # OAuth credentials
    auth_type: AuthType                         # COOKIE_ONLY, OAUTH_ONLY, BOTH
    preferred_auth: PreferredAuthMethod         # AUTO (default), OAUTH, WEB
    status: AccountStatus                       # VALID, INVALID, RATE_LIMITED
    resets_at: Optional[datetime]               # Rate limit reset time
```

## 4. OAuth Constants

All from `config.py` lines 233-253:
```python
oauth_client_id: str = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
oauth_authorize_url: str = "https://claude.ai/v1/oauth/{organization_uuid}/authorize"
oauth_token_url: str = "https://console.anthropic.com/v1/oauth/token"
oauth_redirect_uri: str = "https://console.anthropic.com/oauth/code/callback"
```

## 5. Background Token Refresh Loop

**In `_check_and_refresh_accounts()` (account.py:358-370)**:
- Runs on interval (configurable via `account_task_interval`)
- For each account with `auth_type` in [OAUTH_ONLY, BOTH]:
  - Check if `expires_at - current_time < 300` (5 minutes before expiry)
  - If true, schedule `_refresh_account_token(account)` async task

**In `_refresh_account_token()` (account.py:372-395)**:
- Calls `oauth_authenticator.refresh_access_token()`
- On success: Update account.oauth_token with new tokens
- On failure:
  - If BOTH auth_type: Downgrade to COOKIE_ONLY, clear oauth_token
  - If OAUTH_ONLY: Mark account as INVALID
- Save accounts to disk on any change

## 6. 401 Re-auth Fallback (Request Retry Logic)

**In `_execute_api_request_with_retry()` (claude_api_processor.py:148-249)**:

1. Prepare headers with OAuth access_token
2. POST to Messages API
3. **On 401 authentication_error**:
   - Check if: `response.status_code == 401 AND error.type == "authentication_error" AND not retried AND account.cookie_value exists`
   - If true: Call `_try_reauthenticate_account(account)` (uses full 4-step flow)
   - If re-auth succeeds: Set `retried=True`, loop back to step 2 (retry once)
   - If re-auth fails: Raise `ClaudeHttpError`
4. **On other 4xx/5xx**: Raise appropriate error (does NOT retry)

**Special case 401**: `"OAuth authentication is currently not allowed for this organization."` → Raise `OAuthAuthenticationNotAllowedError`

## 7. Error Handling Patterns

- **Network/HTTP Errors** (302 Cloudflare block, ≥300 status): Raise typed exception (CloudflareBlockedError, ClaudeHttpError)
- **Missing Fields**: Validate required response fields → raise typed exception
- **Refresh Token Failure**: Log warning, downgrade auth_type or mark invalid
- **Re-auth Failure**: Return False, continue with existing token (may fail on next request)

---

**Key Design Patterns**:
- PKCE for security (verifier/challenge split)
- State parameter validation (in full code, state checked)
- Graceful degradation (BOTH → COOKIE_ONLY on OAuth failure)
- Proactive refresh (5-minute buffer before expiry)
- Single retry on 401 (prevents auth loop)
