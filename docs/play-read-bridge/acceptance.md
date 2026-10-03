# Bounded normal-session Play read bridge

## Scope and source

The normal `AppSession` activity/topic Play reader and richer runtime now have a closed composition route for only:

- `GET api/play/nodes?activityId=<positive canonical decimal>` or `?topicId=<positive canonical decimal>`
- `GET api/play/route-state` with the same one-scope query shape

The source contract was checked against backend PR 1189 head `36f9012761ec3b6d170c3f5b39d7c554a4c09ac5`, tree `d2fee9396c577515272aef1764ae6274dcaaa3ea`. Exact relevant source blobs matched the reviewed source checkout:

- `ApiPlayProgressController.java`: `455e4ecc2830d4775ce56f174cac2d089e37eb06`, nodes lines 323–365; route-state lines 992–1013
- `SecurityConfig.java`: `2fa9e73abd8f23e769a8552bff8ada3bed426df4`, explicit public allowlist and final authenticated rule at lines 117–165

Both routes require authenticated membership. Registration, leader-spectator projection, self-play pass requirements, hidden/locked nodes, and route progress remain server-owned. The native bridge does not accept the backend's legacy `actId` alias, extra request parameters or dual scopes. No private implementation or production response is copied here.

## Two independent approvals

1. `ReviewedAppDeployment.ReadGrant.playNodesAndRouteState` approves this root read family for a reviewed regional deployment.
2. The current session's independently supplied `RuntimeDependencyConfiguration` must match market, full base URL, namespace and account, contain `.reads`, carry an explicit `playReadApprovalID`, and approve the particular exact endpoint path.

A complete current account/role/token is required. Neither login, a root read grant, nor an approved host can synthesize runtime approval. Defaults remain unconfigured with no production grants or credentials. Both legacy and rich readers reach the same normal composition transport; no raw injected transport can bypass the query/endpoint fence.

The reviewed authority owns `playReadApprovalID`: retain one UUID for the grant lifetime even if the selector reconstructs dependency/configuration values, and rotate it after actual grant replacement or revocation/reissue. The default is nil and keeps this bridge closed. The transport, final reader projection and retained-reader keys compare that issuance. Fresh entries consult the live selector rather than cached dependencies. Revocation is observed when the authority is evaluated; an invisible revoke/reissue with an unchanged token is not detectable and is not supported by this contract.

Requests are GET only, body/stream-free, exact canonical URLs. Duplicate/extra scopes, nonpositive or alternate-encoded IDs, foreign origins, credentials, fragments, path variants, mutations and other GET routes fail before network dispatch. Session epoch, account, role, token and viewer revision are rechecked on success and error; retained readers also capture viewer revision, so same-epoch role A→B→A cannot reactivate an old reader. Current 401 expires only its matching session; stale/cancelled/revoked 401 is discarded.

## What remains unavailable

This is readback, not complete gameplay. Start/complete/answer, pause/save/clear, hints, leader commands, advanced runtime, player/circle actions, uploads and production device work are not opened. `PlayMemoryCompletionRecovery` and `PlayMemoryPausedStorage` remain memory-only; this patch does not make them durable or acceptable for production writes. Read-only ready snapshots do not enable write controls. The normal coordinator intersects its enabled capabilities with `.reads` even if a supplied runtime configuration also contains mutation capabilities. Completion/hint/leader/retry methods have their own capability checks; run controls and memory-only run state require `.runPersistence`. No `.reads`-only start/pause/end/restore operation mutates the pause store. Previously loaded rich snapshots are projected only while their captured session and live read approval remain current.

The decoded `leadSpectator` marker is retained separately from `registered`. A leader spectator with `registered=false` does not become a registered player or earn completion/reward authority; leader-specific operational UI remains outside this read bridge.

Other `.reads` adapters such as ending, leaderboard, run-session, OS and team progress remain excluded from this root grant. Separately, the existing ending adapter's POST/form mismatch was corrected to the source controller's GET/query contract. It uses exactly one `activityId` or `topicId`, Authorization and Accept headers, and no body. That protocol-only correction does not authorize ending through normal composition, even with a runtime endpoint approval. The backend ending document contains opener/fragments rather than an echoed account/scope identity; native correlation is the captured authenticated request/session boundary, not an invented response identity field. HTTP/business 401, malformed documents, and late results for replaced sessions have separate authored tests.

## Verification boundary

Authored Core tests cover the strict matcher, independent runtime gates, read-only controls, and the separately scoped ending method correction. Authored normal-root app-hosted tests cover both readers with synthetic authenticated nodes/route-state recorder calls, empty/missing-pass/error and registration/leader states, hidden/locked projection, missing approvals, guests, malformed scopes/queries/methods, current/stale 401, cancellation, logout/relogin, role ABA, and revocation.

Python contract checks and deterministic project/scaffold checks are supplementary source evidence only. Swift, Xcode, app-hosted XCTest, simulator, physical device and live backend execution are **UNRUN** in this Linux workspace. Production capability, provider, deployment and business acceptance remain separate gates.

## Independent review corrections

The independent review added explicit stable issuance, live selector/final-projection checks, read-only runtime masking and run controls, individual mutation guards, and separate spectator data. It also corrected a pre-existing chapter-thought XCTest that incorrectly expected `.reads` to enable writes. The review's normal-session tests reconstruct dependency/configuration values on every selector call with a stable caller-owned issuance and exercise revocation, replacement and newly granted fresh entry. Foundation may normalize HTTP method spelling before the matcher sees it; the predicate is strictly the actual request's `GET` method, not inaccessible pre-normalization text.

The standalone ending-protocol delta is already included in the full reviewed patch and must not be applied twice. Shared composition integration must OR only the fully validated manual-map/detail/Play route predicates and forward `playReadConfiguration` into every replacement/scoped transport clone. It must retain session identity/viewer and approval checks before dispatch, after success and on failure.
