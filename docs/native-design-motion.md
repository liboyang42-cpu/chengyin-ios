# Native home and ticket-card refinement

## Scope

A bounded native SwiftUI refinement of `HomeFeedView`, `TicketWalletView`, and `TicketWalletDetailView`, using existing source data and the existing adaptive purple `QuestifyPalette`. Minimum iOS 17. No packages, generated artwork, account/session changes, payment actions, QR codes, or new navigation routes.

- Home: supplied artwork has the largest visual region; missing artwork does not invent an image. Type, title, date, location, and source amount have a clear reading order. Currency remains explicitly unprovided. Existing Beta/LIVE source semantics remain unchanged.
- Wallet: status has both a symbol and localized text. Title and date precede the registration number. Unavailable actions retain their explanation. Status does not enable navigation; only the existing `ticket.action == .detail` rule does.
- Detail: a concise ticket header separates status/date/place from selectable ticket/contact fields and benefits. Read-only redemption notices remain visible, and detail still fetches by ID instead of trusting a list row.
- Typography: system text styles; no minimum font scaling. Metadata and entitlement rows change to leading-aligned stacks at accessibility text sizes. Decorative artwork and symbols are hidden from VoiceOver, metadata has explicit spoken labels, and titles remain independently addressable by existing test IDs.
- Surfaces: opaque system grouped colors, continuous 20-point card corners, 16-point content inset, adaptive purple accents and an increased-contrast border. No custom glass content surfaces or heavy shadows.

## Motion inventory

| Trigger | Response | Reduce Motion |
| --- | --- | --- |
| Press/release a home or ticket navigation card | Native ButtonStyle, 0.98 scale, 120 ms ease-out press, 240 ms spring release with 0.08 bounce | No scale or animation; immediate opacity feedback |
| A supplied image loads | 180 ms opacity transition confined to that image | Immediate update |
| A status key changes while its badge remains mounted | 180 ms opacity content transition confined to the badge | Immediate update |
| Push, pop, refresh, segmented picker | System behavior | System behavior |

The action occurs on normal native button activation; it never waits for the animation. No repeating shimmer, pulse, autoplay, confetti, success haptics on read, whole-list refresh animation, or matched geometry tied to nonunique server IDs.

Home's previous per-card one-second timer is replaced by `HomeFeedStartSchedule`. It returns the requested initial date and, only when still future, the parsed source start boundary. Past starts have one entry. Topic rows and unparseable/local dates lacking a verified source timezone have no live schedule. The predicate is still `start <= now`; no end state or timezone is invented.

## References and application

Verified by the parallel design research, with the implementation using principles rather than copying assets:

- [Airbnb's official 2025 Experiences flow](https://news-assets.withairbnb.com/wp-content/uploads/sites/21/2025/05/Experiences-flow-Summer-Release-2025-US.jpg): real artwork, title, and compact metadata hierarchy. No copied photography, ratings, favorites, or purchase controls.
- [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/): leave system navigation/control treatments to the OS; keep content legible on an opaque surface.
- [Apple: Animate with springs](https://developer.apple.com/videos/play/wwdc2023/10158/): responsive, interruptible native feedback. The precise timings above are this project's choices, not prescribed Apple values.
- [Apple: accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion): suppress card scale/bounce and content animation.
- [Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility): semantic color, readable typography, adequate targets, and status not conveyed only by color.
- [Apple: TimelineSchedule entries](https://developer.apple.com/documentation/swiftui/timelineschedule/entries%28from%3Amode%3A%29): finite ordered schedule for actual state boundaries rather than continuous polling.

The supplied screenshot packages were inspected: the d402/b47 discovery shelf shows a generic joined-list visual hierarchy; the b47 order detail shows equal-weight form metadata. These are related-surface observations. Neither package contains home or ticket-wallet screenshots. All home/ticket changes here are source-based design judgments until new simulator captures are reviewed. No visual, VoiceOver, or animation acceptance is claimed from those old images.

## Integration and verification

Copy the four modified App files plus `QuestifyMotion.swift` and `QuestifyMotionComponents.swift`. Merge the two English/Simplified Chinese entries from `native-design-motion-localizations.json` into the String Catalog, then regenerate the project at the integration root. Shared composition, project, resources, fixtures, workflows, and Square files were not edited in this worktree.

Locally passed:

- Nine focused Python source guards in `Tests/ContractChecks/test_native_design_motion.py`
- Twelve existing Python tooling tests
- `git diff --check`

These are structural checks, not a Swift compiler. Swift/Xcode and simulator execution are unavailable in this Linux worker. Parent-owned home/ticket screenshots and Chinese/dark/accessibility/Reduce Motion fixture tests must run on the integrated revision. In addition, verify press-cancel while scrolling, immediate navigation and repeated Back/reopen, image arrival, all ticket statuses, unknown and partial responses, session invalidation, accessibility-size wrapping, VoiceOver reading order, and boundary/foreground behavior before claiming acceptance.

## Integration update, 2026-10-01

b754 simulator captures now include home light and Chinese dark/accessibility3 states; both relevant presentation tests passed. These synthetic captures were inspected at integration. They do not prove actual VoiceOver order or system Reduce Motion behavior. `QuestifyReduceMotion` reads the real system setting and supports a DEBUG-only policy flag; it does not write the read-only environment key. Subsequent shared image-card changes still require their own runtime screenshots.

The user-selected entity-card direction is full-bleed source artwork, a feathered bottom dark gradient, and white overlaid text with no outline. `QuestifyImageEntityCard` is reused for club and topic/favorites. The dark scrim grows with text; Dynamic Type does not impose a fixed text-height crop. Missing artwork uses an explicit neutral fallback, not a fabricated photograph. The supplied reference portrait, badges and counts are not app assets or product requirements. Award quality is an aspiration, not a verified certification.
