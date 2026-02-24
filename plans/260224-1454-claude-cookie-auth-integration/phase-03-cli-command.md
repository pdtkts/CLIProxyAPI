# Phase 03: CLI Command

## Context Links
- Pattern to follow: `internal/cmd/iflow_cookie.go`
- Main entry: `cmd/server/main.go` (lines 64, 82, 477-478)
- Login options: `internal/cmd/anthropic_login.go`
- Cookie auth core: Phase 02 (`internal/auth/claude/cookie_auth.go`)

## Overview
- **Priority:** P2
- **Status:** pending
- **Effort:** 1h
- **Description:** Create CLI command `--claude-cookie` that accepts a Claude.ai session cookie, authenticates via cookie->OAuth flow, and saves the token file. Follows `DoIFlowCookieAuth()` pattern exactly.

## Key Insights
- CLI commands are plain functions, not cobra commands
- Pattern: `DoXxxAuth(cfg *config.Config, options *LoginOptions)`
- Flag registered in `cmd/server/main.go` alongside other `--xxx-login` / `--xxx-cookie` flags
<!-- Updated: Validation Session 1 - org_uuid + capability naming, no email -->
- File path format: `{authDir}/claude-{org_uuid}-{capability}.json` (e.g., claude-44119bda-...-claude_max.json)
- No email in cookie flow; org_uuid is primary identifier
- Capabilities distinguish plan tiers (claude_max, pro, free)
- Duplicate checking by org UUID

## Requirements

### Functional
- Accept cookie via interactive prompt (consistent with iflow-cookie UX)
- Validate and normalize cookie input
- Call `AuthenticateWithCookie` from Phase 02
- Check for duplicate accounts (by org UUID or email)
- Save token file with cookie, org UUID, capabilities
- Print success message with email, capabilities, file path

### Non-Functional
- Follow existing `DoIFlowCookieAuth` pattern precisely
- No cobra framework dependency
- Graceful error messages (no stack traces to user)

## Architecture

```
User runs: cliProxyAPI --claude-cookie
  |
  v
DoClaudeCookieAuth(cfg, options)
  |-> Prompt for cookie
  |-> Validate/normalize
  |-> Check duplicates by email
  |-> AuthenticateWithCookie(ctx, cookie)
  |-> Save to claude-{email}-{ts}.json
  |-> Print success
```

## Related Code Files
- **Create:** `internal/cmd/claude_cookie.go`
- **Modify:** `cmd/server/main.go` (add flag + call)

## Implementation Steps

### claude_cookie.go

1. Create `internal/cmd/claude_cookie.go` with package `cmd`

2. Implement `DoClaudeCookieAuth(cfg *config.Config, options *LoginOptions)`:

```go
func DoClaudeCookieAuth(cfg *config.Config, options *LoginOptions) {
    if options == nil {
        options = &LoginOptions{}
    }

    promptFn := options.Prompt
    if promptFn == nil {
        reader := bufio.NewReader(os.Stdin)
        promptFn = func(prompt string) (string, error) {
            fmt.Print(prompt)
            value, err := reader.ReadString('\n')
            if err != nil {
                return "", err
            }
            return strings.TrimSpace(value), nil
        }
    }

    // Prompt for cookie
    rawCookie, err := promptFn("Enter Claude.ai session cookie (sessionKey=...): ")
    if err != nil {
        fmt.Printf("Failed to read cookie: %v\n", err)
        return
    }

    // Validate
    cookie := claude.NormalizeCookie(rawCookie)
    if err := claude.ValidateCookie(cookie); err != nil {
        fmt.Printf("Invalid cookie: %v\n", err)
        return
    }

    // Authenticate
    ctx := context.Background()
    svc := claude.NewCookieAuthService(cfg)
    tokenStorage, err := svc.AuthenticateWithCookie(ctx, cookie)
    if err != nil {
        fmt.Printf("Claude cookie authentication failed: %v\n", err)
        return
    }

    // Build file name using org_uuid + capability (no email in cookie flow)
    // <!-- Updated: Validation Session 1 - org_uuid + capability naming -->
    orgUUID := tokenStorage.OrganizationUUID
    capability := claude.ExtractPrimaryCapability(tokenStorage.Capabilities)
    fileName := fmt.Sprintf("claude-%s-%s", orgUUID, capability)

    authFilePath := fmt.Sprintf("%s/%s.json", cfg.AuthDir, fileName)

    if err := tokenStorage.SaveTokenToFile(authFilePath); err != nil {
        fmt.Printf("Failed to save authentication: %v\n", err)
        return
    }

    fmt.Printf("Claude cookie authentication successful!\n")
    fmt.Printf("Email: %s\n", tokenStorage.Email)
    fmt.Printf("Organization: %s\n", tokenStorage.OrganizationUUID)
    fmt.Printf("Capabilities: %v\n", tokenStorage.Capabilities)
    fmt.Printf("Expires: %s\n", tokenStorage.Expire)
    fmt.Printf("Saved to: %s\n", authFilePath)
}
```

### cmd/server/main.go

3. Add flag variable (near line 64, alongside `iflowCookie`):
   ```go
   var claudeCookie bool
   ```

4. Register flag (near line 82, alongside `iflow-cookie`):
   ```go
   flag.BoolVar(&claudeCookie, "claude-cookie", false, "Login to Claude using session cookie")
   ```

5. Add handler in the if-else chain (after the `claudeLogin` block around line 472):
   ```go
   } else if claudeCookie {
       cmd.DoClaudeCookieAuth(cfg, options)
   ```
   Place it right after the `claudeLogin` case and before `qwenLogin`.

6. Verify compilation: `go build ./cmd/server/...`

## Todo List
- [ ] Create `internal/cmd/claude_cookie.go`
- [ ] Implement `DoClaudeCookieAuth` following iflow_cookie pattern
- [ ] Add `claudeCookie` flag variable in main.go
- [ ] Register `--claude-cookie` flag in main.go
- [ ] Add elif branch for `claudeCookie` in main.go
- [ ] Verify compilation
- [ ] Manual test: `cliProxyAPI --claude-cookie`

## Success Criteria
- `cliProxyAPI --claude-cookie` prompts for cookie input
- Valid cookie produces saved auth file at `{authDir}/claude-{org_uuid}-{capability}.json`
- Auth file contains all fields (tokens, cookie, org UUID, capabilities)
- Invalid cookie shows descriptive error
- Help text shows `--claude-cookie` flag

## Risk Assessment
| Risk | Impact | Likelihood | Mitigation |
|------|--------|-----------|------------|
| Cookie paste truncated by terminal | Medium | Low | Document that long cookies should be pasted without line breaks |
| Duplicate account not detected | Low | Medium | Check by email in auth dir |

## Security Considerations
- Cookie is read from stdin, not command-line argument (avoids shell history exposure)
- Cookie stored in auth file with 0700 directory permissions (existing pattern)

## Next Steps
- Independent of Phase 04 and Phase 05
