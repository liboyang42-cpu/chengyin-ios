# Creator line 1: explicit questionnaire deletion

## Provenance and scope

This is **new reconstruction on 2026-10-10**, not a recovery of the missing October 9 work and not evidence that earlier work was completed.

- Exact base: `34928c87f43a6b97bfc0b01f8bcc8dba0d9b1631`
- Source checkout: the separately cloned `line1` worktree; the `native` baseline is unchanged.
- Sole master: `MASTER-v10-extracted-text.txt`, SHA-256 `02f7f9e3a829d474acc5f0cd8159dcbeec7711107c34a515b97a15bdf938afb2`.
- Relevant master context: P039/P040, lines 1565–1572 (existing App creator publishing/editor routes, PA02); W18/S20, lines 861–868 (reuse App authoring and existing publication contracts). These passages do not independently specify a new server deletion API. The one-question/two-option and owner/lifecycle requirements are this task's explicit acceptance criteria.

Inspection found `TemplatePreferenceDraftEditor` already supports local raw JSON, an explicitly installed example, bounded validation and stale-result fences, but provides no explicit per-question/per-option removal review. Project initial-attribute editing already exists separately. This patch closes the questionnaire deletion gap without replacing that existing attribute editor.

## Behavior

The existing local preference editor now opens a named removal sheet. It parses only on explicit opening. The sheet displays ordinary `steps` questions and options from the current source, preserves at least one question and at least two options per question, and requires a separate destructive confirmation. Cancel, Close and dismissal leave the source unchanged. Only the confirmed item plus one adjacent array separator is removed. Removing a question also removes its contained options and fields.

Every surviving token remains byte-for-byte unchanged: unknown root and surviving-row fields, result bodies, tiebreak configuration, escaped strings, canonical-distinct keys, precise numbers and formatting outside the removed span. No source re-encoding, schema migration, dependency repair or result recomputation is performed. Tiebreak removal is outside this slice. Deletion is structural, not a claim of valid scoring or reachable results; the UI tells the author to run the existing JSON check again, whose cached result becomes stale after the source changes.

Malformed JSON, duplicate decoded keys, unsupported shapes, excessive depth/nodes/bytes and bounded UI projection limits fail closed without changing the source. Limits are local editing-safety limits, not new server schema requirements: 1 MiB, depth 64, 20,000 parsed nodes, 128 steps, 64 options per question, 512 total projected options.

Each presentation captures the controller/lifecycle generation, the existing model editor generation, account/namespace/epoch/authorization revision, draft identity and exact source bytes. Confirm and Cancel bind to the exact current review ID and presentation ID. Model load/restore/discard/leave, source edits, method changes, loss of editability and account changes reject stale work. Old dismissal cannot close a reopened presentation; duplicate confirmation cannot delete twice. The mutation uses the existing `model.changed()` path and existing optional local save behavior.

## Exact change allowlist

1. `App/TemplatePreferenceDraftEditor.swift` (one mount)
2. `App/TemplatePreferenceRemovalController.swift`
3. `App/TemplatePreferenceRemovalPanel.swift`
4. `Core/TemplatePreferenceRemoval.swift`
5. `Resources/TemplatePreferenceRemoval.xcstrings`
6. `Tests/CoreTests/TemplatePreferenceRemovalTests.swift`
7. `Tests/AppUnitTests/TemplatePreferenceRemovalLifecycleTests.swift`
8. `Tests/ContractChecks/test_template_preference_removal.py`
9. `docs/reconstruction-20261010-line1.md`

No AppSession, PBX project, central locale catalog, transport, endpoint, production capability, signing or deployment files are changed. No upload or publication was attempted. Preference remains local-only and the existing remote contract continues to reject it.

## Verification and limits

- Executed: 18 preference Python source-contract tests passed, including 12 new deletion contracts and 6 existing preference contracts.
- Executed: 49 adjacent native-local source contracts passed; 10 source-parity checks skipped because the external Flutter checkout is unavailable. A first invocation had a Python import-path error; the corrected invocation used `PYTHONPATH=Tests/ContractChecks`. Both logs are retained.
- Authored but **not executed**: 10 Core XCTest methods and 12 app-hosted lifecycle XCTest methods. They cover first/middle/last removal, minimums, duplicate/escaped keys, exact source preservation, Unicode normalization, budgets, cancellation, duplicate confirmation, stale dismissal, reload/restore/discard/leave, source and owner ABA, owner/epoch/role/namespace/logout, hidden/existing-template guards, concurrent reviews and continued remote blocking.
- Swift and xcodebuild availability were actually probed: both commands returned exit 127 (`command not found`). There was **no Swift typecheck, compilation, XCTest execution, simulator/device run, UI screenshot, accessibility or live-backend verification**.
- Initial optional Tree-sitter preflight returned exit 2 because the pinned parser dependencies are missing. It is not a compiler result.
- Final patch replay, source hashes, whitespace checks and isolated project-generation/scaffold outcomes are recorded in the separate delivery manifest and logs. Those checks do not establish Swift correctness.

## Integration and Apple follow-through

The patch intentionally does not edit the PBX file. The main integrator must run the repository's existing `python3 tools/generate_project.py` after applying all line patches, then `python3 tools/check_scaffold.py`, so the new App/Core/test files and independent catalog are included exactly once. Any isolated generation preview in this packet is evidence of the generator's discovery only; it is not an integrated app build.

On the approved Apple toolchain, run the Core removal tests and the app-hosted removal lifecycle tests, then compile the app and exercise the actual sheet: cancel, close/swipe dismissal, repeated remove taps, first/middle/last options, last-question/two-option disabled states, JSON edit/replace/reopen, leaving the editor, owner changes, English/Chinese, large text and VoiceOver. Re-run JSON validation after removal and verify local save/reopen retains exact surviving data. Real publication remains outside this work.
