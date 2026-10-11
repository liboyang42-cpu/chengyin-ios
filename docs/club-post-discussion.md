# P045 dynamic-card discussion interaction group

## Exact scope and preimage

- Real native baseline: `96d727404a966cd3b3d2437c79449046beda560f`.
- Calendar is already in the baseline. Apply the unchanged image-preview, author-profile, reference-topic and gameplay-preview slices before this patch. Composite preimage tree: `c1c158c5d02903f7acf6847d57a2d0cc4b8d7de6`.
- The member-report slice is independent. All six prior output packages remain sealed and unchanged.
- Master P045, lines 1652–1655: `onPostDetail`, `onToggleComments`, `loadComments`.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- Detail JS 2466–2468 delegates body/card detail to comment toggle. JS 2794–2809 opens one post, collapses a repeated post, resets the previous comment draft on switching, and reads `/api/club/post/comment/list` for the exact `postId`.
- Detail WXML 146–149 binds card detail and comment events separately from user/media/reference/play. WXML 160–179 renders comments under the selected card.

This is one grouped interaction slice: body-to-discussion, expand/collapse, switching cards, inline reads with retry/refresh/pagination, and return from the existing full comments surface. It does not split those controls into separate packages.

## Behavior

The post body/meta region gains the source's discussion action while keeping text selection. It also exposes a native accessibility action; posts without body text have a named discussion target. Author, images, topic details, gameplay and moderation stay separate sibling controls, without a parent-wide tap recognizer stealing their events.

The existing comment button now expands/collapses the same inline discussion. Only one post is open. Tapping another post replaces the selection and starts a fresh read owner; repeating the current post or using Collapse closes it. Missing-topic fallbacks from the earlier reference/play actions also reach this same toggle.

The inline panel uses the existing read-only `ClubCommunityService` comments contract. It shows loading, successful-empty, error with retry, previous/next page and refresh. A failed read is not rendered as an empty conversation. Page size comes from the existing native contract (50); no total count or extra endpoint is invented. Duplicate comment IDs and mismatched post results fail closed.

Open full comments presents the unchanged `ClubCommunityCommentsView` in a large sheet, preserving its existing input/moderation/review permissions. Closing refreshes the current inline page. The new read owner never invokes or cancels the shared write coordinator. No write grant, payment, report, comment submission, social communication or share URL was created or executed by this slice.

## Lifecycle and identity

A selection binds the exact unique accepted post and version, club, viewer account/guest epoch, read scope and composition viewer revision. Both body and explicit-comment actions use the rendered selection, and a stale queued action cannot replace a newer read's discussion. Role-only changes also check the existing live host closure.

Inline reads capture the exact session, generation and source-current predicate. Closing, replacing the post, switching accounts, role changes, refresh and cancellation prevent late responses from publishing. Hidden panel callbacks are retired. Opening full comments does not replace the source feed with a new navigation stack; the existing list/page remains mounted for ordinary close/return.

## Existing production dependency

The baseline's community source-feed service remains dormant in `AppSession`; that separate composition issue is owned by the root/integration line. This patch neither changes it nor claims production end-to-end acceptance. Its read path is functional with the existing configured service. The full comments page retains all existing write gates and cancel/review behavior.

Post sharing was deliberately not invented: the Mini share handler returns a Mini-specific club/post path, and this slice has no verified equivalent public native inbound/share contract.

## Focused checks

Executed on the current computer:

- Sixteen narrow source/static assertions passed.
- Six exact Mini source cases passed: body delegation, exact read request, successful rows, same-post collapse, cross-post reset and dataset fallback. All requests were stubbed.
- Pinned Tree-sitter parsed five Swift files with zero recovery diagnostics.
- Whitespace and complete composite-before-to-after patch/hash reconstruction passed, including reverse-apply check.
- All six earlier sealed patch hashes remain unchanged.

Authored but NOT RUN:

- Eight Core cases for toggle/switch/close, unique exact post, unsafe IDs, guest context, viewer/read/revision retirement and stale callbacks.
- Ten AppUnit cases with a synthetic actor transport: exact post/page request, empty versus error, wrong/duplicate rows, blocked initial read, source/role/logout late responses, latest-wins refresh, close invalidation, retry and page-size boundary.

Swift compilation/typechecking, these 18 Swift tests, simulator/device/UI/VoiceOver and real backend acceptance were not run. This computer has neither Swift nor Xcode; source and syntax checks are not native runtime acceptance.

## Registration and native acceptance

The registration fragment lists only two new sources, two test files and six bilingual keys. Central integration owns source/catalog registration. No PBX, aggregate catalog, CI, shared fixture, `AppSession`, existing comments implementation, gameplay, public-profile or governance implementation is edited.

Native checks: body tap and accessibility action expand; body long-press text selection still works; independent author/image/topic/play controls do not expand; same-card collapse and cross-card switch; loading/empty/error/retry/pagination; late reply after close or account/role change; full-comments close refreshes inline results; source feed page survives ordinary expand/collapse and sheet return; existing comment-write gates remain unchanged.
