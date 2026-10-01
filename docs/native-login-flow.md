# Native login flow

The first wired slice supports an **existing username/password account**, using the source-aligned login and userInfo contracts. It does not yet create player or merchant accounts or launch Apple/WeChat authorization.

## Configuration

The build intentionally has no usable service endpoint. Set `QUESTIFY_API_BASE_URL` in an ignored `Config/Local.xcconfig` only to a reviewed endpoint, preserving the gateway prefix. Xcode configuration files interpret `//` as comments: use `https:/$()/your-approved-host.example/prod-api` as the xcconfig syntax pattern, replacing the hostname only after approval. That is an example, not a functioning API. Inspect the built Info.plist `QuestifyAPIBaseURL` before testing. Never put credentials or private server secrets here.

## Session behavior

- Server-confirmed account ID is required before the signed-in account view appears
- Tokens use a new-bundle Keychain namespace; Flutter sessions do not transfer automatically
- Each login / cancellation / logout advances an operation epoch; stale response completions cannot replace the current account
- Closing an in-flight login discards its result; the server may still have processed the request
- Logout clears in-memory state immediately and persists a non-secret restore-block flag before attempting Keychain deletion
- Remote logout uses only the captured previous token and cannot clear a subsequent login
- Bootstrap 401 blocks old-session restoration; offline/server errors preserve stored credentials and display a safe error when entering login
- Duplicate sign-in taps are ignored; passwords are cleared when the form disappears or the request completes
- Navigation sheets use one destination state to avoid presenting settings and login simultaneously

## Still required

Fixture tests verify transport/model primitives, not app session lifecycle or Keychain runtime behavior. Add native UI and session integration tests, verify actual backend configuration with non-production accounts, implement full registration and merchant approval, and then migrate real post-login pages. The current signed-in account screen explicitly marks remaining business features as pending.
