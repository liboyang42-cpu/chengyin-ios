# L4 free explore: frozen-contract reservation recovery

Status: source implementation and test source ready for integration review. Not an end-to-end completion claim. Cancellation remains blocked by the frozen backend contract; native typecheck, XCTest, live staging and normal-entry verification have not run.

## Scope and bases

- Public destination: `liboyang42-cpu/chengyin-ios`, issue #130.
- iOS base: `0a56746aca42158dda20c821a1d50f089f0d5ae8` (`integration/launch-20261204` at inspection).
- Branch: `codex/l4-free-explore-recovery-20261104`.
- Backend adapter baseline stays **`58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`** in public `hengyin`.
- Local preloaded backend HEAD `c6eac3b8cebf7311e8f00f208d294c3c8212aaec` was inspected only as a labelled difference reference. No backend files, refs, switches or data were changed.
- Exclusive files: four `Core/FreeExploreLaunch*.swift`, three `Tests/CoreTests/FreeExploreLaunch*Tests.swift`, this document and `docs/app-composition/l4-free-explore.diff`.

Issue #130 had no assignees or comments when checked. Existing L4 order-readback and registration-supplemental branches were identified; no existing free-explore branch or baseline `Core/FreeExplore*` file was found. No issue claim or external comment was published under this task's upload-only authorization. No other lane's files were changed.

## Source-backed contract

The authority is the controller and service at the frozen SHA:

- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiFreeExploreBundleController.java`
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/FreeExploreBundleServiceImpl.java`
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/FreeExploreBundlePolicy.java`
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/ExploreBundle{Order,Unit,Reservation}.java`

| Frozen route under `/api/free-explore/bundle` | Adapter behavior |
| --- | --- |
| `GET /catalog?topicId=...` | Checks requested topic, product type 2 and catalog identity; reads only. |
| `GET /order?registrationId=...` | Checks the original registration and every decoded ledger owner, unit and reservation. A null bundle remains read-only. |
| `POST /reservation` | JSON contains only `registrationId`, `unitId`, `offerId`, `startAt` in epoch milliseconds and the original `idempotencyKey`. Defaults off locally and still depends on the server switch. |
| `GET /reservation/receipt?idempotencyKey=...` | Reads the original key. Checks owner, registration, unit, offer and SHA-256 fingerprint including the exact original millisecond timestamp. A null receipt stays unknown. |
| `GET /order/refund-quote?registrationId=...` | Displays server route, amount, total, remaining value, ratio, reason, policy version and after-sales flag. No local threshold or amount arithmetic, no refund submission. |
| `POST /reservation/{reservationId}/cancel` | Exists on the frozen server with `useWaiver` only. **Not dispatched by this implementation**, because the required quote/confirmed-outcome contract is absent. |

Responses use `AjaxResult` (`code`, optional `businessCode`, `data`). Java Longs decode directly as `Int64` or canonical decimal strings, never via Double. Date strings remain server display values. Unknown unit/reservation status strings remain readable and never grant write permission. An unknown refund route remains a server display value, without a client execution mapping.

### Mini-program check and cancellation blocker

At frozen `58f4cc4`, `chengyinhub-xcx/subpackageMember/free-explore/` and `chengyinhub-xcx/utils/free-explore-bundle.js` do not exist. The similarly named play tests do not define the bundle reservation contract. Their absence was checked using `git ls-tree` on the frozen tree.

At **difference-only** `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`, those page/helper files exist and use `GET /reservation/{id}/cancel-quote` followed by cancel with a server `expectedOutcome`. The controller diff confirms both were added after the frozen baseline. This is evidence of a version gap, not authorization to upgrade or call those routes.

Exact blocked action: obtaining a server cancellation quote/confirmed outcome against backend `58f4cc4`, and consequently submitting the requested quote-confirmed cancellation flow. Reason: no such quote route or `expectedOutcome` contract exists there. This is a source-contract blocker, not a tool denial or pending remote operation. No cancel request was sent. The frozen cancel route has no independent request receipt/idempotency key; after any separately authorized cancel attempt, recovery must read the original reservation and original order and must not automatically repeat cancel. `prepareCancellation` and the service's `cancellationQuote` report `cancellationQuoteUnavailable` without HTTP. Do not replace this with a client clock/12-hour or waiver-month calculation.

## Implemented recovery behavior

1. Read the owned original order and catalog. Match the unit chapter and chosen offer. Only the exact known `AVAILABLE` unit state can start a new reservation; server validation remains authoritative for payment, availability, time windows and supply.
2. Persist the complete original command and read it back synchronously before POST. The store key binds exact base URL, market, deployment namespace and account. Token/epoch changes do not discard recovery; a different account or deployment cannot load it. No credential or redemption code is persisted.
3. A pending command blocks a new operation, including another order. A transport/decode/write-result error keeps the command unknown.
4. On restart, read the original reservation receipt, then the same owned order. Clear the record only when that order contains the matching reservation and fingerprint. A successful POST alone never clears it. Null receipts, read failures, foreign receipts, storage corruption and failed removal retain the lock or fail closed.
5. An explicit retry first reads the original receipt. If unresolved, it can resend **the identical original reservation command/key**; no new key or modified payload is generated. There is no automatic retry loop.
6. Account/token/epoch/role/environment changes reject late responses and immediately hide the old coordinator's exposed data. An HTTP or business 401 expires only the captured current session.

## Shared-file integration request

`docs/app-composition/l4-free-explore.diff` is an exact unified diff against the stated iOS base. It adds an AppSession factory and four source memberships to the existing app target. The three Core test files are picked up by the existing Swift package test target; they do not belong in the AppUnit target.

The patch uses zero context to preserve PBX tabs without introducing whitespace errors inside the saved diff. Apply/check with `git apply --unidiff-zero --check docs/app-composition/l4-free-explore.diff` before applying with the same flag. The diff was apply-checked against copies; shared originals were not edited. The patched PBX parses and adds exactly four file references, four build entries, root group membership and app source membership. The patched AppSession passes syntax parsing. L1 must reconcile/apply this diff and refresh its own manifest; this branch does not edit shared files or CI declarations.

The factory uses existing scoped app storage and the existing composition transport. It leaves reservation authorization **false** and does not bypass that transport's route/capability policy. L2 must review/issue free-explore route grants in its own scope before real requests can pass; supplying a backend address alone is insufficient. No root defaults, market capabilities or backend switches were opened here. Claude/UI still needs a normal player entry using the factory and localized presentation; no navigation or visual UI was changed by this subtask. The full launch definition of done therefore remains open.

Suggested ledger status for the responsible owner: catalog/order/refund quote and reservation recovery source ready; enabled markets none in this branch; normal-entry/runtime proof pending; cancellation quote blocked at frozen backend.

## Verification and remaining work

Performed locally:

- Frozen source inspection and explicit frozen-vs-c6 controller comparison.
- Swift syntax parsing of four implementation files and three test files with tree-sitter: 7/7 pass. This is not a Swift typecheck.
- Syntax parsing of the proposed patched AppSession: pass.
- OpenStep PBX parsing and exact source membership/diff-target validation: pass.
- Exact shared diff application and whitespace checks, exclusive-path and public-content scan: performed before upload.
- Publication uses the public repository Git data API with the supplied base as its sole parent, a new independent branch and `[skip ci]`. The base's two workflows are either push-branch restricted (this lane excluded) or manual-only. No PR, merge or workflow dispatch is requested.

Test source contains **27 behavioral cases**: 11 service, 7 pending-store and 9 coordinator tests. They cover HTTP verbs/paths/body, exact IDs and milliseconds, default-off dispatch, null/foreign/fingerprint-mismatched receipts, context changes/401, server quote values, persistence failure/readback, isolation and corruption, duplicate submission, commit-then-timeout/restart, explicit same-key retry, readback failure and cancellation non-dispatch.

Not run: Swift compiler/typecheck, XCTest, Xcode app build, CI/manifest refresh, device/simulator/localization tests, live authenticated test-backend calls, actual reservation/cancellation or any money operation. No Swift/Xcode executable is installed in this Linux environment. No backend build/test was started.

On an authorized native test host, after L1 integration and its manifest refresh, run `swift test --filter FreeExploreLaunch` (or the existing equivalent Core test wrapper), then the related app typecheck/build. Run staging journey verification only under the separate agreed capability/test-backend authorization. Gemini should verify the frozen-contract gap, context fences, original-key recovery and the shared patch before accepting any end-to-end claim.

Excluded throughout: checkout/order creation, payment, refund execution, redemption, passport, money rules, auth/RBAC/JWT changes, credentials, DDL, production capability changes, private repositories, user-machine access, issue messages, PR creation, merges and CI triggering.
