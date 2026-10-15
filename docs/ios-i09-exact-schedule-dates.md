# CY-HANDOFF: IOS — I09 exact remaining schedule dates

2026-10-15 UTC. **SOURCE_DELIVERED_UNVERIFIED; tests, build, App and CI NOT_RUN.**

## Baseline, ownership and scope

- Repository/branch: `liboyang42-cpu/chengyin-ios`, `migration/native-ios`.
- Exact published parent: `fefc96a6a37571b93f36801e948afc4adbda21d3`, tree `28b93d7af9db2dd50b69fef4a416a62429ac3a67`. The isolated working snapshot matched all 5,084 public file blobs before editing. The publication coordinator records the resulting commit separately.
- Protocol `CY-COORD-20261015-v1`; I09 / B04 / BK-SCHEDULE. This closes one bounded source flow: series detail → schedule editor → preview/Apply → immutable review/save → acknowledgement or existing error/readback recovery. It does not close all I09 acceptance.
- Exact changed paths: `Core/ClubSeriesScheduleDraft.swift`, `App/ClubSeriesScheduleEditor.swift`, `App/ClubGovernanceCommandForm.swift`, `Tests/CoreTests/ClubSeriesScheduleDraftTests.swift`, `Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift`, `Resources/ClubSeriesSchedule.xcstrings`, `Questify.xcodeproj/project.pbxproj`, `docs/ios-current-status.md`, and this document.
- The project change only registers the new four-key English/Simplified Chinese catalog. No build settings, deployment target, entitlement, signing, dependency, existing localization catalog, backend file or shared coordination log changes. Existing source is retained; no cumulative patch is imported. Capabilities remain OFF.

## Refreshed backend evidence

The control branch was read at `11f7a95642086d6308abc7867aadad587656fa7f`: [IOS_START_PROMPT](https://github.com/liboyang42-cpu/hengyin/blob/11f7a95642086d6308abc7867aadad587656fa7f/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md), [IOS_HANDOFF](https://github.com/liboyang42-cpu/hengyin/blob/11f7a95642086d6308abc7867aadad587656fa7f/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/11f7a95642086d6308abc7867aadad587656fa7f/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md), OWNERSHIP, COORDINATION, TASKS and LONGRUN_CURRENT. Its frozen candidate is `1e403b135206844a34219753a36e2dee39c7dd59`; recorded CORE checkpoint is `05d307ec0466988f212187666d7f1e5c3274f434` / PR44. These are source identities, not deployed application versions.

The [frozen B04 contract](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/docs/verification/mini-bug-arch-20261015/B04/CLAUDE_CONTRACT.md), blob `7e8a10c629b396a68e49bcb56f8316712ec3118a`, retains nullable common Shanghai HH:mm, update `expectedVersion`, protected history, and added-date-only time assignment. There is no update requestId or new receipt API. The prior [HH:mm repair](ios-i09-series-time-handoff.md) remains in place.

Direct source comparison found the same relevant service/materializer blobs at frozen and CORE checkpoints: service `3d1e4035f62351129a9700ddcb8ac037bbcc4108`, materializer `3fb56cd174ffb2a78c491354e57680518d44891d`. The additional PR36 checkpoint `b5eb886676d2bf1f5fcb9a8b5d9d77ac0d5e7036`, then its observed head `25ede65815d26d1514d3b6c3b92b26d2898a3e45`, was also read. Both have service blob `bcd32a358dc55ee6f795c22824be1eba724f69ec` and materializer blob `4d331d66751b67693215a59a8559d9f11139bd9e`. That later source adds consistent reads, strict time parsing and fixed-date create replay normalization; the update boundaries below are unchanged. The create-only replay behavior is not applied to update or WEEKLY.

Exact existing semantics:

1. [Detail](https://github.com/liboyang42-cpu/hengyin/blob/25ede65815d26d1514d3b6c3b92b26d2898a3e45/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ClubEventOpsServiceImpl.java) returns the Shanghai dates of remaining future ACTIVE occurrences. [SQL](https://github.com/liboyang42-cpu/hengyin/blob/05d307ec0466988f212187666d7f1e5c3274f434/chengyinhub-system/src/main/resources/mapper/business/ClubEventOpsMapper.xml) filters active activity start time after now and orders occurrence time/id. A later-today date can be present. Ordinary cancellation does not rewrite the series recurrence. The list endpoint intentionally has an empty futureDates array; editing uses the actual detail route.
2. [Materialization](https://github.com/liboyang42-cpu/hengyin/blob/25ede65815d26d1514d3b6c3b92b26d2898a3e45/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ClubEventScheduleMaterializer.java) interprets WEEKLY as successive seven-day steps from startDate and occurrenceCount, ignoring customDates. CUSTOM_DATES uses the explicit date set. No existing WEEKLY-with-exclusions representation exists. The server's 1–64 and 90-day limits remain authoritative.
3. updateFuture requires each requested date strictly after Shanghai today, so tomorrow is allowed and later today is rejected. Its existing-occurrence set can still contain later today. Silently filtering today out can remove an occurrence or encounter protected-history conflict.
4. updateFuture reconciles the requested date set, preserving existing dates/times and creating only added dates at startTime. It also persists submitted recurrenceType and increments version. **Submitting CUSTOM_DATES really changes stored recurrence; it is not a wire-only alias that leaves WEEKLY unchanged.**

Contract adaptation is permitted at the frozen level. All TEST_DEPLOYED remains NO; package/database binding, runtime HTTP, real identities, devices, merge and deployment are unverified. Historical backend tests do not validate this native change. No CI was queried or triggered.

## Sanitized source-traced reproductions

These are synthetic examples, not executed business reproductions.

### Canceled middle weekly occurrence

For club 81/topic 91/series 101/version 7, detail returns recurrenceType WEEKLY, startTime 00:30, futureDates `[2026-10-12, 2026-10-26, 2026-11-02]` after the October 19 occurrence was canceled. The ordinary detail edit action seeds the actual snapshot through `ClubSeriesUpdateReturn` and `ClubGovernanceCommandForm`.

Previously, opening `ClubSeriesScheduleDraft` took the earliest date and remaining count, so its WEEKLY preview requested October 12, 19 and 26. Applying without any date edit could recreate a canceled date and remove November 2, or receive a conflict if removal was protected. Changing only the assembly-time control had the same date-set drift.

Now the initial editor uses CUSTOM_DATES for this unrepresentable readback, preserving October 12, 26 and November 2 exactly. Before Apply, the preview explains why the saved recurrence cannot reproduce the remaining dates and that saving will store CUSTOM_DATES. The applied form and final review repeat the conversion disclosure. The payload uses the existing `customDates` array and `recurrenceType: CUSTOM_DATES`; expectedVersion and other policy fields are preserved, with no update requestId. This is a visible recurrence conversion requiring the ordinary Apply/review/Confirm path, not a claim that recurrence metadata is unchanged.

Contiguous weekly dates keep WEEKLY and its count controls. An explicit user switch back to Weekly intentionally regenerates the visible weekly sequence. Explicit custom edits add/change/remove only the selected dates. Time-only edits, Reset, Cancel and reopen do not fill gaps. Empty update readback remains an empty, invalid custom-date selection until the user explicitly adds a date; it does not invent today. Invalid dates and unknown common time remain blocked.

### Update later today and midnight rollover

At `2026-10-11T01:00:00Z` (09:00 Shanghai), an update requesting October 11 at 23:59 previously passed the create-style future-minute check, but updateFuture rejects that day. A detail containing October 11 and October 25 must not be silently shortened to October 25.

Update validation now requires tomorrow or later in all recurrence modes and shows a dedicated explanation. The picker lower bound uses Shanghai tomorrow. The requested-date preview retains today's date until an explicit edit; Apply stays blocked. Create keeps its existing same-day/future-minute rule. Applying a create-origin local copy to an update form still checks the target operation's stricter rule.

An applied October 12 schedule becomes invalid at `2026-10-11T16:00:00Z`, Shanghai midnight. The editor rechecks during its clock updates and at Apply. The form rechecks after asynchronous review preparation and at confirmation entry/after target validation, clears an invalid review through the existing path, and keeps the draft for correction. These client checks do not replace backend time/CAS validation: a rollover during the later coordinator preflight can still be rejected by the server, and its existing error handling remains authoritative.

## Save, result and recovery

The immutable review, permission/member preflight, source generation/identity validation, exact version checks, dispatch gates and durable operation locks are reused. No coordinator, service, API adapter or recovery-policy change is made.

- Acknowledgement closes through the existing `ClubSeriesUpdateReturn` owner. The parent detail performs a fresh read; that read supplies the new version, recurrence and explicit futureDates for subsequent editing.
- A stale version/source during preflight prevents dispatch. The local exact draft remains available; close/refresh/reopen captures current detail and requires a fresh review.
- A protected-occurrence rejection/conflict is displayed through the existing business-error path. There is no automatic retry or invented success.
- A timeout/UNKNOWN retains the original command and existing lock. Matching later detail, leaving the page, or a failed read does not prove the outcome or authorize replay. Acknowledged/readback-failed state also never resends.
- Scope/identity/authorization changes continue to invalidate old sheets and reviews. No production lease or write grant is enabled.

## Authored acceptance and remaining execution

Ten added Core methods cover exact gapped preview/wire fields, contiguous weekly/once compatibility, time-only edit/reopen/reset, deliberate weekly replacement, custom add/remove, empty readback, same-day create versus update, visible today retention, Shanghai midnight expiry/picker minimum, and unknown-time compatibility.

Seven added AppUnit methods exercise the existing detail source, schedule session, coordinator and return owner with synthetic access: exact preview→review→one save→acknowledgement→independent readback; Cancel/Reset; reopen/retired sheet; stale-version preflight and refreshed review; protected-date conflict; UNKNOWN plus matching readback/no replay; and acknowledged save with failed then successful readback/no resend. They are source-authored regression cases, not executed results or a rendered UI test. They do not execute the private form prepare/confirm guards, localized rendering or DatePicker behavior for a retained today selection below its tomorrow lower bound.

The pre-existing preview row format still appends the selected time to every requested date. The new explicit note states that retained dates keep their stored times and only added dates use that selection; no per-occurrence time read model or time-rewrite behavior is introduced. Confirm the rendered presentation is sufficiently clear during device acceptance, especially after a time-only edit or mixed-time readback.

Only source inspection and file/patch identity work were performed. **NOT_RUN:** all Swift/Core/AppUnit/XCUITest suites, Python/source-contract tests, lint, typecheck, builds, simulator, App, accessibility/device execution, CI, real accounts/backend integration, Java/database tests, deployment, signing and release. No toolchain or backend was installed.

Remaining acceptance requires the approved Apple toolchain and hosted UI/device runs, English/Chinese conversion/error disclosure, real delayed preflight across Shanghai midnight, and an authorized deployed B04 backend with independent occurrence/date/time/version readback. Include canceled-middle and later-today cases, protected signup/waitlist/settlement history, cancellation/reset, mixed/unknown time, stale version and lost response. The team-return repair and old HOLD work are unchanged; full player allowed-actions, performance and I09 business acceptance remain separate.
