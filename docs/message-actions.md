# Text message composer

Source: retained Flutter `lib/data/api/im_api.dart` send operation and `lib/feature/im/im_chat_page.dart` `_Outgoing`/`_dispatch`. This implements text only. No live message, read receipt, media upload, websocket or notification operation was performed.

The source sends multipart `POST /api/im/send` with `conversation_id`, `msg_type: 1`, trimmed `content`, and one `client_message_id` retained across explicit retries. Native uses a 32-character hexadecimal UUID-derived identifier once per intent. It does not invent a new retry key or append `extra_json` for plain text. The original response must identify the same conversation, sender, text and message type before it is shown as acknowledged. Server acknowledgment is not recipient delivery or a read receipt.

The coordinator is retained per account/conversation. It requires a successful current-identity history load, checks the exact expected epoch at dispatch, and ignores stale account completions. Duplicate sends are blocked while sending. A timeout/cancel/malformed result is unknown; it retains the original submitted text and key, blocks replacement, and offers only explicit same-intent retry with an explanatory confirmation. There is no automatic retry or exactly-once claim. A typed `HANGOUT_CLOSED` response is terminal. Server rejection and uncertainty are distinct.

These guards are in memory, not a durable outbox. Restart recovery, media/card sends, user blocking/reporting, read receipts, socket/push delivery and comprehensive reconciliation remain unimplemented. No private message content is logged or persisted by this slice. The original submitted text remains private to its owner in memory for recovery; a different account cannot read it through the coordinator's visible state.

## Integration

Construct `MessageActionService` with the existing approved configuration/no-redirect transport. Retain `MessageSessionWriter` using a live account/epoch/token snapshot and the matching-session unauthorized callback. Cache a `MessageActionCoordinator` per account and known conversation ID. Pass it into `MessagingHistoryView(..., sender:)`; nil retains the old read-only UI. Pass the same factory through `MessagingHomeView` when wiring production navigation. Never reconstruct the coordinator to bypass an uncertain outcome. All networking remains unconfigured by default.

`MessageActionFixtureHost` uses a synthetic in-memory store and no network transport. The fixture's key deduplication demonstrates UI behavior only; it does not verify the backend implementation.

Eleven authored synthetic XCTest cases cover fields/headers, trimmed text and stable key, invalid inputs, timeout without retry, mismatched receipts, terminal codes, duplicate taps, explicit same-intent retry, stale ready identities, account changes and uncertainty retention. Swift/Xcode execution is pending aggregate CI. Local source/whitespace review does not certify runtime correctness.
