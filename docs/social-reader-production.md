# Object-card and message-image production composition

## Scope and default

The normal `AppSession.objectCardReader` and `socialMessageMediaReader` now resolve
source-backed services through `SocialReaderProductionFactory`. The composition
root injects `NativeRuntimeDependencies.socialReaderApproval`; its shipped value
is nil. No live API request, media fetch, upload, write, consent or OS permission
is enabled by this patch. No production grant or hostname is introduced.

Approvals bind the audited CN market, exact API base URL, storage namespace and
account, independently opt in the object-card or message-image family, and list
exact approved media origins. Media origin approval is never inferred from API
approval. An injected service captures the full runtime context (account, token,
epoch, role, namespace, market and base URL), checked before dispatch, after
completion and on errors. Services are resolved per operation, so a reader first
created signed out can later use a matching authorized session without retaining
an older account's service. Current 401s may expire only their captured session;
late failures after a session change become cancellation.

## Verified source contracts

Backend files were read from the private backend checkout at local Git HEAD
`f280c988305df257545edc0b48a62d61690ef0e8`. This is local source evidence, not a
claim of deployed behavior or remote-HEAD equivalence. The delivery manifest
records hashes of these source files.

- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiObjectCardController.java`:
  `POST /api/object-card/list` accepts pageNum, pageSize and category; memberId is
  obtained from the authenticated principal. `PlayerObjectCardMapper.xml` scopes
  list/count by memberId. Native retains its existing first-page, 40-row contract.
- `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiImController.java`:
  `POST /api/im/messages` accepts conversation_id, cursor_id and size.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ImServiceImpl.java`:
  `listMessages` requires conversation membership, active group/team/hangout access,
  and an open group. It returns rows plus nextCursor and hasMore, with size capped
  at 50. `send` treats image content as a media URL.
- `chengyinhub-system/src/main/resources/mapper/business/ImMessageMapper.xml`:
  message paging is scoped to conversation and excludes removed status=2 rows.

No message-info, owned-object detail, capability, or media-proxy endpoint is
invented. Object rename and all IM mutations remain outside these factories.

## Exact-message authorization and bounds

Before a message-image download, the factory re-reads the authenticated message
page endpoint and requires the same message ID, conversation ID, image type and
full URL. It repeats this after receiving valid image bytes. Lost access, removed
messages or changed URLs reject the result. No authorization cache is persisted.

The source has no exact message-info endpoint. Readback starts at cursor 0 and
follows only returned nextCursor values. It rejects duplicate IDs, wrong
conversations, empty continuation pages and repeated cursors. A defensive budget
of 20 pages of at most 50 messages is imposed per readback. An image older than
that scan remains unavailable even if the conversation is readable; this is an
explicit fail-closed limitation, not a claim of complete historical-image access.
No cursor is fabricated from a message ID. At most two such scans run per image.

Production defaults use the existing ephemeral no-redirect,
`ResponseLimitedHTTPTransport`: API responses are bounded at 1 MiB, and media
responses at 12 MiB while streaming. Media uses GET with no authorization,
proxy authorization, cookies, body or credential store. The existing image
signature and view-level pixel bounds remain. Test dependencies use inert
recorders, never real external calls.

## Verification boundary

Authored Core tests cover scoped grants, source form request shape, delayed login,
wrong owner/market/origin/namespace, stale token/role/epoch, cancellation during
API and media requests, no conversation access, wrong message/type/URL,
post-fetch revocation, pagination loops and bounds, and stale 401 behavior.
App-hosted tests check that the normal session properties call these factories
and remain unable to send when unapproved or signed out.

Python contract checks, deterministic project generation/scaffold checks and
Tree-sitter are supplementary source checks. Swift typechecking, SwiftPM domain
execution, app-hosted XCTest and simulator/device behavior are NOT_RUN locally;
Apple CI on the integrated exact commit is authoritative.

## Final reader-boundary correction

The dynamic normal-reader initializers now require the full current runtime
context, captured before the operation. Both success and catch/401 paths recheck
it on MainActor after the nonisolated service has finished decoding or validating
media. This closes the interval after the transport's final check when a role,
namespace, market or API-origin change can leave account/epoch/token identities
unchanged. A missing required context denies the operation until it appears;
signed-out-first construction still recovers. Object collection scope also rotates
for those full-context changes, clearing stale selection/collection state.

Five new deterministic Core regression tests use inert continuations to pause
immediately after the approved transport has finished, or after image decoding
and the last successful media authorization callback. They change role,
namespace, origin, market or remove context before release, and assert no old
result or 401 callback escapes. These are authored tests; Apple execution remains
NOT_RUN locally. The original endpoint and origin approvals are unchanged.
