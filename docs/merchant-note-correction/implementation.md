# Merchant customer-note correction presentation

This increment clarifies the existing append-correction workflow. The draft identifies new-note versus correction mode, the exact customer target, corrected note ID, and a read-only description from the matching note in the current customer snapshot. The frozen review repeats the description using its own captured baseline; existing target and request fields continue to display the exact customer and corrected note ID. The summary accepts only NOTE / NOTE_CORRECTION rows with that note ID under that customer query. Missing or blank descriptions are omitted rather than invented.

The correction draft starts empty. The original description is never assigned to the editable content. Append-only copy states that a correction creates a new record and preserves the original. The mutation title distinguishes a correction from a new note.

The dedicated Cancel correction action opens an explicit discard dialog. Keep correcting, system dialog cancellation and dismissal do not mutate the text or target. Only Clear text and cancel correction clears the local text/error and changes the local draft to new-note mode; its correction controls then disappear. Empty content still fails existing review validation. Cancellation calls no request, review preparation, reader, journal, or service. The separate existing editor-dismiss toolbar behavior is unchanged.

## Source evidence

Read-only connector verification against `liboyang42-cpu/chengyin` at `ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/merchant/customer/detail/index.wxml`, blob `220d3c0ea70cff5dd2e615113945b3f3e8fd35c5`, line 118 and surrounding editor/history controls: identifies the corrected note and explicitly says corrections append rather than modify the original.
- `chengyinhub-xcx/pages/merchant/customer/detail/index.js`, blob `ba72ce2e8a1617803fa9ebfb31b7782a000d9e7e`, `startCorrection`, `cancelCorrection`, and `submitNote`: correction starts with empty content, cancellation clears local correction/content, and submission appends through the existing notes route with `correctsNoteId`. The native discard confirmation is a deliberate protection for typed text.

No private source implementation was copied into the native project.

## Scope and integration

Exact input tree: `eedfde666641e90b0bfd6c3c893c1e5ca180c539`, the frozen CRM datepicker result. Only two existing product paths change: `App/MerchantBusinessEditor.swift` and the `titleKey` switch in `Core/MerchantBusinessMutation.swift`. Request generation, validation, permissions, targetKey, review authority, production gates, idempotency and unknown-outcome handling remain unchanged. The customer-page host, existing datepicker packet, AppSession, shared catalog/project, and UI methods/budgets are untouched.

Apply the supplied existing-file hunks, preserving other authors' additions; do not replace shared files wholesale. Merge all seven exact bilingual fragment entries into the shared catalog during authorized integration. The fragment is intentionally not merged here. No new app Swift file is added. The new Core XCTest file is discovered by SwiftPM; central project regeneration is needed before Xcode-based test integration.

## Verification

Passed: five focused Python contracts, three supplementary Swift Tree-sitter parses, and 32 existing native regression checks. One optional private-source regression check is skipped; the separate legacy Flutter source-path check is not run because that checkout is absent. The selected broader run also reports 25 inherited access-lifetime setup errors: its fixed source hash does not recognize the already-accumulated MerchantBusinessViews.swift baseline. The same 25 errors are reproduced against exact input-tree bytes, and both implicated product files are unchanged. No inherited tests or guards were weakened.

Five Core XCTest methods are authored but unrun. No Swift or Xcode toolchain is available here. Swift typechecking, Apple compilation, Core runtime, simulator/UI/accessibility, aggregate and live acceptance are not established by the source checks. The packet includes pre/post hashes, protected-file verification, whitespace checking, and exact-base replay evidence. No remote write, commit, publish, backend save or credential access occurred.
