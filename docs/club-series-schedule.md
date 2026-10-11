# P049 Shanghai series schedule editor

## Base, dependency and exact sources

Base: `41571fed5c27d4766d0bebb02e2800d798f1edbd`.

One exact dependency: sealed batch11 `club-role-assignment-picker.patch`, SHA256 `e1ec23eea1487ba8338c7f73bd19021caeafa784547d5ffb9d2e9cd6a1c792ff`. Its staged composite preimage tree is `31d8b958879bebff012e1940db4500df765ab88c`. This packet is only the subsequent delta, including the shared command form's precise batch11 after-image. No previous packet is changed.

The only master, `MASTER-v10-extracted-text.txt`, P049 lines1668–1671, lists recurrence, first date, count, custom-date change/add/remove, assembly time, cancel and submit events.

Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:

- `pages/club/event-ops/index.js`, blob `8619be05e9cf8f05b0fde678a30b723b6df6ace8`: 27–42 Shanghai clock; 634–675 real series-detail seeding; 704–747 editing events; 749–817 validation and payload.
- `pages/club/event-ops/index.wxml`, blob `1cc5d36acbd475f76309f5b82c5a768ff3cf6552`: 164–224 recurrence/date/time editing UI and server-horizon explanation.

Verified gap: ordinary native create/update forms previously required raw `startDate`, `startTime` and comma-separated `customDates`, with no guided date-time selection or local schedule editing transaction.

## Ordinary user flow

Existing `eventTopics → createSeries` and `series → seriesDetail → updateSeries` routes already pass their actual governance access, identity, coordinator, scope and series-detail seed into `ClubGovernanceCommandForm`. That form now offers Edit schedule for those two operations. It does not depend on a fixture callback or a new AppSession injection.

The nested editor owns a value copy. It provides ONCE/WEEKLY/CUSTOM_DATES, Shanghai calendar/time pickers, a weekly count from1–64, stable custom-date rows with add/remove, a requested-date preview, reset-to-opening-values, cancel and local apply. Closing or swiping away discards only that copy; original text, anchors, policy and request ID remain untouched. Apply validates again at current time, changes only the five scheduling fields, marks the original draft dirty and cancels any prior review. Other fields continue through the existing form.

The preview is explicitly local requested dates, not created sessions. The server still owns its materialization horizon, locked/settled occurrence policy and version conflicts. This editor does not infer counts/statuses of existing occurrences. A later ordinary review uses the unchanged `coordinator.prepare(draft.command())`, including fresh eventTopics/seriesDetail and member-proof reads. Confirm code, command schema, journal, writes policy and service grants are byte-for-byte unchanged.

This packet does not enable create/update writes, perform actual creation/update, or send a notification. Existing production authorization remains necessary. No claim of live-account or deployed availability is made before central registration and Apple acceptance.

## Field and time semantics

- Dates use a Gregorian calendar and `Asia/Shanghai`, independent of device timezone or preferred calendar. Wire date/time strings stay `yyyy-MM-dd` and `HH:mm`.
- Calendar parsing rejects normalization of invalid dates and malformed time values. An invalid source date is retained as invalid, never silently replaced with today. Time parsing checks both component count and round-trip equality, including trailing-newline rejection.
- A blank new draft uses Shanghai today for an explicit user proposal. Existing series `futureDates` seeds the first sorted date and count. The read model supplies no occurrence time; 09:00 is explicitly described as the initial default for newly added dates, matching Mini. Existing occurrence times are not represented as known or rewritten by this UI.
- Dates before Shanghai today and today's assembly time at or before the current minute are blocked. Apply and review preparation check again after time has elapsed.
- Single occurrence applies count1. Weekly uses1–64 and previews seven-day increments. Custom row count stays1–64; exact date strings are sorted/deduplicated at apply. Its submitted count is the number of distinct selected dates. `startDate` is the first selected custom date, ensuring the existing command's required date is valid even when its first-date picker is hidden.
- Source duplicates can be edited separately with stable UUID row IDs, then are combined in the payload. Removing the last row and adding a65th row are prevented.
- Only recurrenceType/startDate/startTime/occurrenceCount/customDates are changed. Capacity, lead member, waitlist policy, offer window, exact club/topic/series scope and immutable expectedVersion remain as supplied by the current original draft.

## Session safety

A sheet captures a fresh UUID, operation, exact scope, original request ID, account/epoch, namespace, authorization generation and access object identity. Every apply rechecks these plus the live busy/review/outcome lock. Cancel/reopen, parent draft edits, scope changes, account/epoch changes, access replacement, namespace changes and authority revisions invalidate delayed callbacks. Closing the parent retires the sheet. No reader or writer is constructed inside the editor.

## Registration and evidence

Register the new App source and Core source in the app target, and new AppUnit test in AppUnitTests. SPM discovers Core/CoreTests. Merge the16 bilingual keys using the supplied registration and localization fragments. No PBX, aggregate catalog, CI, shared fixture hosts, AppSession, other feature lines or existing Core contracts were edited.

Executed here:

- 35 targeted structural checks: PASS. They cover ordinary routes, local-copy isolation, five-field writes, calendar/time gates, session fences, unchanged role picker and existing authority/confirm contracts.
- Existing governance contract suite:12 checks PASS.
- Two exact Mini blob hashes and nine bound source events: PASS. Local source-function oracle covers weekly/custom create payloads, add/change/remove bounds, real detail seeding/version, update payload, four assembly-time cases and cancel/reset. Its transport is a local spy and clock helper is a fixed Shanghai fixture; no request leaves that process.
- Five Swift files parse with Tree-sitter, no recovery or diagnostics. This is syntax only, not Swift typechecking or Apple SDK validation.
- Patch reconstruction and reverse-apply check; protected-file equality and all eleven prior packet hashes checked.

Authored14 Core tests plus8 AppUnit tests: **all22 NOT_RUN**. Swift and Xcode are absent. No native build, simulator, UI automation, VoiceOver verification, screenshots, real-account reads or actual backend mutation was run.

Apple acceptance after registration: ordinary create and existing-series routes; Shanghai timezone/device-calendar changes; midnight/elapsed minute; weekly year boundary and64 limit; custom duplicate dates and remove-last protection; cancellation/swipe/reset with unchanged parent draft; apply→review→cancel; account/auth/access/draft replacement while editor remains visible; Dynamic Type and VoiceOver. Do not execute real series creation/update without the existing required authorization.

## Next independent gap

P049 Mini `loadLeads` lines533–568 and `onLeadChange`714–718 provide a named member selector via `/api/club/members`. The native create form still asks for the raw `defaultLeadMemberId`. Existing native coordinator requires a positive member ID and member proof, whereas Mini's blank default sends null. A subsequent guided explicit-member flow can reuse the existing read contract without enabling writes; do not invent owner fallback or loosen that contract.
