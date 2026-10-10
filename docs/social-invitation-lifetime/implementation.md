# Invitation history: presentation-owned reads

New bounded work dated 2026-10-10, based on native commit
`34928c87f43a6b97bfc0b01f8bcc8dba0d9b1631`. This is not a recovered October 9
work package, a claim of complete migration, or evidence of production readiness.

## Master mapping and verified source gap

MASTER v10 P118 maps invitation history to `App/SocialInviteHistoryView.swift`.
Its PA01 acceptance calls for ordinary entry, data and interaction checks,
loading/empty/error/offline states, return navigation and account-switch cleanup.
This increment covers the lifetime of the existing private read screen only.

At the base commit, the view used `.task(id: reader.identity)`, an integer
request generation, and independent button `Task` closures. Its rendering and
completion checks did not include the reader object or presentation revision.
A replacement reader with the same visible account identity was not a reload key.
A delayed button closure could begin after disappearance and acquire a fresh
integer generation. Disappearance invalidated that integer but did not own or
cancel all requested work. The underlying production reader's complete-session
and cancelled-401 checks already existed and are retained.

## Change

The existing view file now contains `SocialInviteHistoryModel`. It provides:

- A unique model owner and a new UUID for each visible presentation. Appearance
  opens the presentation synchronously; a delayed request cannot reopen it.
- The existing `SocialReadPresentationKey`, including reader object identity,
  account/epoch/role identity, presentation revision and configuration state.
  Replacement, logout, role/credential ABA and configuration changes retire work.
- A synchronous non-published render binding cancels and fences the old reader
  before SwiftUI `onChange` runs, including same-session reader replacement. Its
  unique ID also retires reader A-B-A before callbacks are delivered.
- Render-captured permits for retry, pagination and pull-to-refresh. All reads
  use one owned task, with a fresh request UUID and captured page number.
- Checks before dispatch, after completion, on errors including 401, and in
  completion cleanup. Old completion cannot clear a newer request's loading state.
- Cancellation on disappearance, reader replacement and refresh supersession.
  Refresh cancellation is forwarded to its exact task. Keys/permits remain
  independent guards even when a reader ignores cancellation.
- Retained scoped rows on disappearance so a pushed public-profile destination
  does not lose its owning NavigationLink. Hidden permits are nil; reappearance
  resets to page one. Key mismatch immediately hides old rows in the view.
- Existing source pagination, separate total versus loaded count, partial reward
  semantics, ordinary-error retry and current-401 private-data clearing.

Only the existing app file and existing app-unit test file change Swift source.
Both are already Xcode target members; no new PBX wiring is needed. AppSession,
shared locales, production approvals, service requests and Core contracts remain
unchanged. There are no writes, uploads, deployments or enabled capabilities.

## Authored directed Apple tests

Sixteen app-hosted tests are added in the already-wired
`Tests/AppUnitTests/SocialPresentationIdentityAppTests.swift`, in
`SocialInvitationHistoryLifetimeAppTests`. Held continuations permit deterministic
completion order; no timing sleeps pretend to exercise the race.

1. Current success retains separate total and unknown reward state.
2. Same-identity close/reopen rejects old success, ordinary failure, 401 and defer.
3. Same-identity reader replacement rejects those results and stale actions.
4. Same-presentation refresh supersedes older requests without old cleanup.
5. Closed screens reject late outcomes, queued refresh and pagination.
6. Covered navigation retains scoped rows and rewards; reappearance reloads page one.
7. Another model cannot use the same reader's foreign owner permit.
8. Account, epoch, role, presentation revision, configuration and logout changes
   hide stale presentation and reject success/error/401 before cancellation or rebinding.
9. Guest and unconfigured readers perform no dispatch.
10. Duplicate appearance and pagination dispatch once; failed page retry is exact.
11. Current unauthorized clears private rows; ordinary failures retain rows.
12. Refresh cancellation rejects delayed unauthorized and ordinary failures.
13. A real `SocialAccountSessionReader` with an injected held transport does not
    expire a session after close for HTTP 401 or envelope 401.
14. Current HTTP/envelope 401 still reaches the session expiration callback.
15. Binding a new reader before `onChange` rejects old actions, lifecycle calls,
    results and real-reader HTTP/envelope 401 session-expiration side effects.
16. Reader A-B-A within render callbacks gets a fresh binding and request lifetime.

These are authored tests, not executed App results. Execute on the approved Apple
runner with the existing QuestifyAppUnitTests target, selecting
`SocialInvitationHistoryLifetimeAppTests`. Also exercise invitation → public
profile → Back → reopen and pull-to-refresh on an actual simulator in both
languages. No UI, VoiceOver, Dynamic Type, device or live-backend pass is claimed.

## Verification boundaries

The local output packet includes exact commands, logs, source hashes and a
machine-readable verification summary. Python assertions inspect source structure
and preserve the negative controls; they do not compile or execute Swift.

- Focused new Python contracts: 8 passed.
- Scaffold: passed, with existing source/locale/PBX consistency.
- Social Python regression: 59 tests, 2 failures. Both failures were reproduced
  at the clean base (51 tests, the same 2 failures): a stale hard-coded social-key
  count of 107 versus 114, and an old TicketWalletDetailView protection hash.
  This increment does not change either protected area or weaken those tests.
- Full Python discoveries ran before the final render-binding refinement; see
  packet summary for actual counts and base comparison. Final render-binding
  checks are separately recorded; no final full-suite pass is claimed.
- Swift compilation, Swift XCTest, App-hosted XCTest, simulator/UI tests, device
  and live-service checks: NOT_RUN. This Linux workspace has no `swift`,
  `xcodebuild` or Apple SDK. Passing source checks cannot replace those stages.

No claim is made that all PA01, TC01 or TC02 requirements are complete.
