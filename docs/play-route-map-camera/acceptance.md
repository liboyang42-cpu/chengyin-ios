# Personal route-map inspection and camera controls

Status: dependent candidate for review; Apple execution NOT_RUN.

## Exact dependency and confirmed gap

This patch is based on frozen route-map tree `923e53cabfa6f881bc39b529871841f948512f58`. It must be applied after that candidate, not directly to published ancestor `d270598a904771bd077508c48dcb9b4991a0c639`. The frozen candidate and its saved archive are unchanged.

On that exact base, `App/PlayRouteMapView.swift:90–116` had an automatic initial camera and direct task-opening markers, with no explicit overview/current/other-stop preview controls. A user could pan away but had no local action to restore the route extent or inspect another visible stop while keeping the current task clear.

This is separate from existing foreground walking navigation. `App/WalkingNavigationView.swift:133–178` already implements authorized route/target camera controls and steps. `docs/walking-navigation.md` describes its provider route, distance, ETA and pause/resume. Nothing in that subsystem is reimplemented or changed. The target datum/region/visibility/revision/expiry evidence gates recorded in `docs/walking-navigation/source-target-contract.md` remain unresolved dependencies for actual navigation; this feature does not infer or supply them.

## Added user journey

1. Open the personal city-orientation route map and expand Map view controls.
2. Show all visible stops to recover a bounded route overview after manual panning. Straight dashed lines remain illustrative node order, not a walking route.
3. Focus the confirmed current stop, or select another safe visible stop from the menu or a map marker.
4. Inspect its complete name, supplied address and status. An outline indicates the previewed marker; the existing current-task flag and current-task button remain unchanged.
5. Open the existing task only when the original safe projection permits current/completed replay. The original current-task and equivalent-list buttons continue to open the task directly.
6. Return to overview to clear the preview, or return from the task and inspect another stop. No map choice changes server progress or the authoritative current node.

The controls begin collapsed to preserve the original map/list hierarchy. Their text and preview grow vertically at maximum Dynamic Type. English and Simplified Chinese labels distinguish inspection from task progress.

## Safety and fallback

- The same `PlayRouteMapPresentation` supplies all menu choices, markers and previews. Hidden nodes are absent; locked nodes cannot be inspected. Noncurrent available nodes may be inspected but cannot be promoted to a task-opening action.
- Camera requests bind the complete safe read and `PlayInteractionContext`, plus the visible map lifetime. Buttons capture one-shot gate requests at render time. Consumed, refreshed or foreign-read requests cannot override a newer preview or camera.
- A preview validates its exact read again before rendering. Byte-identical reloads still retire it. No preview is saved to persistent storage.
- A missing-coordinate current stop still has its preview and eligible task action, but no camera fit is applied. The view explicitly says the camera has not moved and offers the equivalent list/task fallback. No user location, arbitrary zero point, previous stop or inferred center substitutes for the current stop.
- The existing bounded `MapMarkerDensity.fit` handles camera geometry only. Polar or date-line-spanning extents fail fit and retain explicit manual/list fallback rather than claim a useful automatic region.
- A successful focus may reopen a user-collapsed map. Failure never moves the camera. Automatic viewport fitting does not request or collect location.
- No target authorizer, coordinate conversion, provider request, direction planner, location permission, server call, grant, completion method, W20 city board, fog, sharing or central Composition/Session change is included.

## Authored verification

- 10 Core XCTest methods: overview extent, current versus inspected identity, missing coordinate/all-coordinate fallback, locked/hidden/unknown identity filtering, ambiguous current choice, polar/date-line bounds, one-shot replacement, exact-read refresh and owner/lifetime loss.
- 2 app-unit methods: real SwiftUI controls grow at accessibility5 in both languages; rendering controls neither starts an additional read nor changes task/command authority.
- 5 new XCUITest methods cover only the added journeys: overview/current/other preview/task, missing-current-coordinate fallback, menu filtering and refresh, unsupported-extent fallback, and Chinese maximum text. The original eight route-map UI methods and all other existing UI methods remain byte-identical.
- 6 new Python source contracts. These and parser/scaffold checks are structural evidence only.

## Execution limits and central integration

Swift/Xcode compilation, Core/AppUnit/XCUITest execution, screenshots, real MapKit behavior, VoiceOver and physical-device/live account/provider acceptance are NOT_RUN in this Linux workspace. The DEBUG map accessibility value records a synthetic action witness; it is not provider execution or camera-pixel evidence.

This candidate does not edit shared duration weights, sharding or CI. Five added UI methods contribute 300 seconds under the existing default, bringing the inherited unintegrated inventory from 718/147 to 723 methods/148 classes. Historical central inventory/cost assertions therefore still require the reviewer's combined integration. The separate JSON estimates are explicitly unmeasured and do not replace measured evidence.

## Local result ledger

- PASS: project/scaffold deterministic regeneration (1,373 Swift app/test references; 7,873 bilingual keys).
- PASS: 6 focused source contracts; 2,023 complete source-contract tests ran, with 46 existing missing-source skips.
- PASS: strict pinned Tree-sitter parsing for all 7 touched/new Swift files (advisory only); existing map alternative-list contracts; whitespace checks.
- PASS: all 151 inherited UI source files, including the first route-map suite, are byte-identical to the dependency tree.
- NEEDS CENTRAL INTEGRATION: the 9-test historical creator-pending budget class has its same 3 inventory/cost snapshot failures with the now combined 723-method / 148-class inventory. Five new methods add 300 default seconds on top of the inherited 480 seconds; no budget values or tests were changed to silence the failures.
- NOT_RUN: all Apple compiler, XCTest, app-unit, UI, screenshot, VoiceOver, real map and device acceptance listed above.
