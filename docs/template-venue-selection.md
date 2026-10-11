# P036 local venue preset selection

## Scope and source

Baseline: `c3a914cd53c0ab60e6d19fc24588d85679dcaa1c`.
Construction authority: MASTER-v10 extracted text, P036 at lines 1616–1619
(`openVenueSheet`, `closePickerSheet`, `onPickerSheetSelect`) and PA02 at line 1998.
The ordinary template editor previously offered only a free-text `usageLocation` field.

Pinned private source contract:
- Commit `f859cd6e2618f618a53f5cd33949259828e86313`.
- [Template actions](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/pages/publish/temp/index.js#L1446-L1482), blob `76e39df5c326aaf029bda8da21562072fb352553`; line 115 defines seven ordered presets. Opening marks the current value, closing changes only presentation state, and choosing writes the exact selected value to `usageLocation`.
- [Template form and picker](https://github.com/liboyang42-cpu/chengyin/blob/f859cd6e2618f618a53f5cd33949259828e86313/chengyinhub-xcx/pages/publish/temp/index.wxml#L1630-L1643), blob `b5d2e240b5b3f74f0c63cbdaae1437dcc729afc1`; the ordinary field is at lines 127–131.

No private source implementation is included in product files. Only the source-defined
seven data values and independently implemented native contracts are added.

## Native behavior

The ordinary editor opens a locally available venue sheet with these source values,
in this order: 景区, 公园绿地, 商圈街区, 古镇老街, 博物馆, 校园, 室内场馆.
English and Chinese labels are presentation only. The existing draft, payload and local
store continue using the exact Chinese value. No dictionary request or read approval
is needed for these fixed presets; the existing dictionary enum still has two kinds.

- Opening, cancelling, swiping the sheet closed and selecting the current preset do
  not mutate the draft. The current preset has a checkmark and selected accessibility trait.
- Nil, empty, custom and whitespace-bearing saved values retain their bytes. Historical
  text is visible verbatim and is replaced only by an explicit preset selection.
- Selection changes only `usageLocation`, synchronizes the existing local coordinator
  with `model.changed()`, and closes that presentation. The existing Save locally action
  persists it; reopen/restore use the unchanged account-bound local store.
- The sheet captures session, draft identity, metadata generation and original draft.
  An additional UTF-8 comparison detects canonically equivalent but byte-different venue
  replacement before the parent change callback. Reload, restore, discard, changed draft,
  leave and reviewed/pending writes revoke old callbacks through existing lifecycle guards.
  Closing is irreversible for that presentation; a fresh opening gets a fresh identity.
- Busy/review/pending/unknown/locked state cannot select. This feature adds no network
  operation, production grant, publishing action, fee, payment or reward action.

## Verification status

Executed in the dot Linux worktree:
- 7 new Python source-contract checks passed.
- 25 existing metadata selector/presentation/UI-acceptance structural checks passed.
- The pinned mini-program's actual open/close/select function bodies ran in an isolated
  Node VM with synthetic local state: 18 cases passed, comprising 11 open/cancel cases
  with zero form writes and 7 exact-value selections. The source Git blob hash was verified
  before execution. This is source behavior evidence, not a native runtime test.
- Tree-sitter `0.26.0` / Swift grammar `0.7.3` parsed all 5 changed Swift files with zero
  recovery nodes. This is supplementary syntax evidence only.
- Patch roundtrip, exact path scope, catalog preservation and source snapshot hashes are
  recorded in the delivery evidence.

Authored, **NOT RUN**: 2 new Core XCTest methods and 7 new app-unit XCTest methods in
existing source files. These cover all seven values, unknown/nil/empty bytes, no-op and
cancel, repeated selection, local save/restore, ownership/session changes, stale drafts,
observed ABA, canonical-equivalent byte replacement, review, busy and unknown outcomes.
No new UI tests, diagnostic profile registration, source identity registration or duration
claims are made. Swift/Xcode, typechecking, XCTest, native UI/simulator, device, accessibility
and live backend checks are **NOT RUN** because this executor has no Apple toolchain.

## Integration boundary

Only eight declared paths change. Existing Swift and catalog files are reused, so no new
PBX source/resource entry is required. PBX, workflow, diagnostic profiles and central
readiness files are untouched. `tools/run138_editor_readiness_contract.json` contains a
byte/hash-bound `App/TemplateAuthoringView.swift` snapshot. The delivery manifest supplies
that file's exact before/after bytes and hashes plus the one-line hook patch; the parent
integrator must reconcile the central source identity before the relevant aggregate gate.
No aggregate pass, Apple execution, push, deployment or full P036 parity is claimed.
