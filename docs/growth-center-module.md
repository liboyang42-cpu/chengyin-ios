# Integrated status (2026-10-01)

The steps below have been applied to the current integration tree. The latest regional/storage-scope guard and CNAccountSessionService remain intact. The localization data lives in `docs/growth-center-localizations.json`; source checks live in `Tests/ContractChecks/test_growth_source_contract.py`. Swift/Xcode/runtime are NOT_RUN.

# Growth center native read-only module

## Files to integrate

Copy the four `Core/GrowthCenter*.swift` files and four `App/Growth*.swift` files into the matching directories of the integrated app. Add `Tests/CoreTests/GrowthCenterTests.swift` and `Tests/AppUITests/GrowthCenterFlowTests.swift` to their matching test directories. The original handoff was isolated; the parent subsequently authorized the shared integration described above.

`Resources/growth-localizations.json` contains 47 English/Simplified Chinese entries in `{ key: { en, "zh-Hans" } }` format. Merge these into `Resources/Localizable.xcstrings` using the existing catalog entry shape. Do not replace the shared catalog. The provided source checks use this small JSON as their coverage source; retain it with the checks if they are copied into the integrated repository.

The project generator already discovers flat `Core/*.swift`, `App/*.swift`, and `Tests/AppUITests/*.swift` paths. Run `python tools/generate_project.py` only in the parent integration step. SwiftPM already discovers the pure core tests. There is no new package or framework dependency.

## AppSession wiring

Add the following adjacent to the existing account collection service/reader. The private full-session equality check is intentionally redundant with the reader: a late failure must not expire a replacement credential.

```swift
private let growthCenterService: GrowthCenterService?
private var currentGrowthCenterSession: GrowthCenterReadSession? {
    guard let account, let token else { return nil }
    return try? GrowthCenterReadSession(accountID: account.id,
                                      epoch: gate.currentStamp,
                                      token: token)
}
lazy var growthCenterReader = GrowthCenterSessionReader(
    service: growthCenterService,
    currentSession: { [weak self] in self?.currentGrowthCenterSession },
    onUnauthorized: { [weak self] captured in
        guard let self, self.currentGrowthCenterSession == captured else { return }
        self.expireIfMatching(error: APIError.unauthorized,
                              stamp: captured.epoch, credential: self.token)
    }
)
```

Inside the **existing** guarded initializer branch `if let scope, let regional, let configuration = regional.apiConfiguration`, after creation of the existing shared `URLSessionTransport`, add:

```swift
growthCenterService = GrowthCenterService(configuration: configuration, transport: transport)
```

In the matching unconfigured `else` branch, add `growthCenterService = nil`. If that branch is changed during integration, keep the identical verified regional/storage-scope gate used by adjacent authenticated read services. Do not create a secondary configuration, host fallback, transport, credential store, regional exception, or endpoint. The service has no production host. Keep the real API base URL values empty.

No additional logout/bootstrap hook is required: the reader compares account ID, session epoch, and token on each read and both completion paths. Its UUID `scope` changes whenever the captured session changes. Tokens stay fileprivate in the pure-core reader and never enter UI keys.

## AccountView entry

Add a native navigation entry in an appropriate account section (the account details or saved collections area):

```swift
NavigationLink {
    GrowthCenterView(reader: session.growthCenterReader)
        .id(session.growthCenterReader.scope)
} label: {
    Label("growth.title", systemImage: "chart.bar.xaxis")
}
.accessibilityIdentifier("account.growthCenter")
```

The containing AccountView must continue observing AppSession via its existing `@EnvironmentObject`. The destination `.id` clears navigation/view-local state when the complete read scope changes. Keep the signed-out account shell behavior unchanged; standalone fixture/deep-link use of the growth view displays its explicit login gate without dispatching reads. There is no invented route to a redemption, check-in, reward, or completion action.

## Offline fixture registration

In `ModuleFixtureSupport.swift`, add `growthCenter` to `ModuleFixture` and add `case .growthCenter: GrowthCenterFixtureHostView()` to its switch, retaining the existing DEBUG guard and `AccessibilityFixtureOptions` modifier.

Launch arguments:

```text
--uitesting-module growthCenter --uitesting-growth-scenario content
```

Scenarios: content, empty, partialCenter, partialMileage, partialCompleted, partialRank, failure, unauthorized, guest, unconfigured, unranked, sessionChange, slowFilters. All records are synthetic; this path does not configure or instantiate a network transport.

## Contract and UI decisions

Audited source files:
- `app-audit/lib/data/api/growth_api.dart`
- `app-audit/lib/data/models/growth.dart`
- `app-audit/lib/feature/p3/growth/growth_center_controller.dart`
- `app-audit/lib/feature/p3/growth/growth_overview.dart`
- `app-audit/lib/feature/p3/growth/growth_board_logic.dart`
- `app-audit/lib/feature/p3/growth/leaderboard_controller.dart`
- growth center and leaderboard Flutter pages in that folder
- `app-audit/lib/core/network/dio_client.dart` confirms JSON content type and raw Authorization token

Exact reads:
- POST `api/growth/center`, `{}`
- POST `api/play/growth`, `{}`
- POST `api/play/my-completed`, `{}`
- POST `api/growth/leaderboard`, `{metric: point|exp, period: total|week, limit: 1|50}`

The overview loads all four independently and concurrently. Ordinary failures stay in their own sections. Any unauthorized sibling rejects the complete private result; cancelled or stale readers cannot forward a logout callback. The source score card uses `leaderboard.me.score`, not `center.points`; the fixture intentionally sets those to different values. Completed topics are counted from distinct positive topic IDs; `topicId=0` never adds a topic. A null personal rank is unranked, never rank zero. Missing numeric facts stay nil; real zero stays zero. The leaderboard refuses a metric/period response mismatching the requested filter, and UI result visibility is bound to both scope and query.

Collection fields and outer envelopes are structurally validated more strictly than Flutter's empty defaults: missing/null/wrong-shape collections fail rather than pretending the user has none. Numeric JSON strings are accepted; booleans and fractional counts are rejected. The badge unlock date is a strictly valid source-local China timestamp; missing/unparseable time omits the date area. Device timezone does not change it.

Native List, LabeledContent, menu Pickers, NavigationLink, and DisclosureGroup provide Dynamic Type, system Back navigation, and standard accessibility. Read-only mission metadata is labeled as such; no reward claim operation exists. Reduce Motion suppresses transactions; there are no custom animations. Badge and rank displays use local SF Symbols/text; source image URL strings are decoded but deliberately not fetched in this first read-only slice. No external media loader or new network provider is introduced. The source's decorative three-person podium is represented by ordered native ranking rows, with the supplied rank preserved.

## Verification

Source checks after integration: `python -m unittest discover -s Tests/ContractChecks -v` from the integrated repository. All 11 Growth checks pass (8 module checks plus 3 integration checks); the complete contract suite has 81 passing checks.

Supplementary Tree-sitter parse: all 10 Swift files pass with zero recovery nodes. This is syntax-only evidence, not a Swift compiler/typecheck.

Prepared regression coverage: 17 XCTest core methods covering exact requests, filter combinations, malformed/empty/numeric boundaries, partial failures, any-sibling 401, date/rank semantics, invalid input, guest/config gates, account/epoch/token/logout isolation, current/cancelled unauthorized, generation races, query races, and navigation cancellation. Seven UI methods cover navigation/refresh, filters, partial failures, unranked/empty states, logout reset, Chinese, large text, and dark mode.

Swift compilation, SwiftPM XCTest execution, Xcode build, Simulator UI execution, screenshots, VoiceOver, and device Reduce Motion: **NOT_RUN**. The cloud executor has no Swift/Xcode. Run these on an Apple toolchain before treating the module as build- or runtime-verified. The provided UI XCTest names are ready for the existing shard runner after fixture/project integration.

Integrated verification inventory: 750 core test methods, 92 UI methods in 17 classes, 1352 bilingual catalog keys. All are authored counts. Three exhaustive UI shards contain 30/31/31 methods. Aggregate parser diagnostics remain in six untouched files; the new Growth files have zero parser diagnostics. No Swift compiler or runtime pass is implied.
