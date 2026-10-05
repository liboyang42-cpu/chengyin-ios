# Merchant business production assembly

`MerchantBusinessProductionFactory` supplies a separate bounded HTTP mutation transport. It is not a `MerchantBusinessTestTransport`, and does not acquire redemption or refund-execution authority. Default host dependencies still contain no production approval.

## Activation contract

The deployment composition supplies `merchantBusinessApproval`: CN market, exact API origin, account, namespace, reviewed policy version, exact source mutation paths, and typed `MerchantBusinessActionGrant` entries. A grant binds the merchant ID, closed action, exact nested note/tag/correction target and destination operator role. Batch grants bind the exact customer set. AGREE, REJECT and EVIDENCE are distinct actions. Endpoint permission cannot authorize arbitrary bodies: the transport rebuilds and compares exact reviewed URL, query, POST method, credential and JSON bytes including request ID.

The ordinary business reader/coordinator and review sheet now use explicit per-mutation availability, while synthetic labels remain restricted to synthetic examples. Runtime generation covers role/account/epoch/token/origin/market/namespace changes. Production confirmation requires the durable intent store, current access and target equality, optimistic version/assignable-role checks, and another fresh source snapshot after reservation. The coordinator mints a one-shot reservation ticket unavailable to ordinary callers. Confirmation cancellation and session changes are fenced through the final read and at final transport entry, including a deterministic awaited forwarding-barrier test. Public direct-service/reader APIs cannot bypass the reviewed reservation. Mixed synthetic/production composition stays strictly on the synthetic transport. Navigating away invalidates pending work.

The source backend now distinguishes `merchant:aftercare:decide` for AGREE/REJECT and `merchant:aftercare:evidence` for EVIDENCE. The native mutation validates those permissions, backend role rules and fresh `canRespond`/`allowedDecisions`. The older umbrella `respond` bit does not upgrade finance to owner/manager. Financial employees may provide evidence only when the server and exact grant permit it. A merchant opinion response never implies that a refund was executed; payout/refund status remains independently decoded from the server.

Unknown results remain in the file journal across relaunch. No HTTP error proves rollback, no list refresh clears an unresolved write, and no automatic retries replace a request ID. A confirmed typed receipt clears only its own exact intent. The existing separate redemption adapter is unchanged.

## Source proof

Current `ApiMerchantAftercareController` documents `/respond` as appending opinion/evidence without changing audit/payout status. `MerchantAftercareServiceImpl.respond` rechecks merchant/owner binding, exact replay identity and pending platform review before insertion. `requiredPermission`, `requireRoleDecision` and `allowedDecisions` are the authority for the native capability split. Existing Flutter merchant business paths and JSON/query shapes remain the transport contract. No private source files or credentials are copied.

## Verification and remaining gates

Eighteen new non-DEBUG tests use the production factory with an ordinary fake HTTP transport: default off; direct-service bypass blocked; exact merchant/action/target/namespace; finance role cannot decide; actual opinion request/receipt; customer-note CRUD; operator invite; assignable-role revocation; durable-store requirement; decision revocation; same-epoch role change; post-reservation cancellation; final-read cancellation; unknown/relaunch replay prevention, nested grant binding, public-reader bypass, mixed composition and final transport-barrier cancellation. Portable assertions and syntax parsing are supplementary, not compiler or live acceptance. Apple compile/runtime checks, approved deployment, current legal policy review and physical-device/live-business acceptance remain outstanding. This work sends no real opinion, order, refund or notification.
