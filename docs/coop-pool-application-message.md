# P045 cooperation-pool application message

## Exact source and backend contract
This is applyCoopPool, not the merchant invitation composer. MASTER-v10 P045 lists applyCoopPool. Mini revision f859cd6e2618f618a53f5cd33949259828e86313, pages/club/detail/index.js:3136–3173 prompts for an optional message and sends topicId plus message: r.content || ''. Native077 CoopFlowMutation.apply(topicID) and the existing pool row preview omitted message.

Read-only verification at backend feature95e499471eaa39c28f77d16125f0cc17b8c37123 (tree22bc7ffc04ce17496c3e37584ff4b00e8c8eb2ba):
- ApiCoopPoolController.java blob3a2bf7a788147e07f8b9e8dea79637c4a764ad9f, apply reads topicId, optional clubId and message; String.valueOf is passed to the service without trimming.
- CoopClubApplyServiceImpl.java blob5f4c6387ac0f6981755ca43cb50f0f497f17ed23, apply passes original message to new rows or reapplication. The inspected Java apply path has no message length, normalization or truncation check.
- migration_open_club_pool.sql blob26b5014f29a3dc9b890ba5f4d80987c953355d11 defines message VARCHAR(500) under utf8mb4. These three blobs equal the pinned Mini-era f859 source.

The client therefore enforces a source-DDL budget of500 Unicode scalars/code points, not Swift Character/grapheme count or Java UTF16-unit count. This is a client guard based on checked-in schema, not proof of a live deployed migration. Text is never trimmed, normalized or truncated; overlength remains editable and cannot be previewed/encoded.

## End-to-end local action
Only the existing pool-apply preview entry is replaced. It consumes the current reader, accepted pool, loaded session and read generation. Exactly one applicable topic row and hasClub=true are required. The optional text editor supports empty text, original whitespace/newlines/Unicode, a code-point count, explicit keep/discard, and the existing generic immutable request preview. Navigating back from preview leaves the same editor's message state intact.

CoopFlowMutation.apply(topicID:message:) has a default empty message, so existing .apply(topicID:) call sites remain source-compatible. Its body is exactly topicId/message; empty input produces an explicit empty string as in Mini. Withdraw and all other mutation bodies are unchanged. The existing generic preview displays all serialized fields, including the original message, through Text(verbatim:). It still has the exact disabled submit button. No service, executor, factory or authorization setting changes.

Coordinator.lockKey and SourceEvidenceReader receive only arity-compatible ignored-message patterns. The legacy account/topic lock key, scoped lock checks and permission reads are unchanged: changing text cannot escape an unknown-outcome lock. The original Coordinator's default-disabled confirmation remains disabled.

## Context and return isolation
An editing session has a fresh UUID and exact current account/token/epoch, reader object, source generation, selected topic and canonical whole-pool bytes. It does not synthesize a clubId, merchantId, invite recipient or invitation confirmation. The source API chooses an active club when no clubId is provided; this local UI does not claim to know or confirm that backend selection. Source rows/name/state/merchant projection changes invalidate the context. Editing/review/dismiss callbacks check the current model binding and session; old dismissals cannot cancel a reopened editor. Each preview has a new review UUID and exact message UTF8 proof. Changed text, stale context or an old review cannot reuse that preview. Leaving/background closes this ephemeral draft; ordinary preview-back retains it.

This guard is local draft/preview isolation, not current server write authority. Future authorized dispatch still needs its existing fresh evidence and separate confirmation. No real send, notification subscription, agreement, pool mutation or backend request was performed.

## Verification limits
19 Core and18 AppUnit tests are authored:37 NOT_RUN because Swift/Xcode are unavailable. Coverage includes empty/default/whitespace/Unicode/500–501 boundaries, scalar versus grapheme and UTF16 lengths, exact body and review, invalid topic/state/club evidence, duplicate rows, source replacements, account/token/epoch/reader changes, cancellation/reopen/background, preview-back state ownership, old review/dismissal isolation, existing lock key and default-disabled coordinator. Model tests are not SwiftUI runtime tests.

Tree-sitter parsing and source/static/oracle checks do not compile or typecheck Swift. Apple acceptance must compile/register the new sources/tests, run all37 tests and existing cooperation suites, then test entry/edit/keep/discard/preview/back/reopen/source switch/account switch and disabled submit on-device. Actual backend/deployed schema and sending acceptance are NOT_RUN.

## Integration boundary
Eleven product paths; four existing files modified only at declared narrow hunks. Core/App new leaves, test leaves, eight-key localization fragment and registration fragment. Generic preview/service remain unchanged. Prior1–30 sealed artifacts and original28 withdrawal remain preserved. All artifacts are local/private; no upload, public publication, commit/push, other environment or old repair.
