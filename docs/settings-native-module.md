# Native settings, About and source legal documents

Status: additive source-backed native slice. Complete feature/runtime/release parity is not claimed.

## Delivered

- Six independent native Toggle preferences: sound/haptics/airplane ambience/ocean/raindrop/forest. Source defaults are true/true/true/false/false/false. `airplane` is explicitly an ambient-sound preference, not the operating system setting.
- Local JSON persistence uses the exact source `scene_sound_haptics` key in the native app's UserDefaults. This is intentionally a non-sensitive preferences store, not Flutter Secure Storage; no old Keychain entry is read, and no cross-app storage migration is claimed. Missing JSON keys retain source defaults, present null/non-Boolean values fail, unknown fields are ignored. Failed reads never overwrite corrupt values. Writes are serialized and displayed only after success. UserDefaults readback verifies the in-process saved value, not physical disk durability.
- Native About reads display name, version and build from the actual native Bundle. No copied Flutter `1.0.0` version or substitute metadata. The original tagline is retained in both languages. Source contact information is presented as selectable text only for CN; US/missing-market contact stays unavailable.
- Offline attribution strings match the source exactly. They are labelled source-app credits; this slice imports no third-party artwork. URLs are selectable text, not external-launch controls.
- Three typed legal routes. Unknown string routes retain the source user-agreement fallback, but market selection still fails closed. CN source agreement v2.2 and cancellation notice v2.1, both dated 2026-08-12, are copied verbatim with all 13/5 sections. Version is now visible as source metadata, although Flutter rendered only its effective date. Hanging indentation preserves exact list-marker/body text.
- Loading, retry, missing text and source-document states. Overlapping legal reads use generation checks; dismissal invalidates delayed results. Legal text remains Chinese under an English UI and is explicitly labelled source content with no approved English/native-app legal review implied.
- CN app privacy policy remains missing, as it is in source. All US documents remain missing because none were supplied. Missing build-market metadata cannot fall back to CN. The module never takes a language parameter to choose market/legal content.
- Read-only explanatory destinations for unconnected privacy/location withdrawal, marketing consent, and account cancellation. There are no action controls that pretend these workflows are implemented.
- A strict passive `SettingsPlayerCode` decoder models the source `data.qr` field and only accepts HTTPS image URLs without embedded credentials or a fragment. No endpoint, image download, generated QR or live code reader is installed.

## Source evidence

- `app-audit/lib/feature/settings/sound_haptics_settings.dart`: six keys, defaults, partial decoder, failure semantics, storage key
- `app-audit/lib/feature/settings/settings_page.dart`: sound sheet serialization, offline attribution, existing role-dependent account navigation, privacy withdrawal sequencing
- `app-audit/lib/feature/settings/about_page.dart`: tagline, CN contact, app-info presentation, protected personal-code states
- `app-audit/lib/feature/legal/legal_docs.dart`: exact source legal text/versions/dates and intentionally empty app privacy policy
- `app-audit/lib/feature/legal/legal_doc_page.dart`: route fallback, read-only document body, hanging list layout; its login consent statement is NOT ported or wired
- `app-audit/lib/data/api/account_api.dart:62`: `POST /api/user/player-code` may generate/reuse a server-side personal code, not merely fetch static art
- `app-audit/lib/feature/settings/marketing_consent_sheet.dart`, `lib/data/models/marketing_consent.dart`, `lib/data/api/page_parity_api.dart`: per-merchant/channel server truth and write-then-readback requirement; not converted into local switches

## Integration (preserve the current target)

No main/shared file was changed during isolated authoring. Use the current target checkout, never replace it with the worker directory or an older snapshot.

1. Copy the new `Core/Settings*.swift`, `App/SettingsAboutView.swift`, `App/SettingsFixtureSupport.swift`, `App/SettingsLegalDocumentView.swift`, and `App/SettingsSupportSections.swift` files to matching directories. There is intentionally no replacement `App/SettingsView.swift`.
2. In the existing `SettingsView` Form, insert `SettingsSupportSections(market: RegionalLaunchConfiguration.market)` after its language Section. Keep its @AppStorage key, RegionalLaunchConfiguration.language calls, independent market row, language notice, enclosing NavigationStack, Done toolbar and locale environment unchanged. Do not introduce another production Settings root or language picker. Existing account/profile/participant/merchant/play navigation remains with its current owner.
3. Merge the 49 unique `settingsNative.*` entries in `docs/settings-native-localizations.json` into the current `Resources/Localizable.xcstrings`. Keep every existing key and locale intact; if a key already exists with different values, stop and resolve instead of overwriting it. These UI strings do not translate or rewrite legal bodies.
4. Add `case settingsNative` to the existing DEBUG `ModuleFixture` enum and `case .settingsNative: SettingsFixtureHostView()` to its current switch. Preserve every other fixture case, including growthCenter, officialEvents and any concurrent project-editor work. QuestifyApp already excludes production AppSession creation for a selected ModuleFixture; no additional root/session branch is required.
5. Copy both new test files into their matching CoreTests/AppUITests directories. The existing UI shard runner discovers `SettingsNativeFlowTests` automatically. Copy this document, the localization fragment, and the two uniquely named source-check Python tools if desired.
6. Run `python3 tools/generate_project.py` against the target so all new Swift source/test files are in the Xcode project. Do not hand-edit the generated project and do not replace the Package manifest.
7. Re-run the target's scaffold/resource checks, project-generation idempotence check, supplementary parser and Python suites. Source parity command (when Flutter source is available): `python3 tools/check_settings_native.py --flutter-root ../app-audit`.
8. On the approved Apple toolchain, run `swift test`, unsigned CN/US simulator/device builds and all UI shards. Exercise `--uitesting-module settingsNative` plus `--uitesting-settings-scenario` content/loadFailure/saveFailure/legalFailure/missingMarket/missingMetadata. Set `--uitesting-market CN|US` independently of AppleLanguages. No test enables HTTP, device settings or consent operations.

## Verification at isolated handoff

PASS, source-only:
- Exact regenerated legal source comparison: 13 + 5 sections, two versions/dates, privacy still empty
- All 49 EN/zh-Hans labels present with unique keys
- Exact source-app attribution strings and links
- Static checks reject HTTP requests, URLSession, external URL opening, OS location/audio/haptic control, live consent methods or duplicate @AppStorage
- Pinned Tree-sitter parse: 10 Swift files, zero ERROR/MISSING recovery nodes (tree-sitter 0.26.0 / tree-sitter-swift 0.7.3)

AUTHORED, not executed: 25 XCTest cases and 11 XCUITest cases. Includes persistence, corrupt/missing data, serialized/failed/cancelled operations, newer/dismissed legal loads, regional isolation, missing version metadata, unsafe/missing personal-code values, reopen/retry, bilingual UI and maximum Dynamic Type.

NOT_RUN: Swift typechecking, Swift tests, Apple SDK compilation, simulator screenshots/UI execution, device validation, real HTTP, account/consent operations, legal acceptance or release verification. Swift and Xcode are absent in the worker environment. Static checks and parser success are not runtime evidence.

## Remaining source parity and release blocks

This slice does not implement server personal-code generation/image fetch/refresh or its authenticated session lifecycle, source phone-call action, source copy buttons (text selection is the safe read-only alternative), profile identity-card navigation, inviter, sign-out, marketing consent reads/writes, location-consent revocation/tracking shutdown, OS permissions, account-deletion checks/SMS/cooling-off/submission, or audio/haptic playback consumers. Existing separately migrated account/navigation flows are not duplicated. No screenshots or live-runtime success are claimed.

The CN source agreement still refers to mini-program privacy and source business behavior. Rendering it is preservation evidence, not legal approval for the native app. Native CN privacy policy, reviewed English documents and US-specific terms/privacy/cancellation policy remain release blockers. Do not infer acceptance from opening, scrolling, dismissing or choosing a language. No consent line, acceptance button, legal write or account operation is added.
