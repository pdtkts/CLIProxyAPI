# Phase 01: Extend Token Struct

## Context Links
- Token struct: `internal/auth/claude/token.go`
- Types: `internal/auth/claude/anthropic.go`
- Research: [cliProxyAPI Patterns](research/researcher-02-cliproxyapi-patterns.md)

## Overview
- **Priority:** P1 (blocks all other phases)
- **Status:** pending
- **Effort:** 30m
- **Description:** Add Cookie, OrganizationUUID, and Capabilities fields to ClaudeTokenStorage. All fields use `omitempty` for backward compatibility with existing auth files.

## Key Insights
- Existing struct has 7 fields, all serialized via `json.NewEncoder().Encode()`
- `SaveTokenToFile` serializes the full struct, so new fields automatically persist
- Old auth files without new fields will deserialize cleanly (Go zero-values + omitempty)
- `Expire` field has JSON key `"expired"` (historical naming, keep consistent)

## Requirements

### Functional
- Add `Cookie` field to store session cookie for re-auth
- Add `OrganizationUUID` field to store org UUID from organization info
- Add `Capabilities` field to store account capabilities (free/pro/max plan indicators)

### Non-Functional
- All new fields MUST use `omitempty` tag
- Existing auth files MUST load without errors
- No changes needed to `SaveTokenToFile` method

## Architecture
No architectural changes. Purely additive struct modification.

## Related Code Files
- **Modify:** `internal/auth/claude/token.go`

## Implementation Steps

1. Open `internal/auth/claude/token.go`

2. Add three new fields to `ClaudeTokenStorage` struct after the `Expire` field:

```go
// Cookie is the Claude.ai session cookie used for cookie-based OAuth flow.
// Stored for automatic re-authentication when refresh tokens expire.
Cookie string `json:"cookie,omitempty"`

// OrganizationUUID is the UUID of the Claude organization associated with this account.
// Retrieved from the organizations API during cookie-based authentication.
OrganizationUUID string `json:"organization_uuid,omitempty"`

// Capabilities lists the account's capabilities (e.g., "chat", "pro", "max_mode").
// Indicates the account tier and available features.
Capabilities []string `json:"capabilities,omitempty"`
```

3. Verify compilation: `go build ./internal/auth/claude/...`

4. Verify existing tests still pass: `go test ./internal/auth/claude/...`

## Todo List
- [ ] Add Cookie field with omitempty
- [ ] Add OrganizationUUID field with omitempty
- [ ] Add Capabilities field with omitempty
- [ ] Verify compilation
- [ ] Verify existing tests pass

## Success Criteria
- All three fields present in struct with correct JSON tags
- `go build ./...` succeeds
- Existing test suite passes
- Old auth JSON files deserialize without errors (omitempty handles missing fields)

## Risk Assessment
| Risk | Impact | Mitigation |
|------|--------|------------|
| JSON key naming inconsistency | Low | Follow existing pattern (lowercase, snake_case) |
| Struct size increase | Negligible | Only 3 fields, all optional |

## Security Considerations
- Cookie field contains sensitive session data; same security level as refresh_token
- Auth files already stored with mode 0700 directory permissions

## Next Steps
- Phase 02 depends on these new fields being available
