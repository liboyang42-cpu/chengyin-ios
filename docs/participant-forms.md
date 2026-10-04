# Native participant mutations and forms

## Scope and evidence

Implemented locally against native baseline `e66571d`. Source inspected at Flutter commit `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`:

- `lib/data/api/address_api.dart`: list/info/action/delete/setDefault contracts and shared-row semantics
- `lib/data/api/participant_api.dart`: same underlying table/endpoints; its narrower save/default wrapper differs from the actual edit-page writer
- `lib/feature/account/address_edit_page.dart`: the real edit path calls **AddressApi**, reads `/info` before edit, shows only name/phone, trims those values and hidden address fields, and preserves loaded default metadata
- `lib/feature/account/address_list_page.dart`, `participants_page.dart`: participant management, not a shipping flow
- `test/feature/account/address_test.dart`, `address_edit_native_controls_test.dart`, `address_default_visibility_test.dart`, `test/feature/profile/participant_default_test.dart`: exact keys, native two-field form, and no visible default controls

No live requests or record changes were performed. No commits, pushes, app-session changes, root navigation changes, project changes, or String Catalog changes are included in this slice.

## Wire parity

All operations are POST multipart form-data with the existing raw `Authorization` token header. The existing no-redirect transport must be injected.

| Operation | Path | Fields |
| --- | --- | --- |
| Create | `/api/user/address/action` | `fullName`, `mobilePhone`, `isDefault=0`; no `id` |
| Edit | `/api/user/address/action` | `id`, edited `fullName`/`mobilePhone`, loaded `isDefault`, loaded nonempty `province`/`detailAddress` |
| Delete | `/api/user/address/delete` | `id` |
| Set default (capability only) | `/api/user/address/setDefault` | `id`, `isDefault=1` |

The actual edit page calls AddressApi.save, so native edits intentionally preserve hidden address/default values instead of substituting ParticipantApi's narrower save payload. `province` is the entire province/city/district string. There are no invented `city`, `area`, or `address` keys. Source trim-and-omit-empty behavior is retained; nonempty hidden field content remains intact apart from source-equivalent surrounding-whitespace trimming.

Create/edit validation now follows the current mini and backend: trimmed nonempty name and an 11-digit ASCII mobile number beginning with 13–19. See `participant-mini-phone-parity.md`; this supersedes the older Flutter-only validation rule. A displayed masked phone is never reconstructed or submitted. A failed or mismatched detail read cannot produce an editable empty draft.

Success requires numeric `code=200`; mutation `data` can be absent/null and is not assumed to contain a new record ID. Server business rejection and unauthorized responses retain code/message without logging raw request or arbitrary error descriptions.

## Native interface

- Existing read-only `ProfileParticipantsView(reader:)` and `ProfileParticipantDetailView(id:reader:)` remain available unchanged by default
- Injecting a retained coordinator adds the participant create sheet and fresh-detail edit/delete actions
- The form uses SwiftUI Form, native text fields, name/phone autofill and focus, a phone keypad, a pinned save button, native alerts, and cancel/dismiss protection while sending
- Save requires an explicit confirmation showing the frozen name/phone values
- Delete requires an explicit destructive confirmation naming the participant and explaining that any address on the same row is also deleted, with no undo
- No address-entry fields, shipping purpose, default badge, default toggle, or set-default button were added
- `setDefault` exists as a tested service/coordinator capability only because the source retains the endpoint while its UI tests explicitly forbid exposing that control. Wiring it needs a separately approved product change
- Account changes, stale load completions, unavailable detail reads, repeated save/delete taps, cancellation, and sheet dismissal have explicit guards

## Uncertainty and retry boundary

`ParticipantMutationCoordinator` is retained by the session owner across screens. Preparing/cancelling confirmation sends nothing. Confirmation submits one immutable intent at most once; a second tap or completed confirmation cannot replay it.

A transport error, cancellation after dispatch, malformed response, or non-authentication HTTP error is an **unknown outcome**, not evidence that no mutation occurred. The original account keeps an in-memory lock across dismissal/relogin. Stale account/token/epoch completions never invalidate a replacement session or expose a previous account's rows. Clear server rejections can be reviewed and confirmed again with a new intent; there is no automatic retry.

Unknown outcomes offer exactly one read per explicit readback tap:

- Create/delete: existing participant list read
- Edit/default: existing detail read for the known ID

Readback is only a snapshot. List pagination/completeness and create-response IDs are not guaranteed by the inspected contract; matching names or missing rows do not establish whether the earlier request completed. Therefore readback does **not** auto-unlock mutation or resubmit. A failed read can be explicitly retried without repeating the write. Dismissal discards readback PII and invalidates late read completion.

Limit: this is an in-memory duplicate guard, not backend idempotency or durable exactly-once behavior. It is not persisted across process termination. The retained source does not establish a safe request-ID reconciliation mechanism, so there is deliberately no automatic unlock/reset endpoint. Recovery beyond the displayed readback requires a separately verified reconciliation contract or explicit reviewed workflow.

## Root integration contract

1. Create optional `ParticipantService(configuration:transport:)` next to ProfileService, using the same explicitly configured endpoint and no-redirect transport
2. Retain `ParticipantSessionWriter(service:currentSession:onUnauthorized:)`; the live closure returns `ParticipantWriteSession(accountID:epoch:token:)` from the same verified account/token/epoch as ProfileReadSession
3. Retain **one** `ParticipantMutationCoordinator(writer:reader:onParticipantsChanged:)` for the lifetime of the session owner. Do not create it per form or reset it at logout. Call `synchronizeSession()` on session replacement/logout as well as screen entry
4. The unauthorized callback must expire only the captured matching session. The writer already verifies account, epoch and token before invoking it
5. Pass the retained coordinator through the account links to `ProfileParticipantsView(reader:coordinator:)`. The default nil argument preserves read-only integration
6. Use `onParticipantsChanged` to invalidate any independent participant/address/registration-picker cache. Existing list/detail screens refresh on return/dismissal; the callback enables other shared-row consumers
7. Merge the 22 entries in root `participant-localizations.json` into `Resources/Localizable.xcstrings`, then regenerate the project with `tools/generate_project.py`
8. Optional DEBUG launch routing can select `ParticipantFixtureHostView(scenario:)`; it is not wired into release or root navigation here

## Offline verification

Added 34 XCTest cases across `ParticipantFormTests`, `ParticipantServiceTests`, `ParticipantSessionTests`, and `ParticipantCoordinatorTests`. Tests use synthetic values and injected fake transports/readers/writers only. Coverage includes hidden-field preservation, source validation/fields/routes, absent success data, invalid preflight, timeout/cancellation/malformed responses, repeated confirmation, readback retries, dismissal, stale readback, account/epoch/token replacement, stale 401s, and shared-row invalidation.

DEBUG fixtures cover success, empty data, load error, server rejection, timeout after a fake mutation, unauthorized, and unconfigured states. Timeout-after-save intentionally changes the memory-only fake data and then reports uncertainty, so readback can be inspected without HTTP.

Local checks: `git diff --check` and a bilingual-key completeness check passed. An isolated temporary copy, with the supplied keys merged and project regenerated, passed `check_scaffold.py` (92 Swift source references and 553 bilingual keys, deterministic project regeneration); the tracked catalog/project were untouched. These are structural checks, not compilation. Swift/Xcode are absent from this Linux workspace; XCTest execution, SwiftUI compilation, simulator interaction, localization layout, VoiceOver, and Dynamic Type remain unverified until macOS CI/device acceptance. Existing read-only tests were not edited.
