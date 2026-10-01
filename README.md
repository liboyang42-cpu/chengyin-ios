# Questify · native iOS

SwiftUI-first iOS app, with UIKit bridges only when a feature needs them. Independent of the preserved Flutter app, which remains a candidate Android client. This folder is a new implementation, not a completed migration.

## First slice

- Native player / merchant registration-intent chooser
- Settings language preference: system / English / Simplified Chinese, device persistence
- Native navigation, sheets, system controls, Dynamic Type and light/dark support by construction
- English / Chinese String Catalog, three SwiftUI previews
- Pure Swift domain test package; dependency-free Xcode project

Registration currently opens an explicitly labeled **not connected** screen. No authentication, merchant authorization, API call, account creation, payment, or live data is implemented. UI behavior and accessibility have not yet been exercised on a simulator/device.

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

These Python checks do not compile Swift or demonstrate a working iOS app. See `docs/verification.md` for actual results, and `docs/migration-plan.md` for scope.

## Repository and security boundary

Target repository: `chengyin-ios` (public). Flutter history, deployment scripts, signing material and third-party artwork have not been copied. No open-source license has been assigned to this new code without an ownership decision.

## CI scope

`Native iOS checks` uses GitHub-hosted macOS for pure Swift unit tests and unsigned simulator/device compilation, plus a separate read-only Gitleaks job. It does not run UI interaction tests, connect a production backend, sign an IPA or upload to a store. No release credentials or build artifacts are used. A successful compile alone is not product acceptance.
