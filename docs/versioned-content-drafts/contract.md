# W02 versioned content-draft client seam

## Scope and activation

This is a dormant typed client of the existing `/api/content-draft` service. It is not a second draft backend, a publish action, an editor UI, an installation action, or an entitlement policy. No production route grants, login, network allowlist, storage implementation, or permissions are enabled. The existing composition transport continues to reject these routes.

`ContentDraftDocument<Payload>` and `ContentDraftCoordinator<Payload>` require a reviewed, lossless `Codable & Equatable` payload schema. They reject unknown-field loss on decode/re-encode. There is no generic JSON editing screen. The existing native `ProjectEditDraft` uses separate topic publication bundles, edit-detail snapshots and local identities; no evidenced W02 payload-schema or identity mapping exists. It is therefore deliberately not wired to this seam. A real editor adapter remains a separate acceptance prerequisite.

The endpoint contract was checked against the existing controller, command/domain DTOs, service, mapper, and canonical UTF-8 digest helper. Public code contains a fresh client implementation and synthetic fixtures only.

## Exact wire shape

All operations are POST, with the existing raw token in `Authorization`. No owner ID or local operation UUID is sent. Responses use the existing AjaxResult envelope: inspect `code` before decoding `data`, including HTTP 200 with envelope `code: 409`. Successful HTTP bodies first pass bounded whole-document JSON validation; duplicate envelope/record keys fail as malformed before code interpretation or unauthorized callbacks. HTTP-level failures remain independent of AjaxResult body formatting.

- `save`: JSON body `businessType` (`ACTIVITY` or `TOPIC`), `clientDraftKey`, nullable/omitted `subjectId`, JSON-encoded string `payloadJson`, `expectedVersion`, `deviceId`, `scope`; `id` is omitted on create and required on update.
- `restore`: form fields `draft_id`, `scope`.
- `list`: form fields optional `business_type`, `scope`.
- `delete`: JSON body `id`, `expectedVersion`, `scope`.
- `publish` is intentionally absent from this client.

Scope is empty (principal), `MERCHANT` (server resolves PROJECT_MANAGE owner), or `CLUB` (principal for this service). Merchant UI intent does not resolve or authorize the owner. The grant must bind the reviewed account/role/realm and resolved owner. Unknown nonempty scopes are not modeled.

Flat response fields consumed are `id`, `ownerMemberId`, `businessType`, `clientDraftKey`, nullable `subjectId`, `payloadJson`, `payloadHash`, `status`, `version`, `updatedByDevice`, nullable `publishedResourceId`. Dates and additive optional fields are tolerated without becoming authority. A `DRAFT` read is required for restore/list; a delete acknowledgment is `DELETED`.

## Identity, CAS, and replay

The key identity is resolved owner + business type + `clientDraftKey`; the assigned `content_draft.id` is distinct from `subjectId` and published resources. Keys and device IDs are nonempty, already trimmed under the server’s Java `String.trim()` boundary (including edge C0 controls) and the stricter client whitespace check, at most 64 UTF-16 code units. Changing a key to evade an unknown outcome is not supported.

- Create uses `expectedVersion: 0`, no server draft ID. The server creates version 1. Repeating the same key may return any later active version only when payload and subject still match.
- Update sends the exact baseline ID and version N. Both normal acknowledgment and matching retry require version N+1, active status, matching subject and payload.
- Delete sends ID/version N and accepts only the matching deleted N+1 record.
- The server canonicalizes JSON and hashes those UTF-8 bytes with SHA-256. The client verifies the returned hash against returned bytes; it does not pretend a locally sorted JSON hash equals the server canonical hash. Canonicalization comparison is lossless for numbers, strings and object keys, including escaped forms and Unicode code-point differences. Duplicate keys, excessive nesting and pathological exponents are rejected.
- Client resource bounds are 512 KiB payload, 1 MiB response and 128 nested JSON levels. These are defensive local limits, not asserted server limits. Oversized results fail closed.

Known first-attempt 409 conflicts preserve local edits. Explicitly fetch the latest version, choose whether to retain local edits or use the cloud payload, then create a new review. No automatic overwrite/retry occurs.

An uncertain write persists the exact immutable command before dispatch and retries those exact bytes/key/version only. A subsequent conflict/denial/readback cannot prove that an earlier attempt did not commit: its pending lock remains. This service exposes no general mutation-status endpoint, so such divergent unknown outcomes require a separately reviewed recovery process. GET/list alone never clears uncertainty. A matching mutation acknowledgment does.

## Lifetime and persistence boundaries

Use a fresh `ContentDraftSessionLease` for a session lifetime. Its host must revoke it on every logout/account/role/token/market/realm transition, including an intermediate A→B→A. The context also carries the monotonically advancing session epoch. Before/after HTTP and before 401 callbacks, the service checks the irrevocable lease, byte-exact captured authority context, exact endpoint grant, owner and scope. Canonically equivalent Unicode spellings do not share a realm, role or journal; full journal records compare all string bytes exactly. Old coordinators are never retargeted to new drafts. Invalidation clears in-memory private content, but not the durable pending journal.

Read-only clients need no journal. Coordinator mutations require an injected `ContentDraftSecureJournal` implementing confidential, durable, atomic insert-if-empty/identical and full-record plus caller-owned-generation compare-and-swap replacement/clear. Scope binds market, endpoint, namespace/realm, account and resolved owner/business/key. Tokens, epochs and request scope are excluded so relogin or a scope change cannot lose an uncertain operation. Different request scopes resolving to the same account/owner/business/key share the lock. The pending command keeps its original request scope; reopening under a different scope is blocked rather than silently rebinding that command. An opt-in [encrypted journal candidate](../versioned-content-draft-journal.md) is supplied, but no production composition activates it and no plaintext/in-memory fallback may be substituted.

`ContentDraftService.mutate` now accepts only the coordinator-minted, one-attempt `ContentDraftPreparedDispatch`; the raw mutation overload is intentionally removed. It verifies the immutable request and caller-owned journal generation at the final dispatch boundary. Consumption and retirement are separately irreversible, including retirement while the final read is suspended. Network-capable transports require the concrete durable adapter's sealed fixed-OS-storage provenance; arbitrary journal/store conformance cannot confer it. The internal final in-process recorder is the only synthetic transport exception, and has no executable callbacks or network forwarding. Reads remain unchanged. See the [journal API compatibility notes](../versioned-content-draft-journal.md#api-compatibility-and-source-only-verification).

This source boundary is not runtime proof of Security/APFS durability, reviewed editor ownership wiring, endpoint deployment approval, or protection against arbitrary code manually sending HTTP outside this client. Those remain independent activation gates; no UI writer or production capability is enabled here.

## Optional installed-module evidence

An optional `installedModules` restore projection is being reviewed independently. Its absence remains valid. Historical receipt visibility, `EXACT_REVISION`, installation IDs or hashes must never imply preview/edit/export/publication/execution/commercial-use rights. This client does not add any such capability or issue content-use actions. An optional projection may be added only as a read-only typed field after its exact public schema is reviewed; it must not change `payloadJson` or mutation identity.

## Verification status

Authored Swift recorder tests cover exact form/JSON shape, create/update/delete/restore/list, owner denial, malformed records/hashes, canonical JSON, same-key retry, crash recreation, known/unknown conflict recovery, late results/401, ABA, each session authority dimension, journal failure and default-off behavior. Additional independent-review cases cover duplicate envelope/data/identity keys, ambiguous 401/409 envelopes, Unicode authority aliases, and full-record journal equality. They use only synthetic data and an in-process recorder. They do not use a live account or server.

Python source-contract checks and supplementary Tree-sitter parsing are separate evidence. Swift typechecking, Swift tests, Xcode app builds, simulator/device runs, actual network behavior and editor integration are NOT_RUN in this Linux workspace. Passing source checks is not a Swift test pass or production acceptance.
