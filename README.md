# Questify · native iOS

SwiftUI-first iOS app, with UIKit bridges only when a feature needs them. Independent of the preserved Flutter app, which remains a candidate Android client. This folder is a new implementation, not a completed migration.

## Current implemented slices

- Native player / merchant registration-intent chooser
- Settings language preference: system / English / Simplified Chinese, device persistence
- Native navigation, sheets, system controls, Dynamic Type and light/dark support by construction
- English / Chinese String Catalog, three SwiftUI previews
- Read-only native activity list/detail and MapKit
- Registration contracts and a native VisionKit/UIKit scanner component
- Pure Swift domain test package and targeted XCUITest scenarios; dependency-free Xcode project

Registration intent opens an existing-account sign-in form. The service address is deliberately unset, so sign-in is disabled until an approved endpoint is configured. Password login, current-account restoration and logout code are wired, but no live backend validation has been performed. New account registration, third-party sign-in, merchant application and most business flows remain pending. Targeted entry/language/scanner-fallback simulator tests have passed; full UI, accessibility, physical-device and backend acceptance remain pending. See `PROGRESS.md` for exact evidence.

## Build and test (requires an approved toolchain)

Minimum provisional deployment target: iOS 17. Final supported OS range is still to be confirmed. The Bundle ID is deliberately a non-production placeholder. No signing team is configured.

On a Mac with Xcode 15 or later:

```sh
xcodebuild -project Questify.xcodeproj -scheme Questify \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
swift test
```

Open `Questify.xcodeproj` for the SwiftUI previews. Test English/Chinese, system language, reopen after choosing a language, text sizes up to accessibility maximum, VoiceOver, dark mode, role-sheet dismissal and repeated selection. Device and live-backend validation remain separate gates.

Project structure and resource checks available in this cloud workspace:

```sh
python3 tools/generate_project.py
python3 tools/check_scaffold.py
```

These Python checks do not compile Swift or demonstrate a working iOS app. See `PROGRESS.md` for the latest verified revision, `docs/verification.md` for earlier evidence, and `docs/migration-plan.md` for scope.

## Repository and security boundary

Target repository: `chengyin-ios` (public). Flutter history, deployment scripts, signing material and third-party artwork have not been copied. No open-source license has been assigned to this new code without an ownership decision.

## CI scope

`Native iOS checks` runs on pushes to `main` and `migration/native-ios`, PRs and manual dispatch. It uses GitHub-hosted macOS for pure Swift tests, unsigned simulator/device compilation and targeted simulator UI tests, plus a separate read-only Gitleaks job. It does not connect a production backend, sign a distribution IPA or upload to a store. No release credentials or build artifacts are used. A successful compile or limited UI suite is not complete product acceptance.

Development stays on `migration/native-ios`; one overall PR follows completion of the full migration and its acceptance gates.
