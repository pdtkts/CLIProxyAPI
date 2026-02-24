---
title: "Claude Cookie-Based Auth Integration"
description: "Port cookie->OAuth token flow from clove into cliProxyAPI for cookie-based account addition and auto re-auth"
status: pending
priority: P1
effort: 6h
branch: main
tags: [auth, claude, cookie, oauth]
created: 2026-02-24
---

# Claude Cookie-Based Auth Integration

## Summary

Port mirrorange_clove's cookie->OAuth token pipeline into cliProxyAPI (Go) to enable adding Claude accounts via session cookie, automatic re-authentication on refresh failure, and capability detection.

## Architecture

```
Cookie Input (CLI flag --claude-cookie / API POST)
  |
  v
[1] GET claude.ai/api/organizations  (cookie header)
  -> org_uuid, capabilities
  |
  v
[2] GenerateCookiePKCE()  (32-byte verifier, not 96-byte)
  -> verifier, challenge
  |
  v
[3] POST claude.ai/v1/oauth/{org_uuid}/authorize  (cookie + PKCE)
  -> redirect_uri -> extract authorization_code + state
  |
  v
[4] POST api.anthropic.com/v1/oauth/token  (code + verifier)
  -> access_token, refresh_token, expires_in, email (maybe)
  |  fallback: console.anthropic.com/v1/oauth/token
  |
  v
[5] Save to claude-{org_uuid}-{capability}.json  (with cookie, org_uuid, capabilities)
```

## Phases

| # | Phase | File | Status |
|---|-------|------|--------|
| 1 | Extend token struct | [phase-01](phase-01-extend-token-struct.md) | pending |
| 2 | Cookie auth core | [phase-02](phase-02-cookie-auth-core.md) | pending |
| 3 | CLI command | [phase-03](phase-03-cli-command.md) | pending |
| 4 | Management API endpoint | [phase-04](phase-04-management-api-endpoint.md) | pending |
| 5 | Token refresh fallback | [phase-05](phase-05-token-refresh-fallback.md) | pending |

## Dependencies

- Phase 2 depends on Phase 1 (needs new struct fields)
- Phases 3, 4, 5 all depend on Phase 2 (need core auth functions)
- Phases 3, 4, 5 are independent of each other

## Key Constants (from clove)

```
client_id:     "9d1c250a-e61b-44d9-88ed-5944d1962f5e"  (same as browser flow)
authorize_url: "https://claude.ai/v1/oauth/{org_uuid}/authorize"  (DIFFERENT from browser)
token_url:     "https://console.anthropic.com/v1/oauth/token"     (DIFFERENT from browser)
redirect_uri:  "https://console.anthropic.com/oauth/code/callback" (DIFFERENT from browser)
scope:         "user:profile user:inference"
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `internal/auth/claude/token.go` | Modify - add 3 fields |
| `internal/auth/claude/cookie_auth.go` | Create - core flow |
| `internal/auth/claude/cookie_helpers.go` | Create - validation |
| `internal/cmd/claude_cookie.go` | Create - CLI command |
| `cmd/server/main.go` | Modify - add flag |
| `internal/api/handlers/management/auth_files.go` | Modify - add endpoint |
| `internal/api/server.go` | Modify - register route |
| `internal/runtime/executor/claude_executor.go` | Modify - fallback |

## Research

- [Clove OAuth Flow](research/researcher-01-clove-oauth-flow.md)
- [cliProxyAPI Patterns](research/researcher-02-cliproxyapi-patterns.md)
- [Email Extraction](research/researcher-03-email-extraction.md)

## Validation Log

### Session 1 — 2026-02-24
**Trigger:** Initial plan creation validation
**Questions asked:** 3

#### Questions & Answers

1. **[Architecture]** File naming with capabilities included. Which pattern?
   - Options: claude-{org_uuid}-{capability}.json | claude-{org_uuid_short}-{capability}.json | claude-cookie-{org_uuid}-{capability}.json
   - **Answer:** claude-{org_uuid}-{capability}.json
   - **Rationale:** Capabilities distinguish plan tiers (claude_max, pro, free). Consistent with codex pattern (codex-{id}-{email}-{plan}.json). No email available from cookie flow, org_uuid is primary identifier.

2. **[Architecture]** Token exchange endpoint: clove uses console.anthropic.com, cliProxyAPI uses api.anthropic.com. Which to use?
   - Options: Use console.anthropic.com (match clove) | Try api.anthropic.com first, fallback to console | Make configurable
   - **Answer:** Try api.anthropic.com first, fallback to console
   - **Rationale:** api.anthropic.com may return account.email_address in response (like existing browser flow). If it works, we get email for free. console.anthropic.com is proven fallback.

3. **[Risk]** How should we handle cookie persistence after token refresh fallback in the executor?
   - Options: Verify runtime behavior during implementation | Always explicitly save to file after re-auth
   - **Answer:** Verify runtime behavior during implementation
   - **Rationale:** Avoid premature optimization. Check if runtime already saves all metadata keys. Fix only if cookie gets lost.

#### Key Clarification (from user)
- Cookie flow returns NO email. Data from clove's accounts.json: {organization_uuid, capabilities, cookie_value, status, auth_type, oauth_token: {access_token, refresh_token, expires_at}}
- Capabilities (claude_max, pro, free, chat) should be used in file naming to distinguish plan tiers

#### Confirmed Decisions
- File naming: `claude-{org_uuid}-{capability}.json` — extract highest tier from capabilities
- Token endpoint: try api.anthropic.com first, fallback to console.anthropic.com — may get email
- Cookie persistence: verify at implementation time — avoid unnecessary complexity
- Email: optional field, org_uuid is primary identifier

#### Action Items
- [ ] Phase 02: Add dual-endpoint token exchange (api.anthropic.com → console.anthropic.com fallback)
- [ ] Phase 02: Add ExtractPrimaryCapability() helper to pick highest tier from capabilities list
- [ ] Phase 03: Update file naming to claude-{org_uuid}-{capability}.json
- [ ] Phase 04: Update file naming to claude-{org_uuid}-{capability}.json
- [ ] Phase 05: Add note to verify runtime metadata persistence during implementation

#### Impact on Phases
- Phase 02: Add dual-endpoint logic in ExchangeTokenFromCookie; add capability tier extraction helper
- Phase 03: Change file naming from claude-{email}-{ts}.json to claude-{org_uuid}-{capability}.json
- Phase 04: Change file naming from claude-{email}-{ts}.json to claude-{org_uuid}-{capability}.json
- Phase 05: Add implementation-time verification step for metadata persistence
