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

Tests wait for interactive targets to be hittable and assert destination state. Bounded scroll gestures reveal offscreen rows/search controls; their endpoints use the visible collection area after excluding the navigation bar, search toolbar and keyboard. They do not relaunch tests or repeat a failed product action. The pagination fix snapshots `appliedQuery` when resetting and retains generation guards to discard superseded responses. This suite does not exercise out-of-order async responses, refresh races, live account changes, or real backend pagination.

## Integration and verification

Add the following String Catalog entry in both supported locales before compilation:

| Key | English | Simplified Chinese |
| --- | --- | --- |
| `activity.fixtureNotice` | UI test fixtures · No live data | UI 测试数据 · 非实时内容 |

The project generator must be rerun after the new sources are integrated. Existing workflow test discovery runs the full `QuestifyUITests` target; no workflow edit is needed. On the approved Xcode/macOS executor, run the structural/catalog checks, an unsigned Debug simulator build and Release device build, and both UI test classes on the selected iPhone simulator. A focused run uses `-only-testing:QuestifyUITests/ActivityFlowTests` with the existing `xcodebuild test` command.

These files were authored in a Linux workspace with no Swift/Xcode runtime. Local checks cover source-level isolation and fixture JSON only. External CI evidence is recorded below; the corrected revision still requires Apple-toolchain validation and does not yet establish runtime-network isolation.

## First CI findings and corrections

The supplied UI log for run `36846622633` recorded all four new scenarios failing and all five existing entry scenarios passing. These failures are not accepted as test success:

- Both successful row taps pushed a blank destination with a Back button but no title or content. The detail's initial `Group` contained no child (`loading == false`, `access == nil`), leaving task/title modifiers on empty content. List and detail now have a persistent `ZStack` host; detail also renders initial loading content. Native NavigationLink and back behavior remain intact.
- The list-error accessibility identifier propagated from `ContentUnavailableView` onto its image, title and Retry button, replacing the button's own identifier. State identifiers now live only on title `Text` leaves; Retry keeps its distinct button identifier. Tests use typed static-text queries for those states.
- During pagination the collection remained at 0% scroll with the keyboard open. Its AX frame extended behind the bottom search toolbar and keyboard, so default whole-element swipes missed the unobscured list. Gestures now derive their endpoints from current visible geometry and preserve the unsubmitted query.

These corrections require a new simulator run. Timeouts, destination assertions, nullable-value checks, read-only checks and scenario count have not been relaxed.

## Search placement follow-up

Run 36851561783 passed eight UI cases but timed out acquiring the search field in the pagination case. Its accessibility tree showed the field in the adaptive bottom toolbar, with slow snapshot responses; this does not prove one underlying cause. Activity search now requests the native always-visible navigation-bar drawer to make search discovery consistent while scrolling. Existing pagination assertions remain unchanged; this adjustment awaits the next integrated UI run.
