# Normal Play durable recovery prerequisite

Reconstructed against public base `bcd754bd41dd41b3dad22a436211cd89ee47b657` after workspace loss. Previous patch hashes/review outcomes do not cover these new bytes. Fresh independent review and Apple execution are required. This is a bounded normal-App pause/completion prerequisite, not gameplay write enablement or full W01–W20 acceptance. All grants remain default-off.

## Boundary

Async snapshot protocols replace blind synchronous writes. Token-free intent retains exact necessary evidence, action ID/version, route-session identity, original epoch and exact namespace/account/role. AES-GCM immutable random-name files reuse the unchanged reviewed ContentDraft OS primitives: device-only unlocked Keychain CAS, complete-protection owner-only files, no-follow descriptor traversal, exclusive creation and durability barriers. A permanent presence marker distinguishes lost Keychain state from a fresh slot.

Every update reserves its generation before file I/O. Missing, partial, corrupt or foreign state stays locked; a fully authenticated staged generation may finish. Clear commits its tombstone before deleting a blob and retains an empty anchor. No automatic reset, scan, eviction, old-generation fallback, or memory fallback exists.

A one-shot fileprivate dispatch attempt rechecks exact storage generation and current owner immediately before transport. Only the fixed factory's endpoint-bound OS seal can authorize network-capable transports. The factory validates typed RegionalConfiguration and RegionalSessionStorageScope, exact session namespace and endpoint before constructing storage. Raw mutators and the shared request helper cannot evade protection by declaring a read capability or using dot/semicolon/encoded/path aliases. A final synthetic byte-script recorder contains no network, callback or delegated transport.

The coordinator owns child Tasks and retires attempts/cancels tasks on invalidation. Cancellation never proves the server did not execute. A branch retry requires fresh authoritative readback and preserves action/version/payload and deterministic multipart boundary; generic business rejections (including 400/403/409/500) retain uncertainty. No definitive-no-commit semantics were verified for those envelopes. Classic completion has no blind retry. Atomic pause record/tombstone/pendingRemote state and the retained restore lease prevent stale viewers from overwriting a newer operation. Unknown pause/end blocks new run mutations until matching authoritative readback.

## AppSession installation seam

The shared AppSession file remains untouched for separate integration. In `playExperience(for:)`, obtain the current authenticated session from the existing reviewed selector/stable issuance path and include authoritative effective role using `PlayExperienceSession(..., role:)`. Construct `try PlayRecoveryComposition.make(session: captured, scope: scope, regionalConfiguration: regional, storageScope: storageScope)`, inject the same result into `recovery:` and `pausedStorage:`, and remove the two shared memory properties. Construction failure remains unavailable; never fall back to memory. No storage I/O occurs at construction.

Retain the computed live-selector snapshot projection, early thoughtClaims guard, all per-action gates, read-only `restoreRun` storage gate, and GET/query ending contract. Host invalidation must occur for every account/epoch/role/token/realm transition, including intermediate A→B→A; a new issuance cannot reuse an old coordinator. Preserve unrelated read-bridge behavior. All write capabilities remain off. Regenerate the project after integration.

## Remaining acceptance limits

- Fresh independent review, AppSession seam installation and exact-tree Apple checks are still required. Swift/Xcode, Core XCTest, simulator Keychain/filesystem probes, device lock/unlock and real power-loss behavior are NOT RUN in this Linux authoring environment.
- OS tests use only unique synthetic Keychain services and scoped temp roots. Factory mismatch tests reject before OS construction. The API-boundary tool typechecks a positive control before inaccessible-constructor/immutable-request negatives, without executing fixtures.
- A crash after replacement commit but before prior-blob cleanup can leave an unreachable encrypted orphan. No retention/cleanup scan is implemented. Evidence is bounded to a 256 KiB encrypted blob; rewards, story history and credentials are not saved.
- The journal trusts OS Keychain integrity. Restoring an older valid anchor together with a surviving matching encrypted orphan, or rolling back/removing both Keychain and filesystem state, is outside the local threat model. This is not an external monotonic ledger, and complete rollback detection is not claimed.
- Hints, leader/thought/advanced/player/circle/preference/tag and prefab-specific write journals remain separate acceptance work with grants off. Raw prefab completion fails closed for network-capable transports until its own reviewed boundary exists. Synthetic fixtures retain their non-network recorder.
- No backend endpoint, provider or grant is invented or activated. Full-game exactly-once execution is not claimed.

Static Python contracts, project generation and supplementary parsing are distinct from compiled/executed Apple evidence. The packet includes interrupted prepare/dispatch/clear, CAS/ABA, cross-owner isolation, ciphertext rollback, restart/exact retry, unknown rejection, raw helper aliases, stale paused viewers, lifetime retirement and cancellation tests.

## Fresh independent source review

The reconstructed packet received a new independent source review, rather than inheriting the lost packet's result. Review corrections preserve scripted leader actions and preference-ending readback in the sealed fixture, replace a vacuous late-401 assertion with an actual callback plus current-session positive control, and add final-generation replacement and live-selector dispatch probes. The OS storage primitives, AppSession, approval issuance and grants are unchanged.

This is suitable to publish as a dormant source prerequisite, subject to exact-tree Apple compilation and tests. It does not install normal-App exit/relaunch recovery. The next separate AppSession unit must inject one scoped durable object into both protocols using the existing current-selector/issuance lease and authoritative effective role. Its synthetic composition tests must not read the fixed production Keychain service or storage root: construction is I/O-free, but coordinator `load()` invokes recovery reads.
