# P045 Club invitation feedback, read-only

## Independent scope and source

Base `49c68c6420270b0a0cc7ec8d18bc8561f329d796`; no dependency on the16 sealed packets. The existing `App/ClubDetailView.swift` Git blob is `73f78c3bd232f01697466d9cc98c39126322d848`. The only existing-file change appends a three-line guarded entry after the `ClubMerchantDiscoveryView` mount in its existing AppSession block. Every original byte, including the merchant mount, remains unchanged. GovernanceViews, AppSession, cooperation services, permission/command contracts, central PBX/catalog/CI and other feature lines are untouched.

The unique master `MASTER-v10-extracted-text.txt`, P045 lines1652–1655, names `loadMessages`, `reloadMessages`, `reloadInviteFeedback`, `loadTopics`, `goCoopList` and `goCooperation`.

Exact Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- `pages/club/detail/index.js`, blob `b49b5fb14caf49d47e971cd93ffd73cd94d8e044`: lines254–274 decorate partner/topic/status/time;1177–1213 read messages;1215–1229 filter sent invitations by club topic membership;1231–1232 refresh;818–819 define received/sent global-inbox destinations. `evidence/source-index.txt` supplies the verified function line index, refining the initial START range notes.
- `pages/club/detail/index.wxml`, blob `033ac08d82e76b8b92853b7eda9b4c65a7ce7804`: lines634–691 restrict both feedback groups to owners and render separate received/sent loading, retry, empty and row states.

Before this packet, the ordinary native Club detail showed merchant discovery and other Club tools but no Club-scoped received/sent feedback. A global cooperation inbox elsewhere is not the same scoped Club read. This packet adds that missing view using existing read services.

## Ordinary flow

The ordinary Club detail passes its actual ClubReading instance, AppSession's existing CoopFlow reader, and the existing governance access directly. No optional callback default, new service construction or fixture-only injection is added. Entry requires current owner context and aligned configured/signed-in readers.

Opening the feedback view first rereads the club through the existing guarded ClubReading API. A current owner response with the exact club ID is required before either private data read. It then reads `.topics` with clubId scope (unchanged wire key `id`) and CoopFlow `.invitations` with the existing empty-JSON body. These reuse `/api/club/topics` and `/api/coop/list`; no endpoint, permission, credential or write capability is added.

Received rows require `toType == club` and exact `toId == current clubId`. They may reference a topic outside the current Club topic list, matching Mini's received-recipient rule. Sent feedback requires topicId membership in the fresh Club topics response; it does not guess scope from fromId or toId. Returned order is preserved in each direction.

The segmented received/sent selection is local and causes no extra request. Both source arrays and a valid topic snapshot are required before committing a coherent result. A failed/missing source is a visible failure, never an empty invitation list. Genuine empty lists have direction-specific messages. This native view clears both groups on reload; unlike Mini's independent received state, it does not present received data as part of a fully refreshed result while topic filtering failed.

Rows display actual partner/topic names, raw server time and the six canonical response statuses. Unrecognized, absent or null status stays explicitly unknown rather than Mini's permissive Number(null) conversion to pending. Missing names have truthful labels. Record identity includes direction and invitation ID; the same ID in both directions stays separate, while ambiguous duplicates within a direction fail closed.

Selecting a row opens its exact accepted read-only details: partner, topic, status, server time, invitation/topic identifiers and the returned invitation message. Raw contact fields and financial terms are not projected. Closing/swiping the details rereads owner, topics and feedback. Ordinary navigation back returns to the Club detail.

Mini sends row taps to the global cooperation inbox, where handling occurs separately. This increment supplies the authorized Club-scoped reading and selected-record details; it does not expose or claim acceptance/rejection/cancellation capability. A visible read-only notice states that opening a record sends no invitation or response. No messages or real invitation operations were executed during development.

## Isolation

Each context binds exact Club/account/epoch, current owner flag, Club reader object, CoopFlow reader object/session, governance access identity, authorization generation and storage namespace. A fresh owner read precedes each private refresh. Known owner loss denies the view before topic/invitation dispatch.

Visibility permits and per-request generations retire queued retries and old results. Each new read removes prior private rows and rotates the row-target snapshot token. A target also binds the exact rendered row and complete source context. A different account/epoch, access authority, namespace, reader object, direction, changed row or source read cannot reuse it. Rapid double taps are ignored; changed context or retired target clears the details sheet. A cancelled active read leaves loading safely without publishing data. Older transport completions cannot overwrite a newer accepted result.

No persistent storage, outbound share, financial field calculation, invitation command or transport writer is present.

## Verification and integration

Executed in the authorized current dot workspace:
-40 focused structural assertions PASS: exact additive hunk, preserved existing readers/mount, fresh owner proof, received/sent scope distinction, valid coherent data, identity/reader/generation/visibility gates, cancellation cleanup, safe fields, local direction switching, exact-row details and return refresh.
- Existing governance contract suite:12 checks PASS.
-2 exact Mini Git blobs verified. Source functions executed with local transport/navigation spies: received recipient filter, sent topic membership/order, six statuses/unknown, partner/time projection, refreshed-topic filter, empty/error separation, wrong-club response retirement and source inbox routes. No network or mutation occurred.
-5 Swift files parsed by Tree-sitter with zero diagnostics. This is syntax only, not native typechecking or Apple runtime proof.
- Patch reconstruction/apply/reverse check and16 sealed prior patch hashes verified.

Authored10 Core and10 AppUnit cases: **all20 NOT_RUN** because Swift and Xcode are absent. Native build/typecheck, simulator/device UI, VoiceOver, screenshots and live-account reads are **NOT_RUN**. Normal reader wiring is present in code; live production availability is not asserted.

Register one new App source, one Core source and two test files, then merge22 bilingual keys using the registration fragment. This is independent49 plus one additive ClubDetail hunk. If central integration has additional non-overlapping ClubDetail edits, apply that hunk instead of replacing the entire `after` image. All earlier packets remain sealed; P043/map6 remains paused/cancelled.

Apple acceptance: owner Club→feedback, both directions, true empty/unknown status/failed source/retry, duplicate-topic and cross-Club recipient fixtures, exact row→details→close/return refresh, rapid tap/refresh, cancelled or out-of-order reads, owner loss/account relogin/namespace or reader replacement, large text and VoiceOver. Do not send, accept, reject or cancel a real invitation.
