# W1 / W2 / C1 native reference reuse

Implementation baseline: `bb1fb21af582c9eba6114a548f2d393c4184ea50` (2026-10-02).
This finite UI packet changes no provider, runtime grant, permission prompt, routing engine,
or third-party dependency. It does not establish production or release acceptance.

## Applied composition

- W1 reuses the existing foreground-only `WalkingNavigationCoordinator`, MapKit polyline,
  target authorization and current-request checks. `ActiveDestinationSummary` is a stateless
  projection of that existing data. The native map receives a bottom safe-area inset rather
  than an overlay covering its attribution. The summary scrolls at large text sizes.
- Complete steps use one native sheet and NavigationStack. Accessibility sizes use large
  detents. Provider attribution, advisories, safety and the verification boundary remain in
  the detail. The sheet reads the live coordinator rather than saving an independent route;
  loss of the route dismisses it. Closing the sheet returns accessibility focus to its button.
- Phase status, loading, pause and start/resume availability have read-only presentation
  properties on the existing Phase enum. No additional phase or completion criterion exists.
  ETA values now carry localized minute units.
- W2 keeps the original manual area and explicit map opt-in. Synthetic fixtures now exercise
  that same map opt-in instead of bypassing it. Choosing a list row does not enable tiles or
  request location. Map and list selections use identical existing domain-prefixed IDs.
- The native area/filter/sort controls occupy one normal-size row, with a vertical fallback
  when space is insufficient. Additional text filters remain in the native filter Form;
  cancelling its draft does not modify the active query. Applying, searching, changing area,
  or changing account scope clears the old selected-place summary. Existing query gates and
  scope checks remain in place. Selection buttons announce their associated place name.
- C1 retains the existing full-image, bottom gradient, white overlaid text, 20pt inset, 24pt
  corners and no-stroke composition. No reference artwork is bundled. Titles, subtitles and
  metadata explicitly allow unlimited lines, including normal text sizes. Invalid or absent
  image sources keep the existing neutral decorative fallback. No image-origin policy changed.
- The test-only maximum text flag selects accessibility5; it does not change device settings.
  Increase Contrast is authored through UIKit's app-unit hosting-controller trait override,
  not an unsupported write to SwiftUI's read-only colorSchemeContrast environment value.

## Reference evidence and rights

Only structural hierarchy was adapted. The separately retained official App Store thumbnails
were inspected before edits; they are marketing evidence, not runtime or accessibility proof:

- [AllTrails](https://apps.apple.com/us/app/alltrails-hike-bike-run/id405075943): discovery,
  detail, and navigation screenshots (map above statistics; photo-first results)
- [Flighty](https://apps.apple.com/us/app/flighty-live-flight-tracker/id1358823008): map above
  compact current-trip summary

No reference images, brands, proprietary icons or third-party code were copied into the app.
The existing cards, native controls and existing tokens were reused.

API verification: Apple's [colorSchemeContrast](https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast)
is read-only; [traitOverrides](https://developer.apple.com/documentation/uikit/uiviewcontroller/traitoverrides-1z1cc)
provides the mutable app-unit trait seam. The authored accessibility audit uses Apple's
[XCUIAccessibilityAuditType](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityaudittype).

## Authored acceptance, not executed on Apple here

| Surface | Authored checks | Status |
|---|---|---|
| W1 phases and actions | Every phase label; only preparing phases load; stale scope cannot restart; existing coordinator cancellation/expiry suite retained | Swift NOT_RUN |
| W1 navigation UI | Route summary → steps → close → reopen; cancel/resume; routing cancellation; denied/no-route/locked; near-destination boundary; expired scope dismisses detail | XCUITest NOT_RUN |
| W1 bilingual accessibility | English/Chinese, accessibility5, dark, Reduce Motion, scroll to steps and close/reopen, synthetic screenshots | XCUITest/rendering NOT_RUN |
| W2 selection and filters | List/pin shared selection; no automatic map; clear; filter cancel/reopen/apply; explicit manual region change; scope change | XCUITest NOT_RUN |
| W2 states | Delayed loading; first-load error and retry; empty results; existing partial/missing-coordinate cases retained | XCUITest NOT_RUN |
| C1 layout | Long bilingual content grows at 300pt width and accessibility5 under UIKit high contrast; safe URL/missing image policy | App-unit NOT_RUN |
| C1 accessibility | Normal/light and maximum/dark bilingual synthetic screenshot cases; contrast/text-clipping/description audit | XCUITest/rendering NOT_RUN |
| All three | Real VoiceOver read order, actual Increase Contrast setting, small and main CI iPhone screenshot comparisons, real map attribution visibility | Manual Apple acceptance NOT_RUN |

The offline source/parser/tooling results in the packet are supplementary. No Swift compiler,
Xcode, Simulator, actual screenshot capture, device GPS, live provider, or production backend
ran in the Linux workspace. Run the existing complete Apple CI gates on the integrated commit;
include the new Core, app-unit and UI test files by regenerating the project. Keep every
unexecuted matrix item explicitly NOT_RUN until that exact commit supplies evidence.

## Integration source-review corrections

The independent source review inspected the pinned AllTrails/Flighty reference pixels and the exact packet before integration. Layout-only container identifiers were moved to semantic leaves (or the real Map control) so Filter, selection-clear and offline pin actions keep distinct identities. The new routing-cancel fixture now uses a cancellation-resumed continuation rather than a two-second timer. Scope-expiry UI explicitly triggers a nil-default DEBUG control after the steps sheet is visible, then uses the existing coordinator synchronization and the unchanged disappearance assertion. No production clock, cancellation policy, endpoint, provider, grant or location permission changed.

Two new source regressions fail on the original packet and pass on the corrected source; two app-hosted tests are authored for controlled cancellation/restart and explicit scope invalidation. Those XCTest cases and post-fix layout/VoiceOver/contrast execution remain NOT_RUN until Apple CI. Increase Contrast evidence is currently an authored app-hosted trait-override test, not a claim that a simulator/device setting was changed.
