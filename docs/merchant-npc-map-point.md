# Merchant NPC roaming point: manual GCJ-02 editor

## Scope and status

A source-backed manual point editing slice on the existing NPC settings screen. It adds the missing “漫游落点 / Roaming map point” entry, owner-scoped read-only details for COOP_MANAGE users, explicit manual GCJ-02 input, local draft, frozen review, dormant save, and authoritative readback. Visual map picking is still incomplete. This does not claim full mini-program parity, real service activation, NPC publication, arrival verification, AI trial-chat quality, or W04/W05/AI48 acceptance.

Native baseline: published commit `37b49e2602da58a33a5d2b7fa0a679aec6059e22`, tree `583a803d314ec40152063647547278177c6d3738`. This candidate was authored from an independently copied, identical tree. No push is part of this slice.

## Verified source gap

At the private backend reference `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/merchant/decor/ai-npc/index.wxml`, blob `c390dc72f237add08f5ab66333b36a63d290745b`, lines 85–91: a “漫游落点” row opens the location chooser.
- The matching `index.js`, blob `d0088bf4d71158bc2b5cc19e7b4e1db32c4fc0b3`, lines 183–201 and 336–349: read `/api/merchant/coop-profile`; choose a location; POST exactly `locationLat`, `locationLng`, and `address` to `/api/merchant/decor/save`; read the profile again. Coordinates, rather than an address alone, determine whether a point exists. Numeric zero is not discarded.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiMerchantController.java`, blob `ac739a411d2de90de83bebecf482508e1d363a2a`: the read requires `COOP_MANAGE`; the write requires `PROFILE_WRITE`. Both derive the merchant from the authenticated access context. Address length is bounded at 255 Java UTF-16 units. The write handles `locationVerified` server-side merely when both coordinates are present; it is not an arrival certificate.
- `MerchantEditProfileVO` inherits the public id/address/location projection, then adds editor-only fields. The new native DTO decodes only id/address/latitude/longitude.

The baseline NPC editor had character fields and the twelve preset images, but no point row or editable point workflow. The generic decoration DTO preserved coordinates as hidden fields. The mini-program NPC page has no self-service enabled switch or test-chat button; CMS enablement is a separate privileged interface and was not reproduced here.

Private source content is not copied into this candidate.

## Coordinate contract and deliberately limited UI

Tencent's [official location API documentation](https://intl.cloud.tencent.com/ind/document/product/1219/57733), `chooseLocation` callback, specifies GCJ-02 for the returned latitude and longitude. Apple's [CLLocationCoordinate2D documentation](https://developer.apple.com/documentation/corelocation/cllocationcoordinate2d) specifies WGS 84. Those facts do not establish an accepted regional conversion or MapKit point-picker contract.

This feature reuses the existing `WalkingCoordinateDatum` enum and `RoamCoordinate` finite/range validator. It does not instantiate MapKit, a geocoder, a location manager, a device-fix provider, or a coordinate converter. No location, map-provider or live business-API request was made during this work.

The user manually enters latitude, longitude and the store address and explicitly declares the input GCJ-02. That declaration expresses input semantics only; it does not authenticate the source, establish geography, or certify arrival. Nil and WGS84 declarations fail closed. Editing any input resets the declaration. The sheet displays exact numeric draft values before local application. It accepts valid zero and negative values, rejects missing/partial/non-finite/out-of-range coordinates, and never guesses a city or coordinate.

The ordinary UI explains that visual map selection still awaits regional/datum verification and that a store display point is not NPC publication or arrival proof. The source `locationVerified` field is neither decoded, displayed, nor submitted.

## Flow and safety boundaries

1. Existing merchant tools → character/NPC settings → “漫游落点”. A failed point read remains an error rather than a fake saved location.
2. The `.npcMapPoint` read requires the existing COOP_MANAGE permission, matching the backend. The service uses POST `/api/merchant/coop-profile` with JSON `{}` and checks returned merchant id against current access. Details hold no editable draft or confirmation. Only a fresh snapshot with both COOP_MANAGE and PROFILE_WRITE offers the existing editor; its write preflight independently requires both permissions again.
3. The manual sheet captures scope, draft identity and the original point. Opening, typing and cancellation do not change the parent draft or issue a save. Apply changes only the local point draft; stale, duplicated, dismissed, backgrounded, reloaded, concurrent-edited or wrong-account sheets cannot apply.
4. The existing immutable confirmation captures the exact latitude, longitude, address and GCJ-02 label. No request is added on sheet dismissal or navigation. Production writes remain disabled without the already-existing independently injected endpoint grant and durable journal.
5. Before a permitted send, the existing service checks current session, access, merchant identity and unchanged baseline. Exactly three JSON fields are sent; no owner id, NPC fields, unrelated decoration fields or client verification bit is submitted.
6. Point saves share `merchant:storefront` with profile/decor/gallery/story/business-status writes. Unknown outcomes retain the existing durable replay lock; reading a point or reopening the editor cannot clear that lock.
7. After acknowledged save, the coordinator clears the local proposal and rereads the owner-scoped point. It displays returned values even if they differ from the proposal. Failed/foreign-owner readback is explicitly reported without re-sending or claiming the proposed point is saved.

The feature does not change AppSession, composition grants, provider configuration, project wiring, the main localization catalog, CI, preset artwork, character fields, or any other line's business functionality.

## Verification

Executed in the dot Linux workspace:

- Point-focused Python source contracts: 28 passed (13 original plus 15 read-only contracts).
- Related `test_merchant_*.py` Python source contracts: 184 collected, 181 passed, 3 skipped because their external source inputs are unavailable. Skips are not source-verification passes.
- `git diff --check`: passed.
- Supplementary Tree-sitter syntax parse: 5 changed Swift files passed, with no recovery diagnostics. This is not Swift typechecking.
- Exact source blob hashing and unchanged writer-byte verification: recorded separately with the local candidate evidence.

Authored for the Apple/Swift toolchain, not executed here:

- 23 core XCTest cases covering source shape, valid zero values, missing/invalid coordinates, owner identity, exact three-field payload, datum rejection, dual permission checks, default-off live writes, preflight, changed baseline, readback truth, replay locking and stale sessions.
- 12 app-hosted XCTest cases covering cancel/apply, unchanged selection, explicit datum, reconfirmation on edits, invalid/zero inputs, concurrent edits, reload, account changes, unknown-write locking and late apply.

Swift and Xcode are unavailable in this workspace. Swift compilation, XCTest, simulator/device builds, screenshots, VoiceOver, large text, keyboard behavior and live role/backend behavior remain NOT RUN. Do not interpret Python source checks as runtime or device acceptance.

## Integration and remaining acceptance

The integrator must merge `Resources/MerchantNPCMapPointLocalizations.fragment.json` into the main catalog, regenerate existing Xcode project wiring for the new Core/App and AppUnitTests files, and run Swift/core/app-hosted tests plus relevant builds. Neither shared generated file was edited by this candidate.

Verify on an approved Apple setup: role/realm changes while the sheet or confirmation is open; repeated apply/confirm; Back/Cancel/reload; keyboard and large text; VoiceOver order; read denial; acknowledged-save/readback failure; uncertain send followed by refresh/reentry; ordinary NPC navigation return. Live read activation requires the existing deployment configuration and COOP_MANAGE permission. Save activation additionally requires PROFILE_WRITE, the existing write approval, and the durable journal. No approval is created by this feature.

A future visual map picker separately needs a verified provider, explicit regional and coordinate-datum contract, accepted conversion if required, cancellation/lifetime evidence, and real-device map placement checks. The manual editor does not close that gap.

### R1 review correction

The three new core-test access projections (shared success fixture, permission matrix, and revoked-permission reply) now include the existing required `roleCode: MERCHANT_OWNER` and positive merchant id. The app tests reuse `MerchantOperationsFixtureReader`, whose access projection already supplies both. A new static fixture check validates all literal active access projections and the dynamic matrix. The production identity decoder is unchanged; roles alone still grant no permissions. Swift/XCTest remain NOT RUN.

## Read-only parity increment

This increment is layered on the independently reviewed R1 candidate tree `d290636505675cabaf85962b945199c2ef866622`. Its exact scope is nine paths, including only the map-specific read guard in `Core/MerchantOperationsService.swift`; no other operation's read gate changes. `MerchantOperationsAccess`, the entire service save implementation, shared coordinator/session reader, original point DTO/manual editor, frozen-review logic, owner checks and durable pending-write behavior remain unchanged.

The NPC entry now opens a separate saved-details view. Its read-only coordinator checks COOP_MANAGE before requesting the point, matches the result to the access merchant, and rechecks access and the merchant after the response. PROFILE_WRITE revocation preserves permitted read-only visibility but removes the edit entry. COOP_MANAGE revocation or a mismatched owner discards the result. Scope changes, sign-out, dismissal, backgrounding and interrupted reads cannot retain a visible stale point. A failed reload clears the old point rather than presenting it as a fresh success.

A pending storefront write permits inspection of the last read point, displays the existing unknown-outcome warning, and suppresses the edit entry. Read-only load/reload never writes or clears the pending journal. A successful read is not reconciliation of that write. The existing writer still independently checks both permissions, current owner/session, unchanged baseline, endpoint approval and pending lock before sending the unchanged three-field patch.

New authored tests, not executed in this workspace:

- 18 core XCTest cases: real recognized roleCode fixture decoding, role names without inferred permissions, exact COOP-only read request, missing/inactive read access, foreign owner, a COOP-only user attempting the explicitly approved writer (zero write requests and zero journal changes), the real session-reader read-only path, unchanged gates for other operations, reload/dismiss zero-save behavior, dual-permission edit entry, same-session permission revocation, stale scope/sign-out/invalidation, retained unknown lock, and failed reload.
- 15 app-hosted XCTest cases: read-only display with valid zero coordinates, repeated load/dismiss without writes, dual permission edit entry, background/dismiss invalidation, account changes, owner role without PROFILE_WRITE, unknown write visibility, malformed role fixture denial, queued refresh after close/reopen, cancellation before dispatch, stale scope before dispatch, background/resume, and inactive appearances.

The details screen uses a stable navigation destination, so clearing its read snapshot on disappearance does not remove the pushed editor route. The new bilingual copy explains read-only access and labels the separate editor entry. Source-level and syntax checks do not establish Apple compilation, XCTest execution, navigation appearance, VoiceOver, device behavior or live role acceptance. Those remain NOT RUN. Project wiring and the main localization catalog are left to integration, as for R1. No push or live API operation was performed.

### Read-only R1 lifecycle correction

Read-only R0 invalidated an in-flight coordinator correctly, but an unstructured refresh queued before dismissal could start afterward and obtain the new appearance implicitly. The shipped app model now has an explicit visible-appearance token paired with the reader scope. Activation occurs synchronously on appearance or foreground return while still visible. Disappearance and backgrounding clear that token; reopening in the same account/scope creates a new UUID. Scope changes also invalidate the previous intent.

The toolbar captures its exact intent before creating a task. Initial, scope-change and foreground reads use a task keyed by the token with a synchronous capture list; the asynchronous closure cannot activate an appearance. Before entering the coordinator, load rejects cancelled tasks and stale, absent, hidden or wrong-scope intents, so those paths cannot dispatch even access/me. Current-appearance refreshes remain supported. Eight added app-hosted regressions exercise the actual shipping model and assert access, document and save call counts. These XCTest cases remain authored but NOT RUN; four new source-contract checks and supplementary syntax checks run in this workspace.

R1 changes only the read-only app model/view lifecycle, its dedicated app tests, read-only source checks and this document. Core read authorization, role/owner checks, the full service writer, manual editor and pending journal semantics are byte-identical to read-only R0. A separate R0-to-R1 delta accompanies the full replacement patch.

### Read-only R2 task identifier correction

SwiftUI task(id:) requires an Equatable identifier. RefreshIntent retains synthesized equality for its two UUID fields, including Optional equality at both task-id call sites. Hashable is not required by this API. The source check protects equality and both bound task call sites; this does not change lifecycle behavior, permissions or writer code. Swift/Apple compilation remains NOT RUN. Reference: https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)
