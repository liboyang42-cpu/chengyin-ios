# Native design and motion direction

Status: implementation and visual validation in progress. This is a product direction, not a full visual/accessibility acceptance certificate.

## References and decisions

- [Apple Design Resources](https://developer.apple.com/design/resources/): native controls, typography, layout and Wallet patterns are the platform baseline
- [Airbnb's official activity flow](https://news-assets.withairbnb.com/wp-content/uploads/sites/21/2025/05/Experiences-flow-Summer-Release-2025-US.jpg): inspected public image; borrow the hierarchy of artwork, title, date/place, sectional details and a clear primary action, not its brand or unsupported features
- [Flighty's public interface](https://flighty.com/#at-the-airport) and [Apple's design interview](https://developer.apple.com/news/?id=970ncww4): state, time and the next meaningful action should remain prominent in ticket views
- Public [Refero Airbnb samples](https://refero.design/apps/search?app_id[id][]=2) were useful for grouped authentication/privacy forms. Login-only screens were not inspected. Mobbin's Explore page was blocked; no specific Mobbin flow is claimed as reviewed

References provide inspiration, not permission to copy screenshots, proprietary component code or assets into the app. Build the components in SwiftUI/UIKit and retain applicable Apple/third-party licenses.

## Visual system

Retain the minimal urban identity and existing purple tint: light #6D28D9, dark #C4B5FD. Use system semantic colors for text and backgrounds. Consumer discovery cards and tickets need a distinct content hierarchy; merchant administration can remain a native grouped Form.

Initial spacing targets are 16pt page/card padding, 8/12pt internal gaps and 24pt section gaps, with continuous content-card corners around 20pt. These are design starting points, not overrides of native control metrics. Typography must use semantic Dynamic Type styles, wrap at accessibility sizes, and avoid shrinking critical information to fit.

- Home: real artwork, activity name, date/place, price/status. Use featured and compact card variants. Missing images stay honest placeholders; do not invent ratings, distance, favorites, stock, currency or countdowns
- Activity detail: image/title/date/meeting place first, then introduction, route/map and tickets. A future bottom primary action must preserve existing eligibility and booking gates and not obscure content
- Ticket wallet: title/date/status first, reference number secondary. Status uses text plus an icon, never color alone. Preserve response ordering and duplicate-ID semantics. Do not add a fake QR code or nonfunctional Apple Wallet action
- Merchant: retain Form/Picker/TextField/file selection. Keep labels visible and errors actionable. Submission pending, approved and unknown outcome are different states. The current explicit alert keeps Cancel available; a longer future review can use a scrollable native sheet

[Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) belongs mainly to system navigation and controls, not stacked glass content cards. The baseline is iOS 17; higher-version system transitions must use availability checks and native fallbacks.

## Motion policy

Suggested values require device tuning; they are not Apple-prescribed durations.

| Interaction | Initial implementation direction |
|---|---|
| Custom card press | ~120ms to 0.98 scale; ~240ms restrained release. Do not add a second animation to native buttons |
| Filter change | ~180–220ms color/background change; maintain scroll continuity |
| Local disclosure | ~240–300ms restrained spring; interruptible and interactive |
| Loading | Stable placeholder or ProgressView, no fabricated percentage or endless decorative shimmer |
| Completion | At most one symbol/haptic response to a verified state transition; never on appearance or simple data loading |
| Failure | Local text/clear retry, no page-wide shaking or flashing |

Prefer [native springs](https://developer.apple.com/videos/play/wwdc2023/10158/), [symbol effects](https://developer.apple.com/documentation/SwiftUI/View/symbolEffect%28_%3Aoptions%3Avalue%3A%29) and system navigation. No animation package is required. Consider iOS 18+ system zoom only where stable identity and real destination continuity are established; iOS 17 retains NavigationStack transitions. Do not base ticket transition identity on an ID assumed globally unique.

With [Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion), remove custom scale, travel, bounce and parallax; use a brief fade or immediate update. Do not autoplay sound or add recurring global animation timers. LIVE state should update at an actual known start boundary rather than per-card one-second decorative ticking.

## Validation and limits

Inspected prior simulator screenshots showed template, order, participant, registration-limit and merchant states. They did not provide direct home/activity-detail/ticket-wallet acceptance, and static screenshots cannot prove motion, VoiceOver or frame pacing.

The next fixture run explicitly retains successful home, activity and ticket screenshots, including Chinese, dark appearance, accessibility3 text and Reduce Motion environment overrides. These are offline synthetic preview inputs, not proof that actual device settings, VoiceOver or live business flows were tested. Review the rendered images before claiming layout success.

Keep 44pt custom interaction targets, readable text/icon state labels and independent accessibility actions. Preserve current session/permission/unknown-outcome safeguards during all UI changes. Finish with actual device Release testing and Instruments for scrolling, refresh, interruption, background return and memory/frame performance; those release checks remain pending.
