# Square reporting and API-generation boundary

This is a source-backed, offline implementation. Production report reads and writes remain disabled. No real report, moderation request, media upload or external action was sent during implementation. Apple compilation, XCTest execution and rendered UI acceptance are separate gates.

## Normal route and identity

The versioned Square feed now opens an explicitly versioned detail route. Its detail is GET `/api/v1/community/posts/{id}` and its comments use GET `/api/v1/community/posts/{id}/comments`, with the server's decreasing root-thread cursor. Replies do not count as extra root pages. A legacy entry continues to use the legacy detail/comment endpoints. There is no integer-ID crosswalk or fallback between the two generations.

Read models carry their endpoint generation. A versioned report target requires a qualified post and source version; a comment additionally requires its own version and matching parent post ID. Unknown, legacy, stale-version or wrong-parent objects cannot become versioned report targets. The normal detail view mounts reporting, and the session factory is scoped to the current deployment/account/epoch. The default factory does not enable policy reads or submissions.

## Versioned report flow

1. Read `/api/v1/community/capabilities`, using its `reporting` policy version and reason list. Empty versions, duplicate reason codes/labels and inconsistent code lists fail closed. No local fallback policy is substituted
2. Choose a reason in a native nested sheet. Nothing is preselected; Cancel changes no selection. Source labels remain visible, with supplementary English translations for known codes
3. Enter a nonempty description of at most 2,000 UTF-16 units. Attachments are not offered because the source contract rejects nonempty evidence lists
4. Review immutable target, reason, policy version and description. The exact JSON contains `targetType`, `targetId`, `reasonCode`, `policyVersion`, `description`, empty `evidenceAssetIds` and a stable `requestId`
5. Before submission, re-read policy and subject under the same identity and compare origin, ID, version and reviewed content. Changed policy/content requires a fresh review. An account change cancels the old context
6. Persist the account/deployment/typed-target dispatch lock before sending. Unknown outcomes cannot be retried by dismissing, signing in again or creating a new coordinator
7. Validate the returned case against the reviewed target/reason/version/description. Display receipt status as source data, never as proof that content was removed. Exact case readback uses `/api/community-trust/reports/{id}` and never clears the dispatch lock
8. Only an acknowledged case number is retained for later account-scoped readback. Descriptions, reasons, credentials and internal server data are not stored in the case-reference store

The form has keyboard Done, explicit Back from review, dirty-draft cancellation, native Dynamic Type layout and scoped clearing when identity changes. Five authored UI scenarios attach screenshots for normal review, readback, changed policy, unknown/reopen and Chinese large-text nested-sheet states. They do not constitute executed screenshot evidence.

## Neighboring action boundaries

Versioned replies use `body`, `clientRequestId` and only the selected `parentId`; reply relationships are not guessed. Versioned comment likes use explicit POST/DELETE actions with request IDs. Legacy comment/toggle/report endpoints reject versioned snapshots. Legacy post reports separately carry the required nonempty reason (maximum 64 UTF-16 units); legacy comment reports remain ID-only. Legacy likes retain the source's one-toggle contract.

Bookmarks are offered for versioned community posts. The legacy-looking bookmark endpoint delegates directly to community IDs without an ID mapping, so the native legacy screen explains that boundary instead of treating an equal integer as the same post.

Owner-comment deletion uses its generation: versioned deletion carries post ID, comment ID, expected version and request ID; legacy deletion retains its own multipart ID contract. Publisher edit hydration, confirmation and readback use the selected source lane. Existing drafts retain their source lane, cannot switch it in the editor, and cannot be submitted under another lane. Existing live/media/legal grants remain off. No sharing dispatch was added; the detail screen has no share action to reinterpret.

## Validation boundaries

The accompanying Python checks are structural/source checks, not Swift compiler evidence. Supplementary Tree-sitter parsing does not typecheck Apple APIs. Synthetic transports and authored XCTest/XCUITest cases are not deployed-backend or device acceptance. No private backend source, credentials, signing material or live user data is included in this implementation.
