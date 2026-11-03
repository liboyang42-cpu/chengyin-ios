# Code-Level Root Cause Analysis of All 5 `QuestifyAppUnitTests` Failures in Attempt 4 (`15_app_unit_full_keychain_host.log`)

Per `dot`'s instruction in `#issuecomment-6607059473`, none of the 5 failing unit tests in Attempt 4 (`1,222 PASSED / 5 FAILED / 1,227 TOTAL`) is dismissed as generic simulator jitter. Below is the exact assertion failure line, log diagnostic, and source-level root cause for each of the 5 tests on `ab2d3905ec0b0fb17b58ba6b53ec433d83164701`:

---

## 1. `ProfileFavoriteDetailTests.testRealAuthorAndCommentAuthorChildNavigationReturnsToSameDetailReader`
- **Log location**: `logs/15_app_unit_full_keychain_host.log` lines `6897`, `6901`, `6902`, `6906`, `6910`, `6911`
- **Source location**: `Tests/AppUnitTests/ProfileFavoriteDetailTests.swift:169-195` & `RouteFixture` at `:200-226`
- **Exact assertion failures**:
  - `ProfileFavoriteDetailTests.swift:183`: `XCTAssertGreaterThan failed: ("0") is not greater than ("0")` (`probe.childAppearances`)
  - `ProfileFavoriteDetailTests.swift:187`: `XCTAssertGreaterThanOrEqual failed: ("1") is less than ("2")` (`probe.detailAppearances`)
- **Exact SwiftUI runtime diagnostic in log (line 6902 & 6911)**:
  ```text
  [Invalid Configuration] The `navigationDestination` modifier only works inside a `NavigationStack` or `NavigationSplitView`. There's a misplaced `navigationDestination(isPresented:destination:)` modifier presenting `ModifiedContent<SocialPublicProfileView, _AppearanceActionModifier>`. It will be ignored.
  ```
- **Code-level root cause**:
  In `RouteFixture` (`ProfileFavoriteDetailTests.swift:208-221`), `ProfileFavoriteNavigationLayer` attaches `.navigationDestination(item: owner.binding(for: selected))` inside `.background` of `Text("Favorites")`, and its destination closure attaches a second `.navigationDestination(isPresented: $probe.covered)` onto `ProfileFavoriteDetailDestination`. On iOS 27.1 (`iPhoneSimulator27.1.sdk` / `Xcode 27.1 27A9275`), setting `probe.covered = true` at line 181 in the same runloop turn that `probe.detailAppearances` becomes `1` (before `UINavigationController` finishes mounting the pushed destination into the `NavigationStack` responder chain) triggers SwiftUI's misplaced `navigationDestination(isPresented:)` guard (`It will be ignored`), so `SocialPublicProfileView` never pushes (`probe.childAppearances == 0`).

---

## 2. `ProfileFavoriteTopicReadTests.testNormalFullDetailAndChapterCoverReturnUseSameReaderUntilRootLeaves`
- **Log location**: `logs/15_app_unit_full_keychain_host.log` lines `6984`, `6990`
- **Source location**: `Tests/AppUnitTests/ProfileFavoriteTopicReadTests.swift:128-152` & `NormalHost` at `:167-190`
- **Exact assertion failures**:
  - `ProfileFavoriteTopicReadTests.swift:143`: `XCTAssertGreaterThan failed: ("0") is not greater than ("0")` (`probe.childAppearances`)
  - `ProfileFavoriteTopicReadTests.swift:147`: `XCTAssertGreaterThanOrEqual failed: ("1") is less than ("2")` (`probe.detailAppearances`)
- **Code-level root cause**:
  1. In `NormalHost` (`ProfileFavoriteTopicReadTests.swift:181-183`), the child route is declared using deprecated `NavigationLink(isActive: $probe.covered) { TopicChapterView(...) } label: { EmptyView() }` inside a `ZStack` pushed by `NavigationStack` (`ProfileFavoriteTopicNavigationLayer`).
  2. At lines `139-141`, the test polls `for _ in 0..<100 where !h.wire.paths.contains("info-to-user")` and immediately sets `probe.covered = true` without even waiting for `probe.detailAppearances > 0` or for the `NavigationStack` push transition to finish mounting the `ZStack`. Under `NavigationStack` on iOS 27.1, mutating `NavigationLink(isActive:)` before the parent destination is mounted on the stack fails to push `TopicChapterView` (`probe.childAppearances == 0`).

---

## 3. `ProfileGuideReadTests.testOrdinaryConfiguredGuideLoadsOriginalListAndRefreshesWithoutWrites`
- **Log location**: `logs/15_app_unit_full_keychain_host.log` line `7065`
- **Source location**: `Tests/AppUnitTests/ProfileGuideReadTests.swift:164-191`, `Core/ProfileGuideReader.swift:55-79`, `App/SocialAccountComponents.swift:40-80`
- **Exact assertion failure**:
  - `ProfileGuideReadTests.swift:185`: `XCTAssertEqual failed: ("["infomation_list"]") is not equal to ("["infomation_list", "infomation_list"]")`
- **Code-level root cause**:
  In `ProfileGuideReadTests.swift:178-181`:
  ```swift
  for _ in 0..<100 where h.wire.requests.isEmpty {
      revealDocuments(in:host.view);try await Task.sleep(for:.milliseconds(20))
  }
  XCTAssertEqual(h.wire.paths,["infomation_list"]);reader.refresh()
  ```
  `h.wire.requests.append(request)` executes synchronously inside `Wire.send` when the first `"infomation_list"` request begins, **before** the async continuation returns to `SocialReadScreen.reload()` (`App/SocialAccountComponents.swift:74-76`: `let loaded = try await load(); value = loaded`) and **before** `SocialReadScreen.body` re-evaluates to render `ForEach(rows)` and re-establish `@Observable` observation on `reader.presentationRevision` (`revision`). When `reader.refresh()` (`revision &+= 1; readGeneration = UUID()`) runs before `SocialReadScreen` completes the initial `reload()` / view update cycle inside the lazy `UICollectionView` (`List`), `readGeneration` changes mid-flight (causing `valid()` in `ProfileGuideListReader.informationList` at `Core/ProfileGuideReader.swift:67` to throw `CancellationError`) or `revision` increments before `SocialReadScreen.body` observes the new `SocialReadPresentationKey`, so `.task(id: key)` does not launch a second `"infomation_list"` request.

---

## 4. `ProfileSettingsFavoritesTests.testSettingsCollectionUsesOriginalDetailAndKeepsOwnerWhenCovered`
- **Log location**: `logs/15_app_unit_full_keychain_host.log` lines `7738`, `7739`
- **Source location**: `Tests/AppUnitTests/ProfileSettingsFavoritesTests.swift:238-241` & `App/ProfileSettingsFavoritesRoute.swift:94-100`
- **Exact assertion failures**:
  - `ProfileSettingsFavoritesTests.swift:240`: `XCTAssertTrue failed` (`owner.openPost(.init(id: 101, generation: .legacySquare), from: route, current: .current(h.session))`)
  - `ProfileSettingsFavoritesTests.swift:241`: `XCTUnwrap failed: expected non-nil value of type "ProfileFavoritePostSelection"`
- **Code-level root cause**:
  At lines `238-240`, the test waits only for `!h.wire.paths.contains("list")` and immediately calls `owner.openPost(...)`. However, `h.wire.paths` records `"list"` inside `Wire.send` **before** `ProfileFavoritesReader.favoritePosts(pageNumber:pageSize:)` resumes on `@MainActor`, validates the response, and populates `acceptedPosts[101]`. Inside `ProfileSettingsFavoritesOwner.openPost` (`App/ProfileSettingsFavoritesRoute.swift:97`), `offered.access.reader.selectPost(post, renderedScope: offered.access.key.scope)` returns `nil` until `acceptedPosts` contains post `101` (and `owner.posts.open` requires `AccountCollectionFavoritesView` to have mounted `owner.posts.appear`). Calling `openPost` before `acceptedPosts` is populated deterministically returns `false`.

---

## 5. `WorkshopPaidInstallNormalFlowTests.testRealHostedInstallModalDismissAndReopenRetiresOldViewCallbacks`
- **Log location**: `logs/15_app_unit_full_keychain_host.log` line `14333`
- **Source location**: `Tests/AppUnitTests/WorkshopPaidInstallNormalFlowTests.swift:91-98`
- **Exact assertion failure**:
  - `WorkshopPaidInstallNormalFlowTests.swift:96`: `XCTAssertEqual failed: ("ready") is not equal to ("idle")`
- **Code-level root cause**:
  1. Line 93 creates an un-scened `UIWindow(frame: UIScreen.main.bounds)` rather than binding to the foreground `UIWindowScene` via `HostedNavigationSceneWindow`.
  2. Line 96 calls `presenter.dismiss(animated: false)` and then spins `for _ in 0..<1000 { if c.phase == .idle { break }; await Task.yield() }`. `Task.yield()` yields only inside Swift Concurrency's cooperative executor queue without advancing the main `CFRunLoop` / `CATransaction` commit phase that delivers UIKit's `viewDidDisappear` -> SwiftUI's `.onDisappear { controller.close(appearance) }`. After 1,150+ preceding tests in the full-suite run, 1,000 `Task.yield()` iterations complete within `< 2 ms` on the same runloop turn before UIKit flushes the dismissal appearance transition, leaving `c.phase == .ready`.
