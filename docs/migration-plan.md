# Native iOS migration plan

Architecture: SwiftUI + necessary UIKit for iOS; retain the separate Flutter client for future Android work.

## Boundaries

- Preserve Flutter source, open migration PRs and history unchanged
- Share backend business contracts, not Dart UI implementation. Neither this chooser nor local state grants merchant permissions
- SwiftUI for screens/navigation/forms/settings. Use UIKit via UIViewControllerRepresentable / UIViewRepresentable only for a verified capability gap or existing platform SDK. Do not add a cosmetic bridge solely to claim UIKit usage
- Use Apple frameworks where they meet the requirement; audit WeChat/Google/Facebook SDK needs before adding dependencies. No third-party login is enabled by this scaffold
- String Catalog from the first screen. Apply selected locale to dates, numbers, native prompts and server error mapping as those features are implemented. Server content and user text are not automatically translated
- Keep tests, previews, fixtures, native simulator, device, backend and visual acceptance separately recorded
- Provisional iOS 17 minimum; this differs from older Flutter notes describing iOS 13 support. Resolve oldest-supported-device requirement before expanding implementation
- iOS native development still needs Xcode/macOS for compile/simulator. The initial Linux development environment lacks them; native build verification remains pending

## Work batches and completion evidence

1. Foundation: repository, Xcode project, player/merchant chooser, language/settings, accessibility and preview scenarios. Source scaffold compiled on the first hosted macOS run; native interaction acceptance remains pending
2. Account vertical slice: backend-confirmed login methods, registration intent, server roles, Keychain credentials, refresh/single-flight retry, logout, account switching, cold-start restoration. No UI may fabricate success
3. Player primary routes: feed, roam, template square, clubs, profile. Reconcile mapping to Flutter route definitions; discovery → detail → registration → order → ticket. Empty/error/loading and interrupted routes are mandatory
4. Play and location: foreground authorization, MapKit, location accuracy and denial, QR entry, geofence/server validation, rewards and next node. Native location alone is not proof of a successful game check-in
5. Merchant / club: onboarding and approval, activity publishing, inventory/pricing, collaboration/invites, tickets/verification, refund status; enforce server permissions
6. Messaging / remaining modules: send/retry/read, role isolation, drafts and attachments, notification/deep-link recovery; reconcile all source modules without claiming equal completion
7. Release gates: localizable copy review, Apple design/accessibility, privacy/legal entity, approved API/Bundle ID/Team/entitlements, dependency/material licenses, signed build, TestFlight installation and live test accounts. Publishing requires separate approval

## Current evidence to reuse carefully

Source inventory baseline: public Flutter PR8 head a63e9e91c82a3282e8dd7138f943b1a8cbfc021d, not merged main. Generated inventory records feature folders and lexical route declarations only. Existing Flutter CI has unresolved failures; porting does not make them disappear. Do not label historic 128/129 page counts or 293 visual states as native completion.

All business workflows, backend contracts, assets and native integration choices require source review before reuse. Existing public defaults deliberately use an invalid API endpoint. Validate legal entity and legal document metadata before release. Do not enable broad ATS exceptions when integrating third-party SDKs.
