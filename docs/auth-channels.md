# Native phone and Apple authentication channels

## Scope and evidence

This local additive slice implements the preserved Flutter contracts. It has no configured endpoint, signing capability, credentials, real SMS test, Apple account access, or live backend proof. The root integration owns navigation, project generation, localization import and session persistence; this slice does not edit `LoginView`, `AppSession`, the project or String Catalog.

Source inspected in the preserved Flutter checkout:

- `lib/data/api/auth_api.dart`: `sendSmsCode`, `loginWithPhone`, `loginWithApple`, `userInfo`
- `lib/feature/auth/phone_login_sheet.dart`: phone/code fields, explicit send/resend, one-time-code autofill, six-digit field limit, feedback, shared form and dismissal behavior
- `lib/feature/auth/auth_controller.dart`: Apple email/full-name scopes, `identityToken` exchange, neutral incomplete-authorization result, validated token/account and serialized persistence
- `lib/feature/auth/login_gate.dart`: phone form expands in the existing gate; no automatic nested sheet or automatic resend
- `lib/feature/legal/legal_doc_page.dart`: implied-consent footer with separate user-agreement and privacy links
- `lib/feature/legal/legal_docs.dart` and `tool/legal_doc_gate.py`: privacy body is a pending placeholder; release gate requires nonempty body/version/date
- `ios/Runner/Runner.entitlements`: Flutter entitlement does not establish signing/capability configuration for the separate native application

The source comments record SMS-provider and Apple-backend configuration failures observed on 2026-09-19. Those are historical observations, **not a current availability finding**. This work did not probe either live channel.

## Contracts

All channel writes are explicit user actions and use the established multipart builder, raw-token validator and HTTPS configuration. Gateway path prefixes are preserved.

| Action | Route | Form fields | Success |
|---|---|---|---|
| Send OTP | `POST /api/sms/send` | `phone` | `code == 200` |
| Phone sign-in | `POST /api/login/phone` | `phone`, `code` | `code == 200`, valid `token`, `data.id > 0` |
| Apple exchange | `POST /api/login/apple` | `identityToken` | Same login result |
| Verify current account | `POST /api/userInfo` | No body; raw `Authorization` | `code == 200`, `appUser.id > 0` |

The client accepts eleven ASCII phone digits, matching the source sheet, without inventing a country-code route. Code input is one to six ASCII digits, matching the source nonempty validation and six-character field limit; the backend decides whether a code is correct. The source documents server six-digit issuance and five-minute expiry; no local timer claims a server code remains valid.

`AuthChannelService` returns existing `LoginResult`/`Account` and delegates current-account reads to `AuthService`. The coordinator additionally reads current account before commit and rejects an account ID differing from the login response. This readback is native hardening; no refresh-token or new registration endpoint is invented. Apple tokens are opaque: validating transport characters does not validate a JWT signature or audience. The server remains responsible for those checks.

## Root integration

Retain one `AuthChannelCoordinator` for the session owner, including while its sheet is dismissed. This preserves the in-memory SMS cooldown. Construct it with an optional configured `AuthChannelService`, a live session snapshot reader and a synchronous main-actor writer:

```swift
AuthChannelCoordinator(
    service: configuredChannelService,
    appleConfigurationVerified: false,
    currentSession: {
        AuthChannelSessionSnapshot(
            epoch: gate.currentStamp,
            accountID: account?.id,
            isBusy: isWorking
        )
    },
    commitLogin: { result, expected in
        guard gate.currentStamp == expected.epoch,
              account?.id == expected.accountID,
              isWorking == expected.isBusy,
              account == nil, !isWorking else { return false }
        try vault.write(result.token)
        // Only after successful storage; do not suspend between checks and assignment.
        gate.invalidate()
        UserDefaults.standard.set(false, forKey: restoreBlockedKey)
        token = result.token
        account = result.account
        errorKey = nil
        return true
    }
)
```

The snippet illustrates the contract; adapt captures/ownership to the existing `AppSession`. `false` means reject a stale commit; thrown errors show storage failure without reporting successful login. Never put a second asynchronous task, unguarded write or secret logging inside this callback. Never publish an account before its token is stored. Login role comes from the server/current-account response, not player/merchant intent.

`AuthChannelView(coordinator:sessionSnapshot:legalReleaseContentVerified:onOpenAgreement:onOpenPrivacy:)` is a standalone native sheet. Pass a fresh snapshot from observable root state on each update. The coordinator rechecks the live reader even if a SwiftUI update is delayed. Present it from one explicit additional-sign-in action; it does not mutate shared navigation itself. Close/swipe-away/navigation clears phone and OTP state and invalidates late results. Call `coordinator.cancel()` when the host abandons the flow or changes sessions. Do not reset the host bootstrap operation merely for opening/closing this form.

The view owns an in-memory model. The OTP is cleared immediately on submit, on phone changes and on disappearance. Async request-local copies may remain until the suspended request unwinds; they are never logged or persisted. Apple identity tokens are never published into view state or storage. Only the final backend token reaches the existing session writer.

## Error, resend and cancellation rules

- One channel operation at a time; repeated taps and repeated Apple completions cannot dispatch duplicate requests
- No automatic SMS retry, OAuth retry, token exchange retry or code submission
- Conservative 60-second local SMS cooldown begins before dispatch, across phone edits and form reopening; only an explicit tap after expiry sends again
- Cancellation/timeout/unknown SMS response cannot prove non-delivery; the UI says to check messages and wait before a manual retry, and preserves cooldown
- HTTP or business code 429 has a distinct rate-limit result. The transport does not provide response headers, so no `Retry-After` duration is invented
- Structured API failures retain numeric classification internally; arbitrary raw server/transport text is not displayed or logged
- Cancelling the form prevents local commit even if a transport ignores cancellation. It cannot retract a request already delivered to the server
- Older success or 401 cannot replace/sign out a newer session, including a same-account session with a newer epoch
- Apple cancellation/incompletion is a neutral explanation with retry/alternative guidance, because that signal alone does not distinguish user dismissal from unavailable device-account authorization

## Required release configuration

Phone code remains implemented and usable with an explicitly configured test/backend transport. Missing legal content is not an undocumented all-channel switch. Instead, the form shows a visible warning until approved agreement/privacy content and both navigation callbacks are supplied.

Before release, the owner must supply reviewed app-specific legal documents and reachable navigation, confirm applicable consent behavior, configure the approved HTTPS API, and separately validate SMS provider delivery, server limits, OTP expiry and rejection. Do not copy the source privacy placeholder as an approved policy or label this source review as legal approval.

Apple is explicitly disabled by default. `appleConfigurationVerified` must remain `false` until the native App ID/bundle ID, signing team, Sign in with Apple entitlement and provisioning capability, backend accepted audience/client ID, app-specific privacy disclosures and approved device test are verified. This slice neither adds an entitlement nor changes Apple/backend configuration. A disabled explanatory row replaces the active Apple control.

When enabled, the adapter uses Apple's real `ASAuthorizationAppleIDButton` and `ASAuthorizationController`, requests only the source email/full-name scopes, and forwards only `identityToken` to the existing backend. Each controller/ticket is bound to one attempt. Dismantling cancels the native controller and invalidates callbacks. No third-party authorization is initiated by rendering the view.

Apple primary API references: [authorization controller](https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller), [cancellation](https://developer.apple.com/documentation/authenticationservices/asauthorizationcontroller/cancel()).

## Verification

Added synthetic service/coordinator tests cover route/body/auth shape, malformed credentials/results, input rejection before dispatch, HTTP/business errors, cooldown, duplicate taps, storage failure, current-account mismatch, cancellation, stale 401/session replacement, Apple disabled state, cancellation and repeated/stale Apple callbacks. Controlled continuations intentionally ignore cancellation; no actual SMS, network, OAuth account or credentials are used.

This Linux workspace has no Swift/Xcode toolchain. Swift package tests, iOS type checking, native Apple UI rendering, VoiceOver/dynamic-type behavior and simulator/device execution **have not been run for this slice**. Six existing Python importer tests passed. A temporary integrated copy passed the project/catalog structure check with all 25 bilingual additions (90 Swift source files, 556 catalog keys). These checks verify structure only and did not change the worktree project/catalog. The 21 added Swift tests are authored but unexecuted here. Root macOS CI must run `swift test`, unsigned simulator/device builds and applicable UI tests after integration. Fixture tests are not live-backend or release acceptance.

## US rollout limitation

The retained source validates an eleven-digit local phone number, with no verified country-code/E.164 request field. English UI does not establish US SMS support. An international phone contract and provider delivery acceptance are required before marketing this flow as US-phone sign-in. No Google/Facebook route or regional backend behavior is invented.
