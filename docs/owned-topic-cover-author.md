# Author cover selection

The ordinary personal city-orientation editor can open this surface after a saved V2 submission acknowledgment. It consumes the existing owned-cover producer. The independent native author capability defaults to absent, and opening Photos additionally requires its `nativePicker` approval. Server producer gates remain independent.

The sequence is explicit: selected-only Photos picker → sanitized local preview → upload → returned asset reference → exact authenticated byte read and SHA-256 verification → image rendering → captured topic/content/selection/CONTENT-slot confirmation. The selection receipt changes the next review input. It is not a new V2 editing acknowledgment, audit approval, release allocation or player grant. Existing review and approved-preparation views can explicitly read the asset from their captured reference; no arbitrary image URL is opened.

The implementation reuses `RetainedNativeImagePicker`, `RetainedImageSanitizer`, `ResponseLimitedHTTPTransport`, and the existing producer routes:

- `GET api/topic/cover/selection/current?topicId=…`
- `POST api/topic/cover/upload` with one sanitized JPEG file
- `POST api/topic/cover/selection`
- `POST api/topic/cover/selection/status` with the original eight command fields
- `GET api/topic/cover/{assetId}/content?sourceVersion=…&contentHash=…`

`OwnedTopicCoverApproval` has separate current-read, upload, selection, status and asset-read operations. AppSession captures viewer and project-configuration generations, and both bounded transport clones retain the outer identity/capability checks. Configuration changes must use the existing synchronous `withProjectEditConfigurationChange` boundary. Persistent owner keys stay stable across permission retirement.

Before a write can be scheduled, its local intent is written and read back. Unknown selection blocks new selection and the next audit/release read. Recovery queries or retries exactly the original command. Current selector changes do not prove a previous request failed. The upload producer has no status/idempotency endpoint: unknown uploads remain recorded, and a later explicit upload is separately identified. Nothing retries an upload automatically.

Returned receipts survive a local persistence error in the current AppSession, including sheet close/reopen, and can retry local persistence without another HTTP write. This transient cache does not survive process termination. Durable journal entries contain references, command identities and digests, never image bytes or credentials. Each topic has a bounded 32-upload/32-selection history; reaching the bound refuses another intent without deleting history.

All synthetic source/picker code is DEBUG-only and visibly labeled. It generates its own image and uses the real client against in-memory responses. It never opens Photos or calls a live producer. Authored coverage includes current/old 401s, configuration and role ABA, queued claims, retained sheet controls, local storage failure, unknown recovery, exact image bytes and separate V2/selection receipts. Apple compilation, native XCTest/UI execution, actual Photos, OSS/WeChat, MySQL and deployment approval are separate checks and are not established by offline parsing or source checks.
