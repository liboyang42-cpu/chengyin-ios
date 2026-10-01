# Offline native activity UI fixtures

These fixtures exercise the existing SwiftUI activity list and detail through an injected, read-only `ActivityReading` dependency. The production conformer is `AppSession`; the normal root still uses the server-owned account and leaves the service unconfigured by default.

## Isolation

- `ActivityFixtureSupport.swift` and its launch routing are entirely guarded by `#if DEBUG`. Release builds contain neither the fixture reader nor fixture-root selection.
- Opt in with `--uitesting-activity-fixture` followed by exactly `tickets`, `club-gate`, `retry`, or `pagination`. Missing/unknown values do not enable fixtures.
- Fixture selection happens before `SessionRootView` is constructed. The app-scoped session container skips `AppSession` construction for fixtures; only the normal root calls `bootstrap`. Fixture mode creates no session, account, Keychain store, transport, service, or scanner. Normal scenes still share the existing app-scoped session.
- A persistent, localized “UI test fixtures · No live data” banner identifies synthetic data on both list and detail. This is not simulated login success.
- The reader decodes in-memory synthetic data, has no delay or network request, and omits all image URLs and coordinates. No `Map` is constructed for fixture details.
- Failure fixtures throw once for the initial list request and once for the initial detail request. Recovery requires the actual Retry buttons; no automatic request retry is added.

## UI coverage

`Tests/AppUITests/ActivityFlowTests.swift` adds four scenarios; `EntryFlowTests.swift` is unchanged:

1. List → detail → back → reopen: unknown price and inventory remain unknown; known price retains the currency disclaimer; zero inventory is sold out; the read-only notice is present, with no in-content booking/payment controls or map.
2. Club-gated detail stays terminal with no detail content/retry/loading indicator, including back and reopen.
3. Initial list and detail errors recover through their explicit Retry controls.
4. After editing (but not submitting) a search draft, pagination keeps the previously applied query. The final short page stops pagination; submitting the draft resets the list and shows the empty state.

Tests wait for interactive targets to be hittable and assert destination state. Bounded scroll gestures reveal offscreen rows/search controls; they do not relaunch tests or repeat a failed product action. The pagination fix snapshots `appliedQuery` when resetting and retains generation guards to discard superseded responses. This suite does not exercise out-of-order async responses, refresh races, live account changes, or real backend pagination.

## Integration and verification

Add the following String Catalog entry in both supported locales before compilation:

| Key | English | Simplified Chinese |
| --- | --- | --- |
| `activity.fixtureNotice` | UI test fixtures · No live data | UI 测试数据 · 非实时内容 |

The project generator must be rerun after the new sources are integrated. Existing workflow test discovery runs the full `QuestifyUITests` target; no workflow edit is needed. On the approved Xcode/macOS executor, run the structural/catalog checks, an unsigned Debug simulator build and Release device build, and both UI test classes on the selected iPhone simulator. A focused run uses `-only-testing:QuestifyUITests/ActivityFlowTests` with the existing `xcodebuild test` command.

These files were authored in a Linux workspace with no Swift/Xcode runtime. No simulator, compile, UI-test or runtime-network-isolation result is claimed here. The source-level isolation and fixture JSON can be inspected locally, but Apple-toolchain validation remains required.
