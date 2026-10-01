# Native component and migration policy

## Implementation approach

The existing Flutter client is a source of business contracts, route behavior, validation rules, localization and test scenarios. Reuse those assets with traceable source references. Rebuild native UI composition and lifecycle instead of mechanically translating widgets to views. Flutter's renderer does not map its widgets one-for-one to UIKit controls.

https://docs.flutter.dev/resources/architectural-overview

## Preferred Apple components (provisional iOS 17 baseline)

| Need | Default | UIKit when justified |
|---|---|---|
| Navigation, identity entry, settings | NavigationStack, Form, Section, Picker, Toggle | UINavigationController for a demonstrated navigation interoperability requirement |
| Details and registration sheets | sheet + presentationDetents | UISheetPresentationController for presentation behavior unavailable in the SwiftUI surface |
| Alerts, menus, confirmations | alert, Menu, confirmationDialog | UIAlertController when an actual UIKit-hosted flow needs it |
| Search | searchable | UISearchController for complex UIKit collections |
| Activity / card lists | List or lazy stacks | UICollectionView + compositional layout + diffable data source for complex/high-volume layouts |
| Messaging | Native text input and keyboard-safe layout | UICollectionView timeline, UIHostingConfiguration cells, UIKeyboardLayoutGuide; test insertion, paging and keyboard recovery |
| Photos | PhotosPicker | PHPickerViewController in UIKit-owned flows; camera capture uses its own supported API and permission handling |
| Map and route overlays | SwiftUI Map / MapKit | MKMapView if required map delegate or overlay behaviors cannot be represented cleanly |
| Location / region monitoring | CoreLocation domain service | Not a view concern; server validation remains authoritative |
| QR / text capture | VisionKit DataScannerViewController wrapped in SwiftUI | Check isSupported/isAvailable at runtime; maintain a tested fallback for unsupported devices / denied camera |
| Sharing | ShareLink | UIActivityViewController for richer share configuration |
| System credentials | AuthenticationServices, Security/Keychain | Explicit bridges only at integration boundaries |

Apple UIKit is the platform framework, not a generic term for a third-party template library. Use third-party packages only after a concrete gap, maintenance/license review, and build compatibility check. Do not add dependencies merely for visual novelty.

SwiftUI/UIKit interoperability: https://developer.apple.com/documentation/swiftui/uiviewcontrollerrepresentable
UIKit: https://developer.apple.com/documentation/uikit

## Quality gates

Prefer semantic system fonts, colors, controls, materials and safe areas. Support Dynamic Type, VoiceOver labels/actions, Reduce Motion, increased contrast, dark mode and locale expansion. Do not force fixed-height text cards. Newer OS-only effects require availability guards and older-OS fallback. A native framework does not automatically ensure good UX: state, dismissal, repeated action, back navigation and business result still require tests.

## Accelerating the migration safely

1. Inventory source route declarations and feature/API files; never equate lexical declarations with working pages
2. Import only the selected slice's existing English/Chinese literals into a candidate String Catalog with `tools/import_arb_catalog.py`; all candidates remain `needs_review`
3. Queue ICU plural/select/placeholders and percent formats for semantic conversion into typed native formatting; never flatten them
4. Generate Codable models/client operations from a verified OpenAPI schema if one exists; otherwise verify actual JSON envelopes, optionality, dates, pagination, money precision and error behavior before drafting models
5. Implement a small set of native list/form/detail/state patterns, then migrate vertical flows through those patterns
6. Convert existing expected behavior into XCTest/XCUITest scenarios rather than copying Flutter test APIs
7. Compile every slice; retain separate native UI/device/backend gates. Reuse approved/licensed assets only, without copying old deployment files or repository history

The initial importer has six offline Python tests and a 14-string auth-copy proof-of-concept. This is resource conversion, not 14 working UI screens or proof of correct English wording. A schema-driven client generator has not been installed or run.
