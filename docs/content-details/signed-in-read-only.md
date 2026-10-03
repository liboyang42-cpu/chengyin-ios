# Signed-in activity and topic details

This dormant composition slice uses a separate typed `SignedInContentDetailReadApproval.activityAndTopic`. `homeAndSearch` does not authorize either detail route. The default deployment remains unconfigured, with no detail, runtime, registration, write, payment or provider grant enabled.

## Wire contract

- POST `api/activity/info` and POST `api/topic/info-to-user`, with exactly one multipart field `id`: a canonical positive decimal integer. No query, fragment, extra/duplicate fields, JSON body or method alternatives are accepted.
- Both routes require a complete current signed-in identity. A defensive server fallback does not make activity detail a guest route. The raw current Authorization credential must match exactly.
- Responses use numeric `code: 200` and a `data` object. Activity allowed-detail identity must match the requested ID; the existing topic service correlates its ID as well.
- An activity response `{ "gate": true, "clubId": ..., "message": ... }` is a distinct redacted state. It need not include an activity ID. It cannot render full detail, registration or play actions.
- Topic `activityList` is an optional summary shelf containing `id`, `name`, `imgUrl`, `addressName`, `startDate`, `endDate`. Omission/null remains unknown, an empty list displays an explicit empty state, and malformed/duplicate identities fail the detail load. Dates remain server text; no timezone is inferred. Each entry opens the exact activity ID through the same guarded activity-detail path. A shelf entry is not membership, registration, availability or runtime authorization.

## Session and UI boundaries

The normal composition checks account, role, token, session epoch and viewer revision before dispatch and after success/failure. Activity read and topic-session state also fence identity-only refreshes and role/session ABA before handling unauthorized errors. A current HTTP/envelope 401 expires the current session; stale or canceled results cannot expire its replacement. Guest cards display sign-in state with no detail dispatch. Active detail views observe the App session, so an owner or viewer change replaces the displayed projection.

The activity shelf adds a read-only destination. Existing action gates and downstream transport denials remain in place. No server authorization bypass or standalone detail transport is introduced.

## Verification scope

Core tests cover exact multipart shapes, malformed IDs, correlation, club gates, shelf omission/empty/error semantics and topic viewer ABA. App-hosted tests exercise synthetic phone/session restoration plus normal Home/Activities/detail composition, missing approval, partial identities, wrong routes, owner/role/session replacement, stale versus current HTTP/envelope 401 and cancellation. The DEBUG UI fixture injects a memory vault and a synthetic recorder into the normal composition and mounts the normal Home/Activities destinations; it never contacts a live API.

Python wiring checks are offline structural evidence only. Swift compilation, Core/App XCTest execution, simulator UI, physical devices and live service acceptance remain separate Apple/toolchain gates.

## Independent review corrections

The detail views own all initial, retry, pull-to-refresh and review-completion read tasks using `SignedInContentDetailLoadOwner`. Replacement or disappearance cancels the actual reader task before a late unauthorized response can expire the current session. SwiftUI task cancellation propagates to its specific read without canceling a newer replacement. View generations still fence visible state independently. Disappearance retains the existing NavigationLink subtree while a pushed child is open; session/viewer changes recreate the scoped detail view and reload its projection.

Added adversarial authored coverage includes missing/duplicate/extra/trailing multipart parameters, altered boundaries/hosts, current HTTP/envelope 403 without session expiration, restored authoritative-account reads, same-session dismissed/superseded HTTP/envelope 401, parent task cancellation, and omitted/empty/malformed topic shelves. Synthetic UI tests traverse the normal Home card to topic shelf to exact activity detail and back, plus dismissed retries, gate, guest, unapproved and forbidden states. These authored Swift/Core/App/UI tests remain UNRUN without an Apple toolchain. Parser and Python structure checks do not establish compilation or UI acceptance.

## Immutable backend evidence

The reviewed server source is the four exact blobs at published commit `36f9012761ec3b6d170c3f5b39d7c554a4c09ac5` (tree `d2fee9396c577515272aef1764ae6274dcaaa3ea`). The locally available review commit `4d6861556a994a454a97f5b2f2e9301d26c9db1e` contains identical relevant blobs; its entire tree is not asserted equal to the published tree.

- `ApiActivityController.java`: `1080676872aaf99e71ab2590bb0371420b0c3b7f`, exact POST info endpoint and redacted club gate with no activity ID.
- `ApiTopicController.java`: `cc8978c4b3a9a661b154c0c6e9449194c56e6688`, exact POST info-to-user endpoint, current app-user lookup, and TOPIC_SHELF activity summaries.
- `SecurityConfig.java`: `2fa9e73abd8f23e769a8552bff8ada3bed426df4`, anonymous activity/topic list exemptions do not include either detail endpoint; authenticated fallback remains required.
- `PublicActivitySummaryVO.java`: `78eb02fe8d7802e78d8c0773683ff9cc94b0298f`, six display fields only. Date strings are unzoned server text.

This is source-contract evidence, not live endpoint, deployment or account acceptance. No private backend implementation is copied into the native repository.
