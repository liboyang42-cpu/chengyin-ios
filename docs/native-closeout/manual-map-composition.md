# Bounded manual-map normal composition

Base: native local `1264f6e11422204866171437041fcc1a2592c1e0`, tree `66acaa151424e8e49df677e982254b545830d508`.

## Reviewed source

Private backend PR 1189 head `36f9012761ec3b6d170c3f5b39d7c554a4c09ac5`, remote tree `d2fee9396c577515272aef1764ae6274dcaaa3ea`. Mapped local source commit `4d6861556a994a454a97f5b2f2e9301d26c9db1e` is a tracked projection, not a claim of full-tree equivalence. Exact inspected controller/security blob equality:

- `ApiRoamController.java`: `2ee909d333361ec1b75deb76673e212744a8419e`; GET `/api/roam/pois`: lat, lng, radius, controller radius ceiling 20,000 m.
- `ApiMapController.java`: `71485791ab698ac37b89bc05900a426de2fb6b27`; POST `/api/map/nearby`: longitude, latitude, radius, limit. Controller also consumes status/auditStatus; this native grant excludes both. Server maximum 50,000 m/200 rows; the native subset is 20,000 m/100 rows.
- `ApiCityNodeController.java`: `ae41820698189c370b5c88af552b7556e49843c3`; GET `/api/city/nodes`: lat, lng, radius, keyword, categoryId, tag, cityRole. GET `/api/city/nodes/{id}` requires positive ID and returns `poiId`. Existing native decoders correlate that response ID with the requested ID.
- `SecurityConfig.java`: `2fa9e73abd8f23e769a8552bff8ada3bed426df4`; these four reads are absent from anonymous exceptions and fall through to authenticated access. Public merchant routes confer no manual-map authority.

No private implementation is copied into this repository. The independent review re-read these four blobs from the mapped local projection and reproduced their exact Git object IDs. Remote equality is the supplied prior verification evidence; this offline review neither fetched nor asserted equality of the entire backend trees.

## Boundary

The shipped composition stays unconfigured. A reviewed deployment must independently include `.manualMap` and supply a retained `ManualMapReadApproval` for the exact current account, token, epoch, role, market, base URL and namespace. Approval expires and has an issuance revision; re-issuing requires a new instance. Login never manufactures this approval.

Each reader receives an area-bound child of the normal composition transport, sharing its recorder/network adapter and current viewer identity. Roam and Global Search have independent manual-area selections. Each explicit selection advances a revision, even A → A or A → B → A. Requests match the exact selected coordinates and canonical URL or multipart bytes. Malformed framing, duplicate/extra fields, different paths/verbs, body-bearing GETs and unapproved query scopes are rejected before dispatch. Literal `+` in a filter is emitted as `%2B`, and raw `+` queries are rejected because Servlet query decoding interprets them as spaces. This does not expand the filter field allowlist. City filters have a local 256-byte non-control-text bound and positive Int32 category IDs; these are conservative client bounds, not claimed server validation limits.

Both success and failure completions must retain the approval issuance, full current viewer identity/revision and selected-area revision. Reader/UI checks prevent cross-area painting and stale unauthorized completions from expiring a new session. Both normal readers now include the fresh, matching approval issuance in their identity/context, so approval revocation, expiration or reissue after a raw transport response still invalidates the final decoded/fan-out result and retained detail lifetime. Detail views keep their originating area/session lifetime; both origins are captured at view construction and retained in view state rather than recomputed by parent reevaluation or captured only after a deferred task starts. A per-view read-task owner acquires button-task ownership synchronously, blocks work while the view is inactive, cancels the actual reader task on replacement/disappearance, propagates parent cancellation, and prevents a retired completion from clearing the replacement task. A current matching unauthorized response still expires that session.

Only POIs, nearby route-node rows and city-node list/detail reads are admitted. Events, players, explore-day, merchant detail, reverse-geocoding, presence, reveal, discovery, finish, completion, collection, reward, settlement, device location/permission/provider/key work remain outside this grant. Nearby retains manual city fallback without reverse-geocoder dispatch; unsupported layers retain unavailable states. Guest city-search fallback can use only the pre-existing, separately enabled `.homeAndSearch` POST `/api/activity/list` layer, which is explicitly anonymous in the verified SecurityConfig. Without that separate grant the activity layer is unavailable; city-node reads remain a sign-in gate. `.manualMap` never permits guest or partial-identity dispatch to any of its four protected routes. This does not enable W20 board runtime or claim complete W18 market parity.

## Evidence and limits

- Actual normal `AppCompositionRoot`/`AppSession` recorder XCTest is authored for both readers, list/detail, malformed/duplicate/extra scopes, wrong method/IDs, guest/partial identity, realm/token mismatch, absent approval, revocation, area/account/role ABA, current versus late 401, manual fallback and zero location factory/provider calls.
- Existing authored UI suites remain; no new UI execution evidence is claimed.
- Python source-contract and project-regeneration checks are supplementary only. Swift typechecking, XCTest execution, Apple builds and simulator/device UI are **UNRUN** in this Linux environment. No live API, GPS/provider, push, production activation or deployment was used.

## Independent corrections and merge guidance

Review frozen input: commit `e7f02980248f93a6d926561c5697afc82bd73159`, tree `c58e1a26594e676c248bbbbbfe606b9f0a7d4007`, author patch SHA-256 `4b95a6c23e31a5c6808a34b0ec1b326be25b6656fd19086881bf1ae264aab599`.

Corrections address final decoded-result authority, retained view identity, retry task ownership, literal-plus filter semantics, and callback-preserving injected transports. Ten additional app-unit tests are authored for those boundaries, encoded traversal/authority aliases, exact numeric/filter bounds, authority mismatch/expiry, public guest fallback and zero device/provider calls. Their Swift/XCTest execution is **UNRUN**. The final-reader test intentionally uses a plain recorder without a composition response fence to isolate post-service authority validation; it does not claim a real Apple scheduler/decode-race observation.

When combining sibling Play and signed-in content-detail work:

1. The transport's query exception must be the OR of separately validated manual-map and Play route matches. Do not allow arbitrary query URLs, and do not drop either route-specific exception.
2. `scopedForManualMap` and `replacingUnderlying` share one copy helper. Preserve every selector and property there, particularly `ownerDraftReadApproval`, `manualMapReadApproval`, manual selection and the sibling mutable `playReadConfiguration` callback. The normal root and the AppSession replacement helper must keep fresh current identity and callback semantics. Clone chains retain their parent identity source, whose AppSession callback remains weak; temporary intermediate clones must not silently lose the current identity. Content-detail approval is retained through the unchanged deployment value.
3. Preserve the sibling Play approval-issuance rules and all existing async journal/storage/runtime callback changes. This packet does not authorize simplifying those paths or broadening any grant.
4. Keep both normal readers mounted with separate area selections. Re-run the integrated aggregate and Apple app-unit/build checks after conflict resolution. Python/Tree-sitter source checks cannot establish helper signatures, actor isolation, SDK correctness or runtime behavior.
