# L4 invoice handoff — continuation 2026-11-05

Status: independent implementation and isolated tests complete; **not launch complete**.
The shared composition patch is delivered for Claude review, not applied. No live invoice
application, title change or cancellation was sent. No CI, PR or issue comment was created.

- Public target: `liboyang42-cpu/chengyin-ios`, issue #130.
- Continuation branch: `codex/l4-invoice-followup-20261105`.
- Preserved original delivery: `codex/l4-invoice-launch`, head
  `533b2a5c53bb19d7c0386ecc41b575c818498207`. Original branch was not changed.
- Continuation iOS base: `08be33155c71d87d4008839fcf83f6cc22aef000`.
- Original iOS base: `0a56746aca42158dda20c821a1d50f089f0d5ae8`.
- Backend contract: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4` only.
- `c6eac3b8cebf7311e8f00f208d294c3c8212aaec` was read only as a labelled
  difference reference; no backend upgrade or backend edit is included.

## Reconciliation with integration

At the pinned continuation base, none of the original nine delivered files were
present. The original commit is not an ancestor of that integration SHA. There is
no `InvoiceLaunch` factory, normal entry or `/api/invoice` call in App sources.
The existing `MemberSubscriptionAndOrderInvoiceSectionView` uses static audit
snapshots; its READY/ENFORCED copy is not evidence of a working invoice journey.
`InvoiceHistoryUnknownProjection` is an existing pure projection, not a transport.
No alternate invoice transport/owner implementation was found. Issue #130 still
has no assignee or comments at this read; this continuation does not post one.

This branch migrates the original four Core sources, three tests and two handoff
files onto the pinned integration base; it does not introduce a parallel invoice
implementation. The original service and journal remain byte-identical. Existing
API/auth/storage dependencies were compared before reusing them. Do not cherry-pick
both the original nine-file commit and this nine-file continuation. Integrate one
complete continuation patch, resolving any later owner changes against its base.

Additional independent work completed:

- `overview()` returns server titles, server-selected eligible orders, application
  history and the exact pending record together. It never releases a pending write,
  invents eligibility, returns a partial result or accepts a stale session result.
- Every failed post-mutation or pending-recovery read now reports `outcomeUnknown`
  while retaining the original record. A read's NOT_FOUND or FEATURE_OFF can no
  longer look like a definitive rollback of an earlier committed write. Only a
  coded rollback from the mutation itself clears the original as rejected.
- `documentStatus` reuses existing `InvoiceFileStatus`. With no file locator in
  this frozen projection, even ISSUED plus an invoice number remains UNKNOWN for
  document availability. No download URL or original requestId is fabricated.
- The shared handoff diff was regenerated against current PBX structure; its
  AppSession and AppCompositionRoot preimages are unchanged from the original
  baseline. Shared source files were only read, never edited or applied.

Remaining complete-journey work, with ownership boundaries:

| Gap at the pinned base | Required next owner/action |
| --- | --- |
| Migrated Core not yet in integration; four sources unregistered in PBX | Claude reviews/migrates this branch, applies/rebases the shared diff and refreshes the manifest |
| No normal invoice entry or Chinese/English presentation | Claude wires the entry to `overview`, original detail, mutation and recovery methods; presents pending before a new intent |
| `RegionalLaunchConfiguration.composition` passes `reviewed:nil`; verified capabilities remain empty | Existing deployment/login owners provide the approved test configuration; this branch does not change grants or auth |
| Unknown apply without known ID and unknown title save cannot be read by request | Backend owner/main coordinator resolves the frozen missing receipt contracts; client must retain pending, never resubmit legacy save or apply |
| Application projection has no invoice document locator | Backend/file owner supplies reviewed file evidence before any download journey can be accepted |
| Full App, device storage and real backend evidence absent | Current native-build/Gemini owners run permitted validation after shared integration; no CI or real trade was triggered here |

The shared zero-context diff requires these exact preimage blobs before use:

- `App/AppCompositionRoot.swift`: `8dcee370eac7a235cbeb2ce184a3d6fe2fe0a85e`
- `App/AppSession.swift`: `71a95534f52f604aca62c475970d408f4623fa1d`
- `Questify.xcodeproj/project.pbxproj`: `7d69d96f1a37715b68d83a9970d117920e892ece`

Check with `git hash-object <path>`. If any preimage differs, Claude must rebase the
patch rather than applying line-number insertions blindly to changed shared files.

## Frozen contract evidence

Read the frozen [controller](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiUserInvoiceController.java),
[service](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/UserInvoiceServiceImpl.java),
[mapper](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-system/src/main/resources/mapper/business/UserInvoiceMapper.xml),
`UserInvoiceTitle`, `UserInvoiceApplication`, `UserInvoiceOrderLine`,
`UserInvoiceException`, and `ApplicationConfig` at that exact SHA.

The frozen tree has **8**, not 11, public invoice endpoints. Every route below
is POST JSON with raw Authorization, using the existing HTTP transport seam.
The backend obtains member ownership from the authenticated session, never the body.

| Route under `/api/invoice/` | Body | Result used |
| --- | --- | --- |
| `titles` | `{}` | Complete active title list; masked tax number |
| `titles/save` | optional `id`, `titleType`, `titleName`, optional `taxNo`, `isDefault` | Saved title projection |
| `titles/delete` | `id` | Success envelope with no data |
| `orders/eligible` | `{}` | Server-selected registration orders and amounts |
| `apply` | `requestId`, `titleId`, `orderIds` | Application with complete order lines |
| `list` | `{}` | At most 200 application summaries; order lines can be empty |
| `detail` | `id` | Original owned application with order lines |
| `cancel` | `id` | Original owned application, status CANCELLED |

Application fields match `applicationView`: `id`, `applicationNo`, `status`,
`titleType`, `titleName`, `taxNoMasked`, `totalAmount`, `orderCount`, `provider`,
`invoiceNo`, `rejectReason`, `issuedAt`, `createTime`, `orders`, optional `replayed`.
Order fields: `orderSource`, `orderId`, `amount`, `orderTitle`, `ticketName`,
`paymentTime`. Decimal amounts are displayed as returned, never summed, priced,
converted into a tax basis, or used to calculate eligibility. Jackson dates retain
their string or integer-millisecond representation without inventing deadlines.
Only SUBMITTED, ISSUED, REJECTED and CANCELLED exist on the frozen application.
Unrecognised states fail decoding and retain a pending write as unknown.

**Contract blocker:** the frozen public controller does not expose `request`,
`titles/save-request` or `titles/request`. Its `applicationView` does not echo
`requestId` or `titleId`. The frozen mini-program tree has no invoice pages or
`utils/user-invoice.js` (`git ls-tree` and `git show` verified this).
Those five mini-program pages and eleven endpoints exist at the c6eac3 reference,
including `save-request → titles/request` and `apply → request`. They were inspected
for comparison, not silently enabled or used as the frozen contract.

## Writes and recovery

- A shared device journal saves and reads back the pending operation **before**
  dispatch. A pending record rejects both a different intent and the same-body
  resubmission. A main actor lock also fences concurrent taps and recovery.
- Pending metadata stores original application requestId/titleId/orderIds, or an
  original title/application entity ID. It stores no token, title name, tax number,
  invoice document or amount. Realm, backend and account scope it; session epoch,
  role and token fence dispatch and completion. Revoke retained services on logout.
- A validated apply response checkpoints its returned application ID before the
  mandatory detail read. Restarts can then read that exact ID and match order IDs.
- An unknown apply **without a checkpointed ID** cannot safely recover against
  this frozen API. It stays pending with `originalReadUnavailable`; neither list
  matching nor a new apply is attempted. Apply's server idempotency is not used
  as a substitute for the user's read-only recovery requirement.
- An unknown `titles/save` also stays pending with `originalReadUnavailable`.
  There is no idempotent save receipt. No retry through legacy save and no matching
  by title name or masked tax number is allowed. A known successful save must be
  independently found by exact returned projection in the complete titles read.
- Cancel has **no requestId receipt**. Unknown cancel reads only its original
  application ID. Only observed CANCELLED clears the journal and returns the
  application fact. Frozen `cancelApplication` updates the owned ID from SUBMITTED
  to CANCELLED; `cancel` and `releaseOrderLines` are in one transaction. SUBMITTED,
  ISSUED, REJECTED, NOT_FOUND and read errors retain the pending cancellation.
- Delete also has **no requestId receipt**. Unknown delete reads the complete
  active titles list. Absence of the original ID returns `titleAbsent`, a fact,
  not a receipt attributing the deletion to this call. This release condition is
  specific to frozen `selectTitlesByMember` (all owned `del_flag=0` rows, no LIMIT)
  and `deleteTitle` (same owned ID becomes `del_flag=2`). Present ID, incomplete or
  failed read retains the journal. Application-list absence is never a release
  condition, since that list is capped and has no requestId correlation.
- Only a known business rollback **from the mutation response itself** can clear
  pending without readback. REQUEST_IN_PROGRESS, REQUEST_REUSED, timeout, transport
  errors, session changes and malformed success stay unknown. Rejections during
  the later read do not establish that the write rolled back. A failed secure
  storage read/write/checkpoint/delete is visible and prevents new dispatch.

## Composition deliverable and remaining integration

`docs/app-composition/l4-invoice.diff` is an exact patch against the stated iOS base:
The patch uses zero context against that exact base (apply with `--unidiff-zero`);
it registers only four new Core sources in PBX, adds a closed-by-default reviewed
factory and retained AppSession coordinator, and adapts the existing device-only
Keychain storage. It adds no server address, capability, grant, feature switch or
UI. Core tests are discovered by SwiftPM, not the AppUnit PBX target.

Claude must review/apply/rebase that patch and refresh the current CI manifest under
its exclusive ownership. The current manifest was intentionally not edited.
Claude's normal invoice entry and bilingual presentation still need to call this
coordinator. Recovery must run on re-entry and before allowing a new intent.
Surface `originalReadUnavailable` as unresolved state, never as a failed request
that invites re-submission. Host invalidation must include account, epoch, role,
token, market/realm and deployment approval changes. The diff captures viewer
revision in addition to the session tuple to reject intermediate transitions.
Do not enable invoices for launch until the frozen-contract recovery blockers,
reviewed environment, normal entry and end-to-end evidence are resolved.

## Validation evidence

Linux Swift 6.0.3 in Swift 5.9 package mode: **31 XCTest cases passed, 0 failures**.
An isolated temporary package compiled the four exact new Core sources plus the
unmodified current-base `APIConfiguration.swift`, `AuthRequestBuilder.swift`,
`AuthService.swift`, `Account.swift` and `InvoiceHistoryUnknownProjection.swift`, with the three exact new XCTest files.
No mock replaces those production dependencies; transport/storage test doubles are
explicit test-only seams. This is not the full Core suite or iOS application build.

Reproduce the isolation by copying those nine sources into
`/tmp/invoice-validation/Sources/QuestifyCore`, the three tests into
`Tests/QuestifyCoreTests`, and creating a Swift 5.9 package with a QuestifyCore
target and QuestifyCoreTests test target depending on it. Run:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/invoice-validation/clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/invoice-validation/module-cache \
swift test --package-path /tmp/invoice-validation \
  --cache-path /tmp/invoice-validation/cache \
  --config-path /tmp/invoice-validation/config \
  --security-path /tmp/invoice-validation/security -j 4
git apply --check --unidiff-zero docs/app-composition/l4-invoice.diff
git diff --cached --check
```

Coverage includes real frozen request shapes, server decimal preservation,
masked projections, summary/detail differences, absent receipt routes, durable
write-before-send, unknown restart, same-ID recovery, double tap, mismatched
responses, coded rollback versus read failure, request reuse/in-progress, title
PII exclusion, backend/account/realm isolation, epoch/role/token changes, stale 401,
corruption, failed write/readback and failed journal deletion. Follow-up coverage
adds atomic overview, stale/partial/corrupt-journal browsing, all mutation kinds
with a later read rejection, non-cancelled final facts, and ISSUED without file
evidence. Shared diff application check, App syntax parse and PBX reference
structure checks also pass; these do not constitute a full App typecheck.

Not run: full-repository Core tests, Xcode/AppUnit/UI/device tests, live backend
requests, actual invoice application, real title deletion/cancellation, Java tests,
WeChat mini-program tests, CI or Gemini verification. Backend test services were
not started. Shared source files were not modified; no other lane's files changed.
