# Private home: bounded session composition

## Boundary and default state

This local additive patch wires the existing owner-only private-home client into the normal `QuestifyApp → AppSessionContainer → AppSession → SessionRootView → AccountView` path. The shipping `RegionalLaunchConfiguration.composition` remains `.unconfigured`. No live endpoint, real account, provider, backend feature flag, production approval, or OS permission is enabled. The backend is unchanged and its default-off gate remains a separate requirement.

An independently reviewed `PrivateHomeTransportGrant` identifies one exact `RegionalSessionStorageScope`, positive account ID and role. The scope binds native bundle, market, canonical API endpoint and explicit deployment realm. A mismatched grant cannot be attached to a deployment. The transport permits exactly GET, PUT and DELETE at that deployment's `api/native/home` URL, with no query or fragment, only for that current authenticated owner and role. It does not add a generic method/path allowlist or grant home/search, wallet, public map, restore/proof or any other feature. Existing first-slice CN auth and separately granted home/search routes retain their boundaries.

Authentication, remote booleans and role selection do not construct feature grants. Default grant and Keychain primitive inputs are both nil. A future reviewed deployment must explicitly supply its exact grant and the reviewed `PrivateHomeSystemKeychain` primitive. This patch supplies neither in shipping composition.

## Mandatory durable storage and privacy

The factory always constructs the approved `PrivateHomeKeychainJournal`; only its typed primitive is injectable. Production has no plaintext, defaults, in-memory, absent-journal or storage-error fallback. Tests exercise this same adapter with an actor-backed synthetic Keychain primitive. No Security function is executed by those tests. A locked/unreadable journal blocks load before home HTTP; failed persistence blocks mutation dispatch. Existing journal insert-only and conditional-delete rules remain unchanged.

The reviewed wire contract remains owner-derived GET/PUT/DELETE, WGS84 with at most six decimal places, expectedVersion and stable requestId. No coordinates enter telemetry, logs, public mapping, NPC services or caller-supplied owner parameters. Only synthetic coordinates appear in tests.

## Lifecycle

AppSession retains exactly one coordinator per complete `RuntimeDependencyContext`, comparing account, role, session epoch, token, market, endpoint and canonical namespace. Gate mutation and existing synchronous account/token synchronization revoke the prior instance immediately, clear home/review/decision/pending display state, and drop the retained reference. Atomic authentication commit exposes no mixed old-account/new-token private-home context or transport identity. The existing account-refresh routine is now internal so app-hosted tests can exercise same-epoch role changes through the real service path.

The normal root marks the private-home presentation inactive on disappearance and active on reappearance. An offscreen old root cannot reconstruct its coordinator. Immutable deployment/realm replacement must leave the old root; this deactivates its owner without changing or deleting its pending journal. Reentry obtains a fresh coordinator and reloads the durable record for the exact account and namespace. There is no in-place deployment mutation API.

Old coordinator references stay invalidated. Captured full-context predicates and the composition transport fence both success and failure after suspension; a late 401 or matching mutation reply cannot expire or populate a replacement session, or clear its durable unknown record. GET never clears an unknown mutation. Same-owner reentry requires explicit exact retry with the original request bytes; another account or realm cannot read that pending slot.

## Verification and limits

Nine authored app-hosted XCTest cases cover normal-root dependency wiring with a valid synthetic AppSession, stable owner identity, PUT/DELETE and cancel review, valid authentication without a home grant, absent secure storage, locked read/save, logout and retained old references, same-owner exact pending retry, cold recreation, account/realm isolation, same-epoch role refresh, token replacement, root teardown/reentry, suspended 401/success and exact route/method/owner denials.

Executed local checks: 877 Python contracts with 46 explicit optional external-source skips; 92 tooling tests; deterministic project/scaffold verification; supplementary Tree-sitter syntax parsing of five changed Swift files; whitespace diff check. These are source-only evidence.

NOT_RUN: Swift typechecking, SwiftPM, Xcode compilation, app-hosted XCTest, simulator UI interaction, device/Keychain behavior, network/backend acceptance and production enablement. The root mount test is dependency wiring evidence when run, not a tapped UI acceptance flow. An independent review and Apple checks against the final integrated tree are required before acceptance. No remote publication was performed.

## Independent review additions

The independent source review added two app-hosted regression methods (eleven total), each covering four schedules: same-epoch role A→B→A or root disappear/reappear, with a suspended 401 or success reply. GET must not repopulate the invalidated coordinator; a mutation must not clear pending bytes or change an already loaded replacement coordinator. The exact same role, token and epoch are restored intentionally, so the test depends on permanent coordinator invalidation rather than snapshot inequality alone. Replacement recovery still requires explicit exact-byte retry. These authored cases have not run in this Linux workspace; Apple XCTest remains required.
