# P049 named default lead for a new series

## Base and dependencies

Base: `41571fed5c27d4766d0bebb02e2800d798f1edbd`.

Exact preimage packets, in order:
1. Batch11 `club-role-assignment-picker.patch`, SHA256 `e1ec23eea1487ba8338c7f73bd19021caeafa784547d5ffb9d2e9cd6a1c792ff`.
2. Batch12 `club-series-schedule.patch`, SHA256 `02132fffcaa2490df7f6e0d92fa92712d9d8604f3764908c2192317cf8ee3e44`.

Composite preimage tree: `e3b5af7dc14fe5912785f09ba98664cd3cef7d0c`. This packet contains only the subsequent delta. The prior12 packets remain sealed.

## Source and verified gap

The unique master, `MASTER-v10-extracted-text.txt`, P049 lines1668–1671 lists `onLeadChange` and `submitSeries` on the activity-operations page.

Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- `pages/club/event-ops/index.js`, exact blob `8619be05e9cf8f05b0fde678a30b723b6df6ace8`, lines533–568: `/api/club/members` read and named options; 714–718: selected `memberId`; 749–817: existing series create payload.
- `pages/club/event-ops/index.wxml`, exact blob `1cc5d36acbd475f76309f5b82c5a768ff3cf6552`, lines224–230: the named default-lead dropdown appears only for a new series.

Before this packet, the ordinary native new-series form still required a manually typed `defaultLeadMemberId`. Batch11 selects role-assignment targets, and batch12 selects dates; neither provided this lead-selection flow.

## Implemented ordinary flow

The existing `.createSeries` form passes its real scope, identity and governance access to the new selector. A form-owned read model calls existing `.members`, with the normal service access preflight. Its accepted snapshot must carry fresh `club:activity:manage` permission for the same club/topic context. No AppSession or production source changes are needed for this injection.

The user sees loading, a readable error/retry, permission denial, a genuinely empty list, or named member options. Names and member IDs are shown together, so repeated nicknames remain distinguishable. Blank names use a localized unnamed-member label alongside their real ID. Expanding, choosing and cancelling are local interactions; cancel only collapses the selector and preserves the original selected ID. Refresh clears old option evidence; a removed member is called out and cannot be reviewed until the user selects a current member.

The selected positive `memberId` goes through the existing draft binding and request-ID lifecycle. The original prepare button and callback now require a current accepted lead option for `.createSeries`. Existing review re-reads eventTopics and members via the unchanged coordinator. Cancel review and unchanged confirmation/journal/write gates remain in place. A synthetic test composes this selection with the preceding schedule model and enters the existing prepare/cancel path with zero sends.

The new selector is create-only. It does not change the existing update-series lead field or claim to fix its policy. It never assigns a role, expands write authority, creates a series or sends any notification during self-test.

## Exact contract boundary

Mini prepends a null/default-owner option and falls back to it when reads fail. Existing native `ClubGovernanceFormDraft.command` and `ClubGovernanceCommand` require a positive lead ID; `ClubGovernanceCoordinator.memberProof` must find it in the current member list. This packet preserves those contracts: no null choice, no fabricated owner ID and no default selection. A read failure or empty list cannot become a successful owner fallback.

Unlike role assignment, series memberProof does not exclude owners or require `isOwner=false`. Therefore any returned explicit member, including an owner or a member whose owner flag is absent, can be selected as lead. This confers no role permission. Duplicate member IDs keep the first source row, matching Mini. Record `id` is never substituted for `memberId`. Malformed rows or contradictory club IDs fail rather than becoming usable targets, consistent with the existing native read-validation boundary.

## Identity and lifecycle

The read context captures exact operation/club/topic, account and epoch, authorization generation, access instance and storage namespace. Form visibility permits reject callbacks after closing or reopening. Per-load generation and a fresh snapshot UUID prevent older responses and stale rendered rows from overwriting a newer list or selecting a retired option.

The form owns activation and cancellation rather than lazily recycled rows. The model binds without publishing during body construction. Selection and both stages of an asynchronous retry check the live editing gate, so queued callbacks cannot mutate or refresh a draft during preparation, review or an outcome lock. Account, authorization, namespace, reader and scope replacements invalidate accepted choices. The existing coordinator remains responsible for fresh proof before any authorized write.

## Registration and evidence

The fragment lists one new App source, one Core source, one Core test file, one AppUnit test file and7 bilingual localization keys. Only `App/ClubGovernanceCommandForm.swift` is modified. All dependency sources other than that file equal their exact staged preimages. No PBX, aggregate catalog, CI, shared fixture host, AppSession, existing command schema, base draft, coordinator, service, validation or permissions are edited.

Executed locally:
- 34 focused structural assertions: PASS for ordinary wiring, current member evidence, lifecycle, create-only replacement and unchanged protected contracts.
- Existing governance contract suite:12 checks PASS.
- Two exact Mini blobs and source-function oracle: PASS for member read payload, owner inclusion, duplicate ID/source order, duplicate names, unnamed fallback, explicit lead/owner payloads, empty/failure states and create-only dropdown binding. All source requests use a local spy; no network.
- Five changed/new Swift files: Tree-sitter syntax parse PASS. No typechecking, Apple SDK validation or native runtime evidence is implied.
- Full before/after delta reconstruction, reverse-apply, protected-file equality and all12 prior packet SHA256 checks.

Authored10 Core and10 AppUnit cases: **all20 NOT_RUN**, since Swift and Xcode are absent. No native build, simulator UI/VoiceOver checks, screenshot, real-account read or backend mutation was run. Native acceptance after central registration should cover ordinary create flow → named lead → schedule → review/cancel, owner selection, same nicknames, empty/denied/error/retry, removed-member refresh, stale row tap, old/new read races, context and identity replacement, long-list scrolling, Dynamic Type and VoiceOver. Do not perform real series creation or role writes without existing required authorization.
