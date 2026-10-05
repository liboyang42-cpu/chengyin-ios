# Native migration execution method

Decision date: 2026-10-01. The 1–2 day request is a sprint target for substantial integrated progress, not a promise of full business parity or release acceptance.

## Selected approach

Keep the independent SwiftUI/UIKit client and retained Flutter Android source. Implement bounded business modules in parallel, each owning separate files and supplying source-linked contracts, localized native views, fixtures and tests. Integrate through one session/navigation layer on `migration/native-ios`; do not create a PR per component.

Copy verified business meaning rather than mechanically translating widget syntax. Reuse source endpoint fields, nullable-value semantics, translations and state transitions. Generated resources remain review candidates until checked. Native platform behavior, permissions, payments and account isolation require explicit implementation and acceptance.

Use fast structural/domain checks during authoring and module-level integration builds. Run complete UI regression at integrated checkpoints; implementation of other isolated modules can continue while CI runs. Do not skip failing tests or report partial checks as a complete pass.

## Research behind the choice

- Flutter officially supports embedding a Flutter module into a native host: https://docs.flutter.dev/add-to-app . This can preserve existing screens during an incremental rollout, but retains Flutter runtime and integration costs. It is an alternative if scope or release urgency changes, not the selected full-native architecture.
- Sebastian Röhl's first-person article concerns choosing SwiftUI for the new FocusKit app; he explicitly retains HabitKit in Flutter. It does not establish a fast automated rewrite of a large existing app: https://sebastianroehl.substack.com/p/from-flutter-to-swiftui-a-case-study .
- Apple's Swift OpenAPI Generator generates typed clients from an OpenAPI document: https://github.com/apple/swift-openapi-generator . The prerequisite is an accurate reviewed schema. No complete approved schema is available for this client, so generator adoption must not invent undocumented response shapes.
- Apple supports isolated interface previews with sample data: https://developer.apple.com/documentation/xcode/adding-previews-to-your-interface-files . Previews still require the Apple toolchain; they are not runnable interactive iOS validation in the Linux authoring environment.
- Point-Free's SnapshotTesting supports view/trait configurations and reusable snapshot states: https://github.com/pointfreeco/swift-snapshot-testing . This is the preferred candidate for expanding visual-state coverage. A snapshot baseline requires human/visual review, consistent simulator versions and synthetic non-sensitive data. It does not replace end-to-end interactions or prove live backend behavior. Research selection is not a claim that this dependency or snapshot suite has already been installed.
- Apple String Catalogs support localization and plural variants: https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog . Existing ARB literal conversion is reusable; ICU/placeholder/plural semantics need explicit conversion review.

## Reporting

Count source-mapped features separately from SwiftUI view files. Report authored, compiled, fixture-tested and live-verified states. A menu link or unsupported placeholder is not migrated business functionality. The fixed-source coverage audit is in `migration-coverage.md`; update it as integrated modules earn evidence.

No speed multiplier or full-completion date is inferred from these sources. Remaining live-service, account, signing and physical-device inputs continue to constrain acceptance.
