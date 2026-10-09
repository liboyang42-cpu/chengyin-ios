# Station live QR display

Base: native batch 16 tree `9aa1200d14df3eef71f6dd12a4b2cebe4a12fa1a`. Three product paths only: a new App-local receipt/lease/view, a liveCode-only mount in MerchantContentViews, and read-only seconds compatibility in MerchantStationProjection.allowsLiveCode. Static posters and every request, grant, write validator, journal, ready payload and service-window editor are unchanged.

## Source contract

Pinned repository: liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636. The packet retains seven complete blobs with verified Git SHA-1, SHA-256 and original source URLs.

- Merchant game-node index.js (`c986f21dfc089293a07e86ca7cc6a40628985610`) opens a scannable QR after explicit live-code issuance and clears it when closing. Its automatic expiry reissuance is intentionally not carried into this native increment: the approved native flow requires existing explicit Retry/navigation for a replacement.
- ApiChapterMerchantNodeController (`69d10193e11d4db958d6710046e7c338e2f8dc1c`) authorizes VERIFY and returns code, nodeId, nodeName, ttlMs and qrcodeUrl. The existing native service still performs the same access/session/playable preflight and issuance.
- PlayCheckinCodeServiceImpl (`aed85d7ec2a3ed3508e702489440c90420b8d238`) issues play_checkin for 60,000 ms and generates a normal QR directly from that exact code. The native view encodes the returned UTF-8 bytes through CoreImage, without fetching qrcodeUrl or wrapping the token in another URL.
- VerifyDynCodeUtil (`a83a0f8a2e694382817c4a2ec5305507b23a4b37`) encodes v1.nodeId.play_checkin.absoluteUnixMilliseconds.signedLongNonce.base64urlHMAC. The display validates shape/source identity/expiry; it does not claim to verify the signature or redeem the token. Server validation and single use remain authoritative.
- GameSessionRuntimeServiceImpl (`3d8ac26f10eb50ba9c48682d9b4cc7873c7a4862`) emits station window strings using `yyyy-MM-dd HH:mm:ss` (formatDate). DateUtils (`44ede073722824600114bcf7a48319c30a0469b4`) creates SimpleDateFormat without setting a timezone, so these are JVM-default civil strings with no offset. A deployed timezone name cannot be established from this wire contract, and none is guessed. The native read-only validator accepts exactly minute/second civil formats, validates the calendar using the existing validator and compares the first 16 characters, matching game-session-merchant.js (`259d8347c9893514692114c79db1638448d765f3`). It never converts this service window into a local instant or uses it for QR expiry. All writes remain strict minute precision.

## Lifetime and privacy

The QR exists only in memory. A lease binds the full receipt/access/query/scope/observedAt to the existing owner model revision. The coordinator snapshot equality omits observedAt, so the lease explicitly checks it. Every render checks current auth/configuration, scope, owner revision, query, exact snapshot, active merchant access, and busy/review/lock state. A scene departure or leaf dismissal permanently retires the lease and clears its exact owned snapshot, without clearing a newer load. The view checks scene state before rendering and retires on non-active scene changes; backgrounding does not refresh the code. A periodic local tick retires expired or invalid leases without any request. Auth has no independent epoch in this existing service protocol; the lease uses the service's existing scope/auth state, and scope rotation remains the session authority.

Absolute signed expiry must be in the future and no later than observedAt + the bounded returned TTL. Delayed receipts do not gain another 60 seconds. A monotonic deadline also bounds the accepted remaining duration; backwards wall or monotonic clocks fail closed. Invalid, expired, mismatched and stale receipts produce only unavailable text. The raw token is not presented as text, accessibility content, copy, share or save data. CoreImage uses no intermediate cache. privacySensitive is a UI privacy annotation, not a claim to prevent screenshots.

## Validation and remaining gates

Focused Python checks inspect source contracts, exact inverse shared-file hashes, unchanged protected files and localization; they do not execute Swift. Twenty-three app-hosted receipt/lifecycle tests and six pure Core read-time tests are authored. Supplementary Tree-sitter parses are distinct from compilation. Swift/Xcode/Apple SDK compilation, all 29 XCTests, real QR recognition, actual scene/navigation timing, screen-reader layout, Dynamic Type, real device and live acceptance are NOT_RUN in this environment. No backend/user-data request or live issuance was performed.

Central integration must merge the four-key localization fragment into Localizable.xcstrings and regenerate project membership for the new App file and app-hosted test. Do not replace whole shared files; apply the exact two existing-file hunks.

## R1 privacy retirement repair

After expiry or invalid initialization, the lease retains only source metadata and a SHA-256 fingerprint of the JSON value for deferred cleanup. The raw code/baseline are cleared immediately. A later scene/departure can still clear its exact original owner snapshot; exact scope/query/access/observedAt and sorted-JSON value fingerprint checks protect a newer receipt, including a different token with the same observation time. Three regression tests cover these transitions. R0 remains immutable.
