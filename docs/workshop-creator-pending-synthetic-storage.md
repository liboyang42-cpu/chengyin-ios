# Creator-pending synthetic recovery storage

## Evidence and scope

CI138, commit `4bf6667f8c5d9d2d59a8063d7d54eaef7a338865`, tree
`82e9abd1afa6180815ef7ea5ea314d6eb692e036`, failed UI60 before the author
form existed. Its accessibility dump contained `workshopPending.issue` with
the local recovery-storage error. The synthetic harness supplied an in-memory
token vault but creator recovery still used `TemplateAuthoringSecureStorage`.
The retained job evidence does not identify an OSStatus or entitlement cause.
UI60 retained no screenshot files, so there is no pixel-based diagnosis.

Evidence: [CI138 UI60](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/37792301124/job/113373676696).

## Narrow composition change

- `AppScopedStorageFactory` adds a DEBUG-only optional
  `syntheticWorkshopCreatorPendingRecoveryStorage`, defaulting to `nil`.
- `AppSession` selects that explicit override only for the three recovery-store
  constructions inside `makeWorkshopCreatorPendingController`: author recovery,
  declaration history, and the nested declaration controller. Without an
  override, including Release, it returns the existing system secure storage.
- Each `WorkshopCreatorPendingFixtureHarness` retains one existing DEBUG
  `TemplateAuthoringMemoryStorage` and injects it before constructing its session.
  Back, controller invalidation, and reopen preserve that instance and its bytes.
  Only the harness's explicit `clean()` removes its values.

The selection happens before any system-storage access. There is no recovery
from a failed Keychain operation by switching to memory. Standalone creator
consent, template authoring, and all unrelated storage wiring are unchanged.
No production grants, network clients, credentials, permissions, or entitlements
are added.

## Regression coverage

`Tests/AppUnitTests/WorkshopCreatorPendingSyntheticStorageTests.swift` adds
eleven authored cases using the unchanged real controllers and stores:

- Nil default and empty-store initial load
- Author, unchecked declaration review, Back, and reopen
- Fresh-controller recovery and explicit byte-identical retry after unknown outcome
- Failed author and nested-declaration writes suppress dispatch
- Nested declaration history survives reconstruction with read-only approval
- Malformed/noncanonical author bytes and foreign owner/source fail closed
- Malformed declaration history fails before further requests
- Separate harness values and harness-local cleanup

`Tests/ContractChecks/test_workshop_creator_pending_synthetic_storage.py`
checks DEBUG exclusion, system fallback, the exact three-store scope, harness
lifetime, existing fail-closed/readback conditions, and project registration.
The standard `tools/generate_project.py` registers the new AppUnit source.

Existing Core controller/store code, `TemplateAuthoringSecureStorage`, UI test
methods and helpers, workflow, shard membership, wait/swipe budgets, and real
protected-storage tests remain unchanged. The original canonical-byte,
owner/source, exact readback, immutable retry, and explicit acknowledgment
requirements still apply to the memory backing store.

## Verification boundary

Python contracts and supplementary Swift syntax parsing are local source checks.
The new AppUnit cases require Apple compilation and execution. UI60 and the
existing creator-pending AppUnit flows must be rerun on the exact integrated
commit before reporting them passed.

The existing historical guard
`CreatorPendingBudgetTests.test_all_original_ui_files_and_complete_helpers_are_byte_exact`
pins the pre-change `App/WorkshopCreatorPendingFixtureSupport.swift` bytes.
It initially rejected this reviewed fixture change. The separately approved
`tools/tests/creator_pending_synthetic_storage_history.py` adapter binds complete
pre/post SHA-256 values for all three changed App files and verifies a stored
complete FixtureSupport preimage. It uses fixed, exact raw-byte inverse deltas
to reconstruct that file before the original `a7fe8e68…` hash assertion executes.
The original historical hash and all runtime budgets remain unchanged.

`tools/tests/test_creator_pending_synthetic_storage_history.py` separately tests
missing, duplicated, moved, unrelated, mixed-state, and CRLF mutations, plus
enabled-by-default overrides, replaced production fallbacks, and damaged or
missing preimages. This projection proves preservation of the historical
fixture bytes only. Current DEBUG exclusion, storage lifetime, and fail-closed
behavior have their own contracts and authored AppUnit cases above.

This fixture does not establish real Keychain or physical-device behavior.
`PrivateHomeSystemKeychainTests`, `ContentDraftSystemStorageTests`,
`PlayRecoverySystemStorageTests`, and `PlayRecoveryDeviceStorageAcceptanceTests`
remain separate, unchanged acceptance gates. They also do not establish the
exact template storage adapter's behavior in the UI-test app process.


## Exact later App evolution admission (2026-10-10)

The historical gate also validates AppCompositionRoot and AppSession as part of
its complete three-file bundle. Reviewed project node-image wiring and the
project metadata category reader evolved those two files after the storage
change. The fixture remained byte-identical to its reviewed storage postimage.
The older adapter therefore rejected the integrated bundle; its 14 negative
controls also failed in setup because they treated current App bytes as the old
storage postimage. This is a historical projection failure, not evidence of a
current storage failure.

The adapter now admits exactly three complete bundle states: the original,
the reviewed storage-only change, and the reviewed integrated App evolution.
Its original six before/after SHA-256 anchors, original fixture inverse,
FixtureSupport preimage, historical budget gate, inventory and budgets are
unchanged. The additional state requires all three current file identities
together. It cannot admit independently mixed generations.

The complete historical App files come from the delivered
`Native-iOS-Local-Validated-d09c-Full-Source-20261008.zip`, SHA-256
`684c097c212c708296ffb431f0719eece3a291a9c81b60459e834819b4106de2`.
Its frozen source manifest has SHA-256
`7f7256b6ae18eeac9573185a54621e986a9f332fdb8307d049fbab2cf49f9abe`
and binds all three storage postimages to the adapter's existing hashes.
The two new complete App preimages are reconstructed from those delivered
postimages using the already reviewed storage deltas and must match the
existing original hashes `2c1d8708…` and `e2f082a2…`. No historical App bytes
are inferred from a current digest.

The hash-bound `reviewed-evolution.json` records the complete old/current file
identities and nine exact raw-byte regions: three AppCompositionRoot regions,
five AppSession project node-image regions, and one AppSession category-reader
region. The integrated source is commit
`3a94b2c32a89acb6b0da981bfe9f407b2476f2f4`, tree
`6b43dc7a42586de04cff8c1cb6b5bc078fd0e83d`. For this complete bundle only,
the adapter reverses those exact bounded regions, requires the unchanged old
storage postimage hashes, then reverses the original storage deltas and compares
every complete result to its original-SHA-bound preimage. Tests reconstruct
both forward stages byte-for-byte as well. No production source is rewritten,
and no result is cached across reads. The two original accepted bundle states
retain the exact old input domain: they require only their three bound App
sources and the existing FixtureSupport preimage. Missing or corrupt later
manifest/App-preimage files cannot reject an otherwise valid legacy bundle.
Only the evolved state requires those additional evidence inputs.

The historical controls now retain all 14 existing cases and add coverage for
all 15 distinct invalid three-generation bundles; missing, duplicated, moved
and partially inverted evolution regions; every complete preimage and manifest;
legacy minimal-root acceptance despite missing/corrupt later evidence; current
nil/secure-storage and CRLF mutations; read-only projection; and later
mutations after a successful read. Current creator storage behavior remains
covered separately by the unchanged consent, observation, pending and synthetic
storage source contracts. These checks do not replace Apple compilation,
AppUnit/UI execution, physical-device or real Keychain acceptance.
