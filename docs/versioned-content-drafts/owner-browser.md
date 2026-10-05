# Owner content-draft browser

## Scope

Account → Saved content drafts is a normal creator destination. Welcome also exposes a guest entry that opens the existing login sheet. Authentication alone does not enable owner-draft HTTP. An unconfigured authenticated entry explains that access is unavailable.

The browser reads the reviewed W02 ACTIVITY/TOPIC list and restore DTO through `ContentDraftReading`, the read-only portion of `ContentDraftServing`. It has its own metadata-only coordinator because the existing generic editor coordinator requires a reviewed lossless payload schema. No schema or ProjectEdit conversion is invented. No payload, client key, device identifier or raw JSON is rendered. Opening a row reads the latest server metadata; it does not save or restore a previous server version.

The detail shows draft ID, type, version and bounded server-formatted `updateTime` when recognizable. The DTO declares `updateTime` as optional display metadata. Missing, numeric or unsupported representations display “Saved time unavailable”; no clock value, epoch unit or timezone is inferred. The display extension is excluded from the existing mutation/journal integrity comparison and does not alter payload hashing, canonical JSON checks or command identity. A restore-only historical receipt summary is described below. A draft, receipt or hash provides no publication, execution, export, licence or other content-use right.

Editing, auto-save, delete, review and publishing are not exposed. The browser does not construct or access a journal. Mutation functionality remains governed by its separate reviewed coordinator and storage contract.

## Wire and authority boundary

- Existing POST `api/content-draft/list`: form `scope=` with optional reviewed business-type filter. The visible browser requests both supported types together.
- Existing POST `api/content-draft/restore`: form `draft_id=<positive decimal>&scope=`.
- The reviewed list contract is an array with no verified page/cursor fields. The UI does not invent pagination or imply that additional records can be fetched.
- `OwnerDraftReadApproval` accepts only an exact personal-owner grant whose routes are exactly list and restore and whose owner equals the authenticated principal. It rejects merchant delegation and all write routes.
- The exact authenticated context includes CN market, deployment URL bytes, role bytes, account, session epoch, storage namespace bytes and token bytes. The shipping composition's approval provider returns nil. The source seam must receive independently reviewed approvals; authentication, role choices and remote booleans must never mint them.
- The composition transport additionally accepts only the exact bounded form shapes, no owner override/duplicates/page fields/body stream/query/fragment, and rechecks current approval after a suspended response. It uses byte-exact credential comparisons.

## Lifecycle and presentation

AppSession owns the retained browser and revokes it before every account/token replacement, on operation-gate context changes and when its root is deactivated. A revoked browser cannot be reused after role/account/root A→B→A. A stale response is checked before parsing or 401 effects in the W02 service and before browser presentation. Current 401 expires only the matching authenticated context.

List refresh clears prior metadata. Errors therefore cannot leave old rows looking current. Requests reject overlapping loads in the same list lifetime. Leaving the list retires its generation, clears its metadata and permits a fresh read on reopen without waiting for a cancelled transport to finish. Pushing a detail retains the validated owner list. Restore uses a separate generation ticket: Back, a newer selection or session revocation prevents a late success/error from repopulating detail. Restore rejects a different ID/key/owner and a version older than the selected row. English and Simplified Chinese strings, native navigation, native List/Form/ProgressView, retry, pull-to-refresh, toolbar refresh and scalable text are included.

Timestamp display accepts complete bounded ASCII date-shaped strings only, including Jackson-style fractional seconds and colonized or compact offsets. Terminal newlines and other control suffixes are unsupported. Numeric or otherwise unsupported dates still remain unavailable. Binary-plist mutation/baseline compatibility cases cover the current durable-journal encoding and older baselines without the optional metadata field; they do not alter the async snapshot/generation journal contract.

## Verification and remaining acceptance

Source contracts, Python tooling, deterministic project generation and the supplementary Tree-sitter parser are offline checks. They do not typecheck Swift or demonstrate a running iOS screen.

Authored synthetic coverage includes Core lifecycle/read-approval/projection cases, app-hosted tests using the actual AppSession/composition/Account entry and in-process HTTP recorder, and UI flows for real entry wiring, both types, empty/loading/error/retry, guest login dismissal, unconfigured access, metadata-only detail, Back/reopen, lifetime replacement and Chinese accessibility-maximum text. Fixture code is DEBUG-only and never owns a network transport.

Run the exact final integration on Apple hardware/CI before accepting it: Swift tests, app-unit tests, unsigned CN/US builds, the `OwnerDraftBrowserFlowTests` UI class, and VoiceOver/large-text/light-dark inspection. Swift/Xcode tests and live deployments, login, account data, GPS, remote publication and deployment were not run in the Linux source workspace. No production grant was enabled.

## Installed-module historical receipts

The optional `installedModules` extension on the existing restore response is read-only. Only the minimum wire schema is declared in `Core/InstalledDraftReceipts.swift`; no private backend implementation is included. List rows ignore the extension. The independently authored native projection is created only after validating the restored draft's owner, key, ID, active status and nondecreasing version, within the same session and detail generation.

The decoder accepts exactly the known availability statuses `HISTORICAL_RECEIPTS_ONLY`, `NOT_ENABLED` and `OWNER_ONLY`. It requires `POST_INSTALL_POLICY_UNAVAILABLE` and all six explicit false flags: text preview, editing, export, publication, execution and commercial use. Unknown statuses, missing/mistyped flags, any true flag, invalid structures or conflicting bindings make the summary unavailable without hiding otherwise valid draft metadata. They never enable an action.

The receipt schema retains only the ten known fields: installation ID, target draft ID, installed target version, installation time, module version ID, content hash, terms hash, optional installed-target payload hash, binding and historical evidence kind. Unknown extensions are discarded. IDs/revisions are positive, module version IDs are bounded to 512 UTF-16 code units, hashes are 64 lowercase hex characters and installation time is a bounded complete UTC ISO-shaped string. It is displayed without interpreting it as an entitlement clock. At most 50 distinct installation receipts are decoded. `hasMore` requires a full page of 50; disabled/owner-only availability requires an empty array and false `hasMore`. No pagination route is invented.

Every receipt must target the restored draft. `EXACT_REVISION` must match both its version and payload hash; `STALE_BINDING` must differ; `BINDING_UNVERIFIABLE` must have no binding hash. None authorizes content use. The UI only receives installation ID, installed target version, installation time and a localized binding explanation. It never renders module version identifiers, hashes, raw payload, text, rights, private sources or URLs. No installed content is fetched or rendered.

The UI distinguishes an omitted extension (older/unextended response), malformed/unsupported metadata, not-enabled lookup, owner-only lookup, explicit empty historical results and populated history. A full capped result explains that more exists but cannot be loaded here. English and Simplified Chinese use wrapping native text with no fixed heights. The summary has no buttons or content actions.

Receipt metadata is intentionally Decodable-only. `ContentDraftRecord.encode` preserves its pre-extension field set, optional handling and immutable payload bytes, and receipt metadata remains excluded from equality. It is not persisted in journals or sent in commands; a journal reopen correctly has no receipt display metadata until a fresh authorized restore. Existing async caller-held journal snapshots, generation-CAS, prepared dispatch, storage and service contracts remain unchanged. Authored tests cover JSON byte equivalence, binary-plist reopen, actual synthetic durable-journal reopen/replace/clear, and stale snapshot rejection.

Back, list refresh, newer selection, task cancellation and session/root revocation clear or reject receipt presentation through the same owner browser lifetime. The original list Back/reopen behavior is retained. Authored Core/App/UI tests cover receipt states, unknown inputs/caps, normal owner form transport, late responses, role ABA and cancellation. Apple execution is UNRUN in this Linux workspace. Source parsing and offline contract checks are not Swift typechecking, simulator, accessibility or live-backend acceptance.

Post-install lifecycle rules for active, expired, revoked, refunded and withdrawn grants remain unavailable. This change supplies no preview/edit/export/publish/run/commercial policy, receipt refresh endpoint, content rendering, installation writes, default cloud-read approvals or runtime activation.

### Independent receipt review

The independent review found that four new receipt app-unit tests still called the old login-helper signature after the reviewed synthetic-auth fixture baseline correction. Their calls now supply the recorder, and a failing-then-passing source regression checks every composition sign-in call. This source-level repair does not establish Apple compilation.

Nine additional Core probes cover unavailable-state capability escalation, malformed tail rejection, numeric identity confusion, the UTF-16 version bound and exact-50 page, frozen pre-extension synthesized record and whole-mutation binary-plist bytes, discarded nested private extensions, duplicate receipt fields in the actual service envelope, foreign owner/regressing draft rejection, and late success/error after list Back/reopen. Two additional app-unit probes cover same-account logout/relogin and root-lifetime replacement while a receipt restore is suspended. All new Swift tests remain authored but UNRUN until the final integrated revision is checked with the approved Apple toolchain. Existing journal storage, caller-held generation-CAS and prepared dispatch implementations are unchanged.
