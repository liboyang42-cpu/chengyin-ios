# P107 native unsaved-profile exit protection

## Basis and boundary

Reviewed v2 leaf base: `c3a914cd53c0ab60e6d19fc24588d85679dcaa1c`.
This isolated PBX/catalog integration uses true parent
`3cbc7d4504911aaa02819f31ad955e7e74c54672` (tree
`dd896152186440ad6b7ad12f993b31f40992ded5`).
The construction document is MASTER v10, P107/PA01 (profile editor, exitPage,
per-field editing, return, account cleanup) and the interrupted/repeated-flow
acceptance requirements. PA01 asks for return and account-cleanup acceptance;
it does not explicitly require an exit-discard dialog.

Read-only Mini evidence is fixed to `f859cd6e2618f618a53f5cd33949259828e86313`,
`chengyinhub-xcx/pages/gerenziliao/gerenziliao.js`, blob
`503d31aae4cecc9197a0987926711f8aed51e491`. Its nickname and introduction
editors use temporary values and explicit confirm/cancel. Its `exitPage`
navigates directly back, or to the member tab when no prior page exists.
The Mini does **not** implement this whole-page discard dialog. This increment
is an explicitly scoped native safety improvement, not a claim that Mini
already protects whole-page exit. Private source bytes are not included here.

## Implemented leaf

- Existing Account → ProfileEditView route keeps its destination and save flow.
  Back uses a local decision; a clean editor can exit immediately once.
- Dirty nickname/introduction are compared as UTF-8 bytes, so whitespace and
  canonically equivalent Unicode changes are preserved. Nil route preferences
  retain the wire value; explicit clear/reorder and a staged avatar are dirty.
- Cancel changes no draft, snapshot, upload receipt, read count, or write count.
  Confirm consumes a single review before dismissing and discards only local
  draft state. It neither saves nor retries.
- Review is tied to the editor instance, account/epoch, viewer revision,
  generation, model/context revision, exact draft/snapshot, and pending-write
  lock state. New edits including ABA, refresh, save review, background,
  departure, and session changes retire or invalidate stale decisions.
- Concurrent profile operations, save/reload reviews, and avatar presentation
  block a competing explicit Back action. A settled unknown save can still
  leave; the existing coordinator's pending-write lock survives.
- Committed exit retires avatar ownership and refuses queued model load,
  reload, prepare, save, and reset operations permanently for that model.
  Reset also checks task cancellation before changing any local state. A real
  navigation reopening uses a new model while retaining the shared coordinator
  and its pending-write locks; a delayed session task cannot reopen the old model.
- The native back button is replaced with a labeled, accessible Back button.
  Dirty/busy modal interactive dismissal is disabled. Actual edge-swipe and
  sheet behavior require Apple/device acceptance; static source cannot prove it.

No new service endpoint, capability, credential, persistence, or production
activation is introduced. The already-existing reload and save paths remain
separate. This is not restoration of any lost historical 14-file increment.

## Allowed paths

1. `App/ProfileEditView.swift`
2. `Tests/AppUnitTests/ProfileExitDiscardTests.swift`
3. `Tests/ContractChecks/test_profile_exit_discard.py`
4. `Resources/ProfileExitDiscardLocalizations.fragment.json`
5. `docs/profile-exit-discard.md`
6. `Questify.xcodeproj/project.pbxproj`
7. `Resources/Localizable.xcstrings`

The four executable/test/fragment leaves match the accepted v2 bytes. The
fixed parent generator registers ProfileExitDiscardTests exactly once in
QuestifyAppUnitTests, which is hosted by Questify. All 27 authored methods are
unfiltered in that target. The three fragment rows are merged verbatim into
the catalog for en and zh-Hans, preserving every existing row/root field.
The previous 19-path/projection packages, other feature leaves, central
readiness/diagnostic selectors, and workflows are unchanged.

## Acceptance and status

- Focused source contract command:
  `python3 -m unittest discover -s Tests/ContractChecks -p test_profile_exit_discard.py -v`
- 27 authored app-hosted model tests include byte-preserving cancel, exact
  confirmation consumption, Unicode/whitespace, preference-only edits,
  cross-editor/account/epoch/viewer rejection, snapshot change, dirty ABA,
  save/reload competition, interrupted reads, unknown-write lock retention,
  queued actions after exit, queued and cancelled reset, a new-model reopen,
  old-model reset rejection while the reopened editor has a save review,
  unavailable reads, and staged-avatar exit.
- The private JS proof executes the real Mini page with fake navigation and
  capture-only transport. It proves source behavior, not native implementation.
- The private evidence directory binds patch/afterimage SHA-256 values,
  baseline SHA, targeted command logs, protected-path comparison, and mutation
  checks to this exact candidate. No full-suite result is claimed.
- Apple: NOT_RUN. This executor has neither Swift nor Xcode; authored Swift
  tests are not executed tests, and static checks are not compilation.

### PENDING_PARENT_INTEGRATION

PBX registration and the three bilingual catalog entries are complete in this
isolated exact-3cbc candidate. The unchanged parent generator and its complete
input path/hash set are recorded with the integration evidence; schemes remain
byte-identical. This does not integrate any other creator/club PBX candidate.
When those separately reviewed source additions are combined, regenerate the
project once from the final unified source inventory. Do not overwrite one
candidate's project file with another's.

Existing historical exact-source/admission readers and central selection
require a separately reviewed final-parent integration step. They are unchanged
here; the old reload contract still has its five inherited failures. Apple:
NOT_RUN. Registration is not Swift compilation, app-hosted test execution,
UI/device acceptance, or a full-CI pass.

After integration, run the 27 tests plus affected ProfileEditRefresh,
ProfileReloadDiscard, and ProfileAvatarPresentation tests. Build the app and
verify ordinary Account entry, clean Back, dirty Back/Cancel/Confirm, edge
swipe, modal swipe, preference/preview sheets, VoiceOver, large type,
English/Chinese, background, logout/account/role changes, failed refresh and
unknown-save recovery. Do not infer production endpoint readiness from this.
