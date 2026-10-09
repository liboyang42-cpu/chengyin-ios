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
