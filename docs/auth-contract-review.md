# Authentication contract review

Source: existing public Flutter client, `lib/data/api/auth_api.dart`, commit `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`. This is client-source evidence, not a fresh backend validation.

## Observed operations

| Purpose | HTTP route | Body fields in source |
|---|---|---|
| Native WeChat login | POST /api/login/wechat/app | code |
| Apple login | POST /api/login/apple | identityToken |
| Password login | POST /api/login | username, password, optional code |
| SMS request | POST /api/sms/send | phone |
| SMS login | POST /api/login/phone | phone, code |
| Current account | POST /api/userInfo | none shown |
| Logout | POST /api/logout | empty form |

Existing request bodies use Dio `FormData` (multipart), not JSON. Native request encoding must be matched and tested against the server rather than inferred from field names. Existing comments describe historical SMS configuration problems; those are not a current health check.

Google / Facebook login routes are not present in this file. US availability does not itself establish backend support for these providers. Do not show working login buttons until client configuration, callback handling and server verification exist.

## Gates before connecting registration

- Confirm approved non-production API base URL, including gateway prefix, and test-account fixture lifecycle
- Review registration / merchant onboarding routes separately; a login endpoint is not automatically registration
- Verify native Apple nonce and identity verification requirements against actual server implementation
- Inspect server token header, expiry / refresh contract and business error envelope
- Store session credentials in Keychain, never preferences or source. Derive roles and approvals from the server, not the onboarding choice
- Reject expired / mismatched account responses after logout or account switching; cover refresh races and cancellation
- Logout should clear local credentials regardless of server failure, with remote revocation attempted under a bounded timeout
- Test callback cancellation, repeated taps, offline transition, foreground restoration, cold start and changed locale

No API calls were made during this review. No SMS, registration or business transaction was triggered.

## Foundation implemented (fixture validation pending at authoring time)

- Explicit HTTPS configuration with no default service URL; gateway prefix retained
- Multipart request bodies and raw `Authorization` header match current Flutter client source
- Typed login `data` versus bootstrap `appUser` response shapes, server role / userType fallback
- No refresh endpoint assumed: current Flutter network source explicitly says none is available
- URLSession ephemeral transport, cookies/cache disabled, credential-bearing redirects refused
- Keychain token storage scoped to the new native bundle with WhenUnlockedThisDeviceOnly
- Epoch-based stale-completion guard primitive; app-level lifecycle integration is a later step
- Local response fixtures only; no real login, SMS, payment or backend write performed

This foundation is not yet connected to the registration sheet. Google/Facebook, Apple authorization UI, merchant application, account recovery and a refresh mechanism remain unimplemented rather than simulated.
