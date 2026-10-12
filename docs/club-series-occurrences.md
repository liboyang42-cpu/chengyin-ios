# P049 inline series occurrence reading and event return

## Exact base and scope

Base `49c68c6420270b0a0cc7ec8d18bc8561f329d796` plus the sealed batch14 roster patch (SHA256 `917f88cd1c1c41aa99ac402cac365ba4c3d9b90519b1204622c56800e68e42df`). Composite preimage tree: `e6fececc9f664940c0c424a406f9fd82e97cd9c2`. `App/ClubGovernanceViews.swift` preimage Git blob: `8eea210172f277bfb88694226b4f26d9fae1de3c`.

Only the single `dataRows` `operation == .series` block is modified in the shared file. Its existing series-detail link remains. Every byte outside this block, including batch14 roster changes, is preserved. There is no dependency on batches11–13's shared command form. P043 remains paused and receives no implementation in this packet.

The unique master `MASTER-v10-extracted-text.txt`, P049 lines1668–1671, names `loadSeries`, `toggleSeriesDates` and `beginEditSeries` in the ordinary club governance flow.

Exact Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- `pages/club/event-ops/index.js`, blob `8619be05e9cf8f05b0fde678a30b723b6df6ace8`: lines314–353 define occurrence rows and display-clock semantics;601–626 define inline open/close and the scoped read.
- `pages/club/event-ops/index.wxml`, blob `1cc5d36acbd475f76309f5b82c5a768ff3cf6552`: lines110–151 show one expanded series, historical/cancelled rows and loading/error/empty states. Editability is a badge, not an edit button.
- `utils/datetime.js`, blob `2163e57af3d7d8cc47b879970a2e96d3c4371ed7`: lines38–102 strictly parse wall/offset/epoch values;149 onwards project the fixed China clock.

Before this packet, the native series list offered only series-detail navigation; occurrences were a separate generic read page. The missing feature is the complete same-row disclosure/read/status/retry/close flow, using the existing event-workbench destination for a returned activity.

## Ordinary usable flow

An ordinary series row receives its real club/topic/series target and the existing access, identity and coordinator, without a nil callback, synthetic-only injection or AppSession change. Its secondary button expands the series' returned dates. Existing parent `filter` state stores the one expanded series ID, so opening another closes the previous one; no occurrence read starts while collapsed.

The existing `.occurrences` contract reads POST `api/club/event-ops/series/occurrences` with clubId and seriesId. No new endpoint, query option, permission or write is introduced. Fresh `club:activity:manage` access remains required. Pending, failed, retry, refresh and genuinely empty responses are separate states.

All returned rows retain server order, including past and cancelled dates. Missing signup/refund counts remain unknown; returned zero is displayed as zero. Cancelled rows show refunds; active rows show registration counts. Nullable editability and raw lock reason are presented as status. No local date/count interpretation grants edit authority.

Parsed display time is fixed UTC+8/Gregorian and explicit `yyyy-MM-dd HH:mm`, independent of the device timezone. Accepted common forms match Mini's wall date, offset ISO, numeric epoch and exact10/13-digit string semantics; a numeric zero sentinel is unparsed, while10 zero digits as a string represents the epoch per the source. Real-calendar validation rejects overflow dates/times. Parsing is display-only at minute precision, not a scheduling or expiry API. Unsupported values, including year0000, retain original text with an unconfirmed-clock notice; absent text is localized as unknown. No date is manufactured.

Only a returned positive activityId can open `ClubGovernanceEventView`; occurrenceId and response index are never substituted. That destination reuses all its existing reads, permissions and separately authorized commands. Closing the sheet refreshes the occurrence list while retaining the expanded series. The feature itself only reads and routes; no real cancellation, attendance mutation, payment or notification was executed.

## Lifetime and isolation

The disclosure captures the parent accepted read context and generation. Opening and read completion require a current parent source and expansion state. The read model binds account/epoch, club/topic/series, authorization generation, access object identity and storage namespace. Each visibility interval, request and accepted snapshot has its own token. Collapse/reopen, another series, refresh, stale completion, sign-out, namespace or authority replacement cannot reuse an old permit or route.

Event selection also binds the exact projected row and read token. Rapid double taps are ignored. A replaced or retired source invalidates the open destination and clears selection. Returning rereads; a pre-return route cannot be reused against the refreshed snapshot. No expansion preference stores member data or grants authority.

## Integration

Apply after the exact batch14 roster patch on49, or reconcile only the documented series block against its full `before` file. Register the new App/Core/test sources and merge the15 bilingual localization keys using `club-series-occurrences-registration.fragment.json`. Central PBX/catalog/CI ownership remains unchanged. The package contains8 delivery files, full before/after images and a delta patch; sealed1–14 are untouched.

## Verification

Executed in the authorized current dot workspace:
-38 focused structural assertions PASS: exact hunk/preimage, ordinary reader wiring, single expansion, read-only transport, unknown semantics, route/source fences, return refresh, localization and unchanged shared contracts.
- Existing governance contract suite:12 checks PASS.
-3 exact Mini Git blobs verified; real source-function oracle PASS for scoped read, open/close/switch, source order, past/cancelled, unknown/zero, empty/error and fixed+08 wall/offset/epoch/cross-midnight display under3 device timezones. All requests were local spies. This validates the source behavior, not execution of new Swift.
-5 Swift files parsed by Tree-sitter with zero diagnostics. This is syntax only, not native typechecking or runtime verification.
- Delta apply/reconstruction/reverse check and all14 sealed prior patch checksums verified.

Authored10 Core and10 AppUnit tests: **all20 NOT_RUN**, because Swift and Xcode are absent. Native build, SDK/API checks, simulator, UI/VoiceOver, screenshots and live-account reads are **NOT_RUN**. No production availability or successful Apple execution is claimed.

Apple acceptance after registration: ordinary club workbench→series→expand; switch/collapse/rapid taps during loading; empty/failed/retry/permission-denied; past/cancelled/unknown counts; Shanghai cross-midnight display on non-China device zones; returned activity→existing workbench→close/return refresh; account/authority/namespace changes while loading or presenting; Dynamic Type and VoiceOver. Do not execute real sensitive mutations as part of these checks.
