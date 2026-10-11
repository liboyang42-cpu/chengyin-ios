# Saved roam share-route privacy (P126 / P128, PA04)

## Implemented slice

The existing history-detail share sheet now projects a separate, locally rendered share route. Route inclusion still defaults off. When enabled, the preview and ImageRenderer export use the same card and remove 10% of the saved polyline length at each end, including interpolated endpoints for a two-point saved track. This operates on value copies; history storage, full route replay, counters and settlement remain unchanged.

Original POI markers are omitted from the exported route because they could independently reveal a removed endpoint. Empty, singleton and stationary tracks produce no route; date-line crossings also fail closed because the existing local schematic does not support longitude wrapping. No fallback exports the original track. Final computed endpoints must each have a positive finite displacement from the original endpoint and the retained route must have positive finite length. If floating-point interpolation cannot represent those insets, the route is hidden; an adjacent-Double route cannot leak unchanged endpoints. The prepared image is bound to the complete record and inclusion choice, invalidated on record changes, toggle changes and dismissal. The existing system share sheet still requires the user to choose its recipient.

Clipping is risk reduction, not anonymization. Interior points can revisit an endpoint and route geometry or displayed date/totals may still identify a walk. The existing pre-share review warning remains. This slice does not add persistent privacy preferences, adjustable percentages, public posting, share-token publishing, location acquisition or new remote services.

## Source alignment

The authorized master inventory identifies P126 history, P128 session and PA04 map/session/persistent-state privacy checks. P129/PA05 was reviewed only to choose a bounded independent increment; nearby team behavior is unchanged.

The retained mini-program session sharing implementation clips the saved track before constructing its preview/export route. Its default is 10% per end and saved simplified tracks are clipped by geometric length, not point count. Native code follows that behavior while using the existing native Haversine distance helper (the retained mini-program uses local planar distance). Native additionally omits POI markers and hides longitude-wrap tracks. Private source excerpts and source identities are retained only in the separate evidence bundle, not this public repository document.

## Verification and remaining gates

- 9 focused source-wiring checks: PASS
- 11 existing roam-experience source checks: PASS
- 10 existing history-live-entry source checks: PASS
- 14 existing replay source checks: 10 PASS, 4 FAIL because their frozen-source hash admission includes the modified math file. No catalog/admission/central gate was altered. Parent integration must reconcile this new source against the approved frozen-source contract before claiming aggregate acceptance.
- 9 actual retained mini-program pure-function cases: PASS (empty, singleton, two points, uneven spacing, interior vertices, duplicates, stationary, reverse, tiny distance). This is JavaScript source execution, not native parity execution.
- 3 changed/authored Swift sources: syntax parser PASS, not a typecheck.
- 17 Swift XCTest methods authored: NOT_RUN. Swift, swiftc, Xcode, simulator/UI and live-backend checks: NOT_RUN because those tools are unavailable in this cloud filesystem.

No TC01/TC02 App runtime acceptance is claimed. No push, deployment, payment, reward, publishing or private-source upload occurred.

## Apple follow-through

Run `swift test --filter RoamShareRoutePrivacyTests`, then an unsigned iOS build. Verify the ordinary history → record → share entry, off/on toggle and re-render, failure/retry, dismissal/reopen, account/record changes while presented, Reduce Motion, VoiceOver and English/Chinese. Confirm saved full-history replay remains unchanged, card and exported image match, POIs are absent and an empty/degenerate route never falls back to full history. The helper is appended to an already registered Core source; the view is already registered. No project membership or resource catalog edit is needed for the app code. The new XCTest is automatically discovered by Swift Package Manager; Xcode test-target membership remains outside this slice.
