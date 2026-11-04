# Native text draft recovery package

This branch preserves previously unsubmitted source as a **reviewable patch only**. It does not change runtime App/Core files, the Xcode project, localization, permissions or workflows.

- Exact patch base: `eec839502b11f1119a6ede212c768bb3f2de4f29` (`integration/launch-20261204`).
- Base tree: `8ae00bce7fddf29de634080c95c87d5a761c81c0`.
- Recovered original work was based on public commit `bcd754bd41dd41b3dad22a436211cd89ee47b657`.
- Patch SHA-256: `d7fb32ddaa4bc52d7c8a6063e59c2d2076ab470490bcb2d2ae985f143a83dd72`.
- Nine new source/test/document files are preserved byte-for-byte. Nine existing files receive only the necessary current-base integration changes inside the patch.

## Why a patch, not direct integration

The app entry, project and string catalog have concurrent public UI work. Replacing their older full-file versions would discard newer changes. This package keeps all existing project objects and translations, adding only six file/build registrations and 28 `nativeText.*` keys. It retains every newer fixture route and test.

The patch is tied to the exact base above. The owner of the current shared files must reconcile it if those files move. Do not overwrite current files with the old recovered working tree, and do not use this package to enable a production writer.

## Exact scope

New files:
- `App/NativeTextDraftEditorView.swift`
- `App/NativeTextDraftEntryView.swift`
- `App/NativeTextDraftFixtureHost.swift`
- `Core/NativeTextDraftEditor.swift`
- `Core/NativeTextDraftPayload.swift`
- `Tests/AppUITests/NativeTextDraftEditorFlowTests.swift`
- `Tests/ContractChecks/test_native_text_draft_editor.py`
- `Tests/CoreTests/NativeTextDraftEditorTests.swift`
- `docs/versioned-content-drafts/native-text-editor.md`

Necessary existing-file edits:
- `App/OwnerDraftBrowserView.swift`: create/open links for this explicit native schema.
- `App/OwnerDraftFixtureHost.swift`: synthetic native-text fixture payload only.
- `App/QuestifyApp.swift`: DEBUG recorder route and startup isolation condition only.
- `Core/OwnerDraftBrowser.swift`: validated native selection projection only.
- `Core/VersionedContentDraftContracts.swift`: exact JSON codec hooks, retaining the existing AST equality check.
- `Questify.xcodeproj/project.pbxproj`: six source/build records and target memberships only; Core XCTest stays auto-discovered by SwiftPM.
- `Resources/Localizable.xcstrings`: 28 nativeText keys only; every existing value is unchanged.
- `Tests/AppUITests/OwnerDraftBrowserFlowTests.swift`: two original native navigation cases appended, retaining newer cases.
- `docs/versioned-content-drafts/contract.md`: original native-format scope note.

## Verification and limits

63 bounded source/integrity/packaging checks passed. The entire 18-path patch was replayed and reversed against the exact public preimages with byte-identical results. Six existing offline Python source tests passed against a reconstructed sparse overlay. The preserved Core coordinator/service/JSON/journal dependencies need no replacement.

**Not run:** Swift compilation, 18 authored Core XCTest methods, four editor UI tests, two owner navigation UI tests, Xcode/App execution, server calls or CI. Static checks do not establish runtime correctness.

The normal editor factory remains `nil`: a normal account sees the unavailable state. Production service approval and secure journal injection are not supplied by this recovery. Only the existing DEBUG in-process recorder exercises saves. The new schema does not convert legacy or installed content and does not publish content.

No account data, credentials or backend response dumps are intentionally included. A bounded credential/reference scan found no matches; a full secret scanner was not available.

## Reviewer application

In a separate working tree at the exact base, inspect `SOURCE-MANIFEST.json`, then run:

```sh
git apply --check docs/recovery/native-text-draft-20261104/restore.patch
```

Apply only after coordinating the shared-file ownership. This recovery branch creates no PR and dispatches no workflow.
