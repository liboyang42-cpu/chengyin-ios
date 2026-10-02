# Native social and account continuation

Integrated 2026-10-01. Source-only implementation and offline fixture coverage; Swift/Xcode/runtime/live acceptance remain **NOT_RUN**. No network request, message, post, reaction, invitation, report, account deletion or upload was executed for this work.

## Implemented source flows

- Account → public profile, invitation history and play guide; Home's existing Square sheet → text composer; Square detail → author profile, comments/replies, post/comment actions and text edit for the source owner
- Public profile has posts/achievements/about sections, source interest labels and portfolio references, nullable relationship/counts, guest-visible header and a separate login gate for author posts. The profile projection excludes balance and contact handles. Achievement totals use public source counts, not the current account's badge wall
- Invitation history reads 100-member pages and a separate 200-row reward scan. Event type 5, positive reward values and normalized numeric event IDs determine earned rewards. Complete scans without a reward mean first purchase pending; partial/failed scans or absent totals mean reward not synchronized. Integral numeric-string totals such as `240.0` are recognized; malformed, fractional and negative totals fail closed. Unlike the source client's permissive missing-total shortcut, an absent total is never evidence that the scan is complete. A ledger 401 invalidates the private screen; an ordinary ledger failure retains invites. Total and loaded count remain distinct. Duplicate-only pages stop with an incomplete warning
- Guide uses the source's three modes and real Home/Roam tab destinations. Information filtering preserves meaningful numeric titles with distinct subtitles; missing IDs, removed records, empty content and failures remain different states
- Review forms cover text-only new posts, text editing with existing media and associations preserved, comments/replies, explicit LIKE/BOOKMARK state, toggle-only comment like, legacy ID-only report, follow toggle and conversation-start request
- Message detail retains the existing static card/text projection and adds an explicitly opened image-preview destination. Source `msgType=2` uses `content` as URL. Preview service uses an explicit HTTPS-origin allowlist, no account headers/cookies, no redirect transport and a post-download signature/12 MiB check. UI inspects dimensions before decoding and rejects over 32 million pixels. The production media service is nil pending origin approval and a streaming-size limiter; the full preview path is testable with local fixture bytes

## Exact retained contracts

Source anchor: `liboyang42-cpu/chengyin-app-public`, audited revision `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`.

| Flow | Source route / request | Source files |
|---|---|---|
| Public profile | POST `api/user/public-info`, multipart `member_id` | `lib/data/api/registration_api.dart`; `feature/profile/user_profile_page.dart`; `data/models/profile_detail.dart` |
| Information | bodyless POST `api/common/infomation_list`; multipart POST `api/common/infomation_detail`, `id` | `data/api/topic_api.dart`; `data/models/infomation.dart`; `feature/account/play_guide_page.dart`, `infomation_detail_page.dart` |
| Invites and rewards | POST `api/user/invite_list`, pageNum/pageSize=100; POST `api/user/points/list`, pageNum=1/pageSize=200 | `data/api/registration_api.dart`, `points_api.dart`; `feature/account/invite_history_page.dart`, `invite_history_logic.dart` |
| New post / edit | POST `api/creativesquare/action`, source contents/id/pics/request_id/data_id/data_type rules | `data/api/square_api.dart#publishPost` |
| Comment/reply | POST `api/comment/add`, owner_type=3, owner_id, rating=0, contents, reply_id, img_arr='' | `data/api/square_api.dart#addComment` |
| Post action | POST `api/v1/community/posts/{id}/actions`, actionType/requestId/source=APP_SQUARE; DELETE `.../actions/{LIKE\|BOOKMARK}`, requestId | `data/api/square_api.dart#setAction`; `feature/square/square_list_page.dart` |
| Comment like | POST `api/comment/like`, ID only; toggle, no enabled field | `data/api/square_api.dart#setCommentLike` |
| Report | POST `api/creativesquare/report` or `api/comment/report`, ID only | `data/api/square_api.dart#report/reportComment`; `feature/square/square_detail_page.dart` |
| Follow | POST `api/user/follow/action`, follow_member_id; result recognized only from exact source success phrases | `data/api/registration_api.dart#toggleFollow` |
| Start conversation | POST `api/im/start`, target_member_id; positive data.conversationId required | `data/api/im_api.dart#startChat` |
| Image preview | Existing message content URL, credential-free GET after explicit load | `data/models/im.dart`; `feature/im/im_chat_page.dart` |

The dormant `SocialActionService` uses actual injected transport, validates source acknowledgement envelopes and never synthesizes post/comment/author/moderation records. Unknown follow result text and missing conversation IDs become uncertain outcomes. No speculative fallback endpoints or unrelated v1 reporting payloads are used. Legacy simple post publication and the professional community publishing workflow are deliberately not conflated.

## Session, review and uncertainty boundaries

Normal AppSession uses `SocialMemberActionFactory` with no grants by default. Exact per-operation grants can compose follow/unfollow and start-chat with durable replay locks and fresh same-session readback. Square actions remain disabled through that factory; their generation-aware read bridge is retained. See `social-member-action-factory.md`. DEBUG fixture acknowledgements are explicitly labelled synthetic, never inserted into a production feed/history.

Reads check complete account/token/epoch snapshots before returning either a result or a 401. Review identity includes account, epoch and server-derived role. Immutable reviews belong to one coordinator/owner/target; confirmation rereads source context. Post owner, reply permission, target IDs, original text, association and follow/like context changes invalidate a review. No client-invented author identity is sent. Unknown outcomes lock the same account/target across navigation, role/epoch changes and same-account reauthentication. Other accounts cannot inspect those records; returning to the original account does not unlock them. There is no automatic retry.

Locks and unsent editor text are memory-only. Durable uncertainty storage, a correlated reconciliation contract, account-scoped persistent draft encryption, moderation/legal acceptance and deployment capability verification remain prerequisites to live enabling. Navigation-away invalidates pending tasks but preserves read rows that own pushed NavigationLinks; session changes hide them immediately and host `.id` resets private navigation. Media data is cleared on leaving or identity change.

## Explicit remaining gaps

- Professional v1 multi-stage compose/publish, public guideline acceptance, media registration/upload, audience/comment policy editing, mentions, community selection, location disclosure, edit moderation, server/local drafts list and source analytics/governance views
- Image attachment picking/camera permission, audio/video previews, realtime messages, incoming card action execution, message deletion/blocking/mute and broader IM operations
- Public member directory and direct Club member-row linking; the profile destination is reusable and currently linked from Account, invite history and Square authors
- Account inviter binding, deregistration and other sensitive account flows; no duplication of prior participant, profile editing, badge, order, favorite or collection modules
- Read deployment behavior, source API availability, full localization/VoiceOver/Dynamic Type/visual parity, Apple compilation and real account/live business acceptance

This is a bounded migration slice, not complete social/account parity or release readiness.
