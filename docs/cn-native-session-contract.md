# CN native SMS and account session contract

## Scope

Normal composition is default-unconfigured. A reviewed exact CN endpoint, native bundle/deployment storage scope and `domesticChinaPhone` capability evidence are all required. A flag is not provider evidence. The retained password-only adapter is incompatible with its existing route prerequisite and cannot be activated through `usernamePassword`. Apple, WeChat and US login remain independently closed.

This source alignment does not claim a usable deployed login. Do not send an SMS, create an account, enroll a device or use real credentials as part of fixture tests.

## Exact request and response contract

All URLs retain the reviewed gateway prefix and exclude query/fragment. All requests are POST with `Accept: application/json`; redirects carrying credentials are refused.

- `/api/sms/send`: canonical multipart with exactly `phone`, eleven ASCII digits starting with 1. No Authorization header. A response succeeds only when HTTP is 2xx and business `code` is 200.
- `/api/login/phone`: canonical multipart with exactly `code` (six ASCII digits) and `phone`, no Authorization. Requires business 200, a nonblank header-safe token and positive `data.id`. No requested role or registration intent is transmitted. Existing server behavior may register a previously unknown phone account, so approved legal/consent content is a release prerequisite.
- `/api/userInfo`: bodyless POST with the raw session token in Authorization. Requires business 200 and a positive `appUser.id` or `appUser.userId`; the explicit `role` must be `player`, `club` or `merchant`. `nickname`/`nickName` aliases remain supported. Missing/unknown role does not fall back to a privileged presentation or establish a native session.
- `/api/logout`: canonical empty multipart, raw old session token in Authorization. No SMS, account selector, password, provider credential or role field.

Exact-byte checks reject extra/duplicate fields, arbitrary role/identity fields, malformed multipart framing, oversized payloads and unsupported paths/methods before transport. Current-account readback must match the login result's account ID before Keychain is written and the current session is published. Server presentation role never grants feature or merchant/club operation permission.

## Denied and interrupted outcomes

HTTP 401 or business 401 is unauthorized. Existing provider-unavailable, wrong/expired OTP and some rate-limit results are HTTP 200/business 500; they are failures, not successful delivery/login. HTTP/business 429 is also handled. No automatic resend or login retry is performed. The conservative 60-second local send cooldown starts before dispatch and survives form dismissal.

Cold restore sends only userInfo using the matching bundle/market/endpoint/realm vault. A 401 closes local restoration and clears the credential; transient failure or an incompatible account projection preserves the stored credential without exposing an authenticated account. Logout first invalidates the local session, persists its restore tombstone and clears Keychain, then attempts remote revocation using the captured old credential. Failure cannot revive the session. Existing epoch/viewer-revision checks fence stale responses and role/account ABA transitions.

## Native close and form behavior

The CN entry names phone sign-in explicitly and never displays the unsupported password form. Phone input requires eleven ASCII digits starting with 1; code input requires exactly six ASCII digits. Entry copy discloses that enabling SMS for a new phone may create a player account. Approved legal content and live-provider acceptance are still separate release prerequisites.

Closing the parent login flow invalidates the phone coordinator synchronously before sheet dismissal, including a pending login exchange or account readback. Late success and unauthorized replies cannot persist a credential or publish feedback into a later form. The sheet continues to clear phone/code memory on dismissal while the session-owned SMS cooldown survives reopening.

The normal-root synthetic tests cover exchange/readback cancellation, identity and role rejection before persistence, unauthorized versus transient cold restore, Keychain-write failure, logout deletion failure plus recreation, and a delayed old logout after a newer login. The native UI tests assert that password fields remain absent and valid-looking phone/code input cannot enable an unconfigured build. Authored tests are not passed tests until executed under the Apple toolchain.

## Required activation evidence

- Approved exact CN endpoint and matching deployment/session namespace
- Reviewed server implementation of the current public role-bearing session projection and existing session revocation
- Authorized SMS provider setup and approved sender/template, shared rate limits, atomic one-time OTP consumption, delivery/expiry/rejection acceptance
- Approved native legal content and consent behavior, including existing new-account behavior
- Apple toolchain execution of final integrated Core/AppUnit tests, UI interruption checks and separately authorized device/provider acceptance

Device enrollment is authenticated post-login work. It cannot supply a missing bootstrap identity or bypass attestation/challenge requirements. No signing, entitlement, credential, auth configuration, provider or deployment changes are included.

## Evidence limits

The new/updated native request and normal-root recorder tests are synthetic and authored for Apple CI. Local Python contract checks and syntax parsing are supplementary source evidence only. Swift typechecking, XCTest, device storage, actual SMS and deployed acceptance have not run in this Linux workspace. A compatible backend packet is reviewed separately; client publication cannot imply that server changes have been deployed.
