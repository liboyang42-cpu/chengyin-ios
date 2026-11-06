# CY-HANDOFF: IOS — I09 / BK-SCHEDULE series time readback

> **当前统一入口 / Current entry (2026-10-15): [iOS 范围、状态与证据](ios-current-status.md).** 下文保留原时间点的计划或证据，不自动代表当前状态；历史数量、合同状态与运行结果不得移用于新提交。当前口径以上述入口为准。

2026-10-15. **SOURCE/FIXTURE ADAPTATION; native execution and deployment NOT VERIFIED.**

## Baselines and ownership

- iOS repository/branch: `liboyang42-cpu/chengyin-ios`, `migration/native-ios`; published parent `8c24b744ebad3c6a71350f4992035ff5704fb52a`, tree `42aa9afe83acf7ac9be4f7dc1246a7626e7deb02`. The publication coordinator records this delivery's resulting commit.
- Protocol CY-COORD-20261015-v1; control `liboyang42-cpu/hengyin@codex/mini-bugs-backend-cloud-plan-20261015`, read at `a8865e69c50ed680bcb1d5157705f99c1ca2fa18`.
- Exact backend candidate: `c236f131b19111138d5d6443fa18441f1adb68de`, [PR18](https://github.com/liboyang42-cpu/hengyin/pull/18), open unmerged draft. Backend files remain owned by C00/C99 and B04. No shared control logs or backend files changed.

## Verified existing defect

Existing backend source baseline `8b7eb814e3db00aa2543fee489fad44f9aa7aec3`:

- [ApiClubEventOpsController.java](https://github.com/liboyang42-cpu/hengyin/blob/8b7eb814e3db00aa2543fee489fad44f9aa7aec3/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiClubEventOpsController.java): POST `/api/club/event-ops/series/detail` delegates to `getSeries` in the existing wrapper.
- [ClubEventSeriesView.java](https://github.com/liboyang42-cpu/hengyin/blob/8b7eb814e3db00aa2543fee489fad44f9aa7aec3/chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ClubEventSeriesView.java), blob `d7eeb4c5baf2ffbd1e732e47aaddcd65ba9019d1`: timezone and futureDates exist; no startTime read field.
- [ClubEventOpsServiceImpl.java](https://github.com/liboyang42-cpu/hengyin/blob/8b7eb814e3db00aa2543fee489fad44f9aa7aec3/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ClubEventOpsServiceImpl.java), blob `7bd12fe56366a25773ff17e2381c9524a9bfa61c`: detail converts occurrenceAt to Shanghai LocalDate only. updateFuture requires startTime and uses it only for added dates; retained dates are skipped.

Native `ClubGovernanceFormDraft` previously seeded both create and update at 09:00. `ClubSeriesScheduleDraft` retained it, and the editor displayed it. Therefore adding/moving a date could create a 09:00 occurrence when actual saved series times were 00:30. Retaining all existing dates does not overwrite their times; the defect must not be described as every no-op save changing every persisted occurrence.

Sanitized source-traced reproduction (synthetic, not executed against a server): create a weekly series at 00:30 Asia/Shanghai with dates 2027-01-17 and 2027-01-24, club 21/topic 31/series 61/version 0. Detail request `{"clubId":21,"seriesId":61}` returns those futureDates but no time on the old contract. Open native editing and extend occurrenceCount to 3 without changing time. The prior request to POST `/api/club/event-ops/series/update-future` contains `startDate:"2027-01-17", startTime:"09:00", occurrenceCount:3, recurrenceType:"WEEKLY", customDates:null`, original scope/expectedVersion, and unchanged lead/capacity/waitlist/offerMinutes. Newly added January 31 becomes 09:00 while retained dates remain 00:30. Expected: preserve a known common 00:30; unknown time requires deliberate choice.

## Contract consumed and control-document drift

The exact [B04 contract](https://github.com/liboyang42-cpu/hengyin/blob/c236f131b19111138d5d6443fa18441f1adb68de/docs/verification/mini-bug-arch-20261015/B04/CLAUDE_CONTRACT.md), blob `7e8a10c629b396a68e49bcb56f8316712ec3118a`, and candidate DTO/service were read directly:

- Detail/list add nullable HH:mm startTime, the common time of future active occurrences in Asia/Shanghai. Empty or mixed future times return null; missing is also unknown. It is not a persisted series default or a past-occurrence time.
- Unknown edit time must clear stale values and require explicit choice; create default unchanged.
- Update request, CAS/expectedVersion, permissions, errors and existing added-date-only behavior are unchanged; no update requestId is introduced.

[OWNERSHIP.md](https://github.com/liboyang42-cpu/hengyin/blob/a8865e69c50ed680bcb1d5157705f99c1ca2fa18/docs/plans/mini-codex-cloud-20261015/OWNERSHIP.md) identifies c236f13 as overall CONTRACT_FROZEN. Combined with the exact B04 contract and matching implementation, this supports bounded source/fixture adaptation. However, [BACKEND_CHANGES.md](https://github.com/liboyang42-cpu/hengyin/blob/a8865e69c50ed680bcb1d5157705f99c1ca2fa18/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md) still calls BK-SCHEDULE planned and says no new published DTO. C00/C99 should reconcile that per-BK record to the exact contract and candidate. This discrepancy is not treated as deployment evidence or a blanket freeze for unrelated contracts. Target deployment is NOT_VERIFIED.

## Native repair and compatibility

- Update hydrates only strictly valid HH:mm readback. Missing/null/wrong type/malformed readback stays empty. Create remains 09:00.
- The normal series-detail update route already passes the actual detail seed to the form. The schedule sheet inherits it. Unknown time shows an empty HH:mm text input with the existing localized time label and existing validation error, rather than displaying 09:00 as a saved value. Explicit valid input, including 09:00, restores the regular picker. Apply stays disabled while invalid; Reset restores the original unknown or known value; Cancel never mutates the original form.
- The schedule fallback is operation-aware, so even a missing draft dictionary key cannot reintroduce 09:00 for update.
- The generic synthetic command factory explicitly chooses 09:00 when constructing its valid command; its date-only read fixture remains a legacy-response fixture. It no longer relies on the unsafe update default.
- Existing request fields, version/scope, timezone, capacity/lead/waitlist/offer window, capabilities, fresh review/authorization, eligibility and backend write protection remain unchanged. No grants are enabled. Old servers can still edit after an explicit time choice; their missing field is not silently invented.

Changed paths: `Core/ClubGovernanceFormDraft.swift`, `Core/ClubSeriesScheduleDraft.swift`, `Core/ClubGovernanceSyntheticFixtures.swift`, `App/ClubSeriesScheduleEditor.swift`, `Tests/CoreTests/ClubSeriesScheduleDraftTests.swift`, `Tests/AppUnitTests/ClubSeriesScheduleEditorTests.swift`, `Tests/ContractChecks/test_club_series_time_readback.py`, this document. No new source file or project registration is required.

## Verification and remaining acceptance

Swift regressions cover actual common 00:30 seed, appended weekly date with time/CAS/policy preservation, missing/null/malformed/wrong-type time, explicit 09:00 choice, switching series/reset without stale time, plus existing create-default/timezone/cancel tests. An AppUnit host-session regression also covers unknown time, explicit selection and cancellation; three existing known-time AppUnit helpers now supply an explicit valid seed. They are authored, NOT RUN.

Actual offline checks: three new source-only contract checks pass; project/scaffold structural verification passes. The broad club source suite ran 435 checks with 14 failures, 8 errors and 4 skips; the unchanged baseline independently reproduced the identical 14 failure names and 8 error names across its 432 checks. These pre-existing failures remain open; the three added checks pass. Scope/preservation and patch checks accompany the local delivery. These do not compile or execute Swift and do not prove UI behavior.

**NOT RUN:** Swift/Core XCTest, AppUnit, XCUITest, Xcode build, simulator, physical device, accessibility execution, real-account/backend integration, Java/database tests, CI, deployment or release. Swift and Xcode are unavailable here; no toolchain was installed and no CI was triggered.

After authorized backend deployment, independently verify saved occurrence_at and activity start_date for the appended date, including Shanghai 00:30 across the preceding UTC date, unknown/mixed series and explicit choice, old-page version conflicts, and signup/waitlist-protected occurrences. Existing dates must remain unchanged. Candidate source and fixtures do not close end-to-end I09 acceptance.
