# Private-home durable journal candidate (inactive)

## Why existing adapters could not be reused unchanged

NativeEnrollmentKeychainStore and ProjectEditSecureStorage use update-then-add and unconditional scoped removal. Those are appropriate for replaceable drafts but could overwrite an unresolved mutation or delete another writer's pending request. This adapter uses the same Apple Security primitives without those semantics.

## Storage and atomicity

- A single generic-password item uses a fixed private-home service and an opaque account key computed from the canonical RegionalSessionStorageScope.service plus account ID. Initialization rejects a namespace mismatch. The canonical scope already binds bundle, endpoint, market and realm. No UI locale-derived namespace.
- The encrypted value data contains a versioned record with namespace, account and full immutable mutation. Data is capped at 8192 bytes and validated on every read. Payload coordinates and labels never enter attributes, logs, analytics, NPC or map APIs.
- kSecAttrAccessibleWhenUnlockedThisDeviceOnly, non-synchronizing, data-protection Keychain; no access group expansion or migration. Metadata includes an opaque random per-record generation tag, never a coordinate-derived digest. The full payload fingerprint stays inside encrypted value data. No readable coordinate or label metadata.
- SecItemAdd is the insert-if-empty operation. Its documented composite primary key rejects a second record at the same service/account. There is no SecItemUpdate and no overwrite fallback. Duplicate insert is accepted only after reading and validating the exact same mutation.
- Clearing first validates the caller's full expected mutation, then uses a single SecItemDelete query with the immutable random generation tag in kSecAttrGeneric. A changed record between read and delete no longer matches and survives. A not-found/mismatched delete is an error, never a successful unlock.
- MainActor journal methods are async. The typed Security primitive is a separate actor, so SecItem calls do not run on MainActor. Actor serialization covers one executor; cross-instance races are handled by the OS unique primary key and conditional attribute deletion, rather than an in-process-only lock.
- The coordinator sets busy before awaiting storage, then rechecks generation/session after every read/save/clear before dispatch or observable mutation. Every dispatch, including an exact retry, rereads the durable journal and requires the same full mutation and owner scope; unavailable, corrupt, missing or replaced storage preserves the in-memory unknown lock and sends no HTTP. Logout during a successful durable insert leaves the lock for future recovery without dispatching HTTP. Logout after receipt/clear cannot repopulate the old UI.

## Platform source verification

Apple documents generic-password primary-key uniqueness and the non-primary generic attribute: [kSecClassGenericPassword](https://developer.apple.com/documentation/security/ksecclassgenericpassword), [duplicate items](https://developer.apple.com/documentation/security/errsecduplicateitem).
Apple documents deletion queries narrowing by supported attributes and blocking execution: [SecItemDelete](https://developer.apple.com/documentation/security/secitemdelete(_:)). [kSecAttrGeneric](https://developer.apple.com/documentation/security/ksecattrgeneric) is a Data-valued generic-password attribute. The conditional-delete design is an inference from those documented query semantics and requires actual Apple integration validation.
Protection and encrypted storage: [unlocked, device-only accessibility](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly), [Keychain items](https://developer.apple.com/documentation/security/keychain-items).

## Evidence and remaining gates

Eight new AppUnit tests use only an actor-backed synthetic vault: exact duplicate/different payload, competing writers, reopened-vault recovery, wrong/full-ID clear, read/delete replacement race, account/realm scope, locked/corrupt storage, and independent random metadata tags. Seven new Core tests cover logout during insert/clear/retry-read, duplicate taps, initial and retry storage failure with zero service calls, missing/replaced durable records (including same-ID changed payload or operation), and stale receipts that cannot clear a newer pending record. The retry-read failure fake represents the same fail-closed error used for locked or corrupt storage; it does not simulate the OS lock state. Existing fixture and Core journal witnesses use the updated full-mutation clear contract.

The original frozen packet source-guard log recorded a failure because a raw `print(` substring check falsely matched `fingerprint(`. The reviewer correction uses a complete-call-identifier guard, adds guard self-tests, and wires the source checks into the existing hosted contract discovery job. Python source guards, Tree-sitter parse and deterministic project checks are local static evidence only. Swift compilation, all XCTest methods and actual Apple Keychain behavior are NOT RUN. No real coordinates, credentials, Keychain operations, backend calls or location prompts were executed. In particular, target-OS attribute return behavior and conditional deletion must be validated in authorized Apple CI/device work before enabling this adapter.

The primitive has no default constructor at composition sites: AppSession remains unchanged and AccountView injection remains nil. This code creates no persistent credentials or access grants; it stores no live data while dormant. Production feature/grant activation, approved endpoint configuration and synchronous session invalidation remain separately gated.
