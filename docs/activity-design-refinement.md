# Native activity list and detail refinement

## Scope

This is a bounded presentation change for iOS 17 and later. It reuses the existing `QuestifyCardArtwork`, `QuestifyMetadataLine`, `QuestifyStatusBadge`, card surfaces, and motion policy. Core contracts, readers, authentication, session state, registration policy, fixtures, payment paths, and requests for business data are unchanged.

- List: supplied artwork, a semantic title, source date/location, and an explicitly labeled starting amount. Blank address names fall back to the supplied address. No remote image is requested when an HTTPS source is absent or unsafe.
- Detail: supplied artwork and title first, followed by source date/location; a distinct supplied street address remains visible. Introduction, optional coordinate-backed map, and ticket cards have separate sections. Ticket descriptions are shown when supplied.
- Tickets: source price and the existing currency disclosure remain together. Sold-out and unprovided inventory states have both text and symbols. No in-stock claim, rating, countdown, currency, or route is inferred.
- Action: the existing registration opener moves to a native prominent button in a bottom `safeAreaInset`. The inset reserves scroll space. It only exists inside the already allowed-detail branch when the caller sets `registrationEnabled`; the unchanged sheet retains `creationPolicy: .disabled` and all downstream checks. No booking/payment button appears for the default read-only fixture or club gate. The existing migration notice remains visible.
- Accessibility: semantic Dynamic Type styles, wrapping without shrinking, a header trait for the activity title, independently preserved title/price/status identifiers, labeled metadata, decorative artwork hidden from VoiceOver, and native button interaction. The shared card surface provides increased-contrast borders and light/dark semantic colors. A native button needs no second custom press animation.

## Motion

Activity list navigation cards use the existing interruptible 0.98 press feedback. Supplied-image arrival uses the existing short local opacity transition. Both use the existing `@QuestifyReduceMotion` policy; this change neither writes to the read-only system accessibility setting nor introduces a separate override. Detail navigation, the registration sheet, refresh, and the prominent button retain native behavior. There are no new timers, shimmer, success effects, haptics, page-wide transitions, or animation delays before navigation.

## Reference and evidence

The hierarchy follows the direction already recorded in `native-design-and-motion.md` and `native-design-motion.md`, including [Airbnb's public Experiences flow](https://news-assets.withairbnb.com/wp-content/uploads/sites/21/2025/05/Experiences-flow-Summer-Release-2025-US.jpg) for artwork/title/date/place/sections. No third-party assets or component code were copied. [Apple's safe-area inset API](https://developer.apple.com/documentation/swiftui/view/safeareainset%28edge%3Aalignment%3Aspacing%3Acontent%3A%29-6gwby) provides the native bottom-action placement; [Apple's buttons guidance](https://developer.apple.com/design/human-interface-guidelines/buttons) remains the control baseline.

The available a1be screenshot of `HomeFeedFlowTests.testTypedDestinationsAndPriceCurrencyDisclosure` was actually inspected. It shows the pre-redesign home metadata hierarchy, not this activity implementation. No direct activity detail screenshot was available in those prior packages. New activity captures, VoiceOver testing, and motion acceptance remain pending; source-based decisions and parser success are not visual/runtime proof.

## Integration

Copy these files from the isolated activity worktree:

- `App/ActivityBrowserView.swift`
- `App/ActivityDetailView.swift`
- `App/ActivityPresentationComponents.swift`
- `Tests/ContractChecks/test_activity_design_structure.py`
- This note and `activity-design-localizations.json`

Merge the five bilingual keys from `activity-design-localizations.json` into the root-owned String Catalog, then regenerate the project to include the new Swift component file. The shared project/catalog and all existing UI tests were intentionally left unchanged here.

## Verification

Locally passed on the finished worktree:

- 10 focused activity presentation source guards
- All 32 contract/source guards, including those 10
- All 13 existing Python tooling tests
- Supplementary Tree-sitter parsing of the three changed/new Swift files, with zero recovery diagnostics
- `git diff --check`

These are not Swift compilation or runtime checks. The aggregate scaffold check requires the root-owned catalog merge and project regeneration first. Cloud Xcode compilation and the root-owned simulator suite are the authority for Swift/Apple API validity and runtime behavior.

On the integrated revision, retain list/detail screenshots in English and Chinese; dark appearance; accessibility3 text; and Reduce Motion policy. Include the read-only nullable-ticket fixture, club gate, explicit-retry flow, and draft-query pagination. Verify real/failed/missing artwork, long title/date/address/ticket descriptions, valid map coordinates, and absence of the map for coordinate-free fixtures. In an already authorized registration-enabled fixture, verify one native action, bottom content visibility, dismiss/reopen, and unchanged downstream gates. Test VoiceOver reading order, scroll-cancelled card presses, repeated Back/reopen, refresh, and system Reduce Motion on a real device before acceptance.
