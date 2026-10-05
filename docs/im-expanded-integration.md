# IM source-backed expansion

## Scope and evidence

The existing MessagingContracts, MessagingService/Reading/History, MessageActionService/Coordinator text-send foundation and SocialMessageMedia image-preview service remain unchanged. New names use IM prefixes and reuse MessagingReadIdentity, MessagingMessage, MessagingCardResult, SocialMessageMediaService origin/byte limits, AuthRequestBuilder and HTTPTransport.

Source mapping:
- `lib/data/api/im_api.dart`: start = POST `/api/im/start`, multipart `target_member_id`, `{code:200,data:{conversationId}}`; read = `/api/im/read`, `conversation_id`, no required data; mute = `/api/im/mute`, `conversation_id`, `muted` exactly `1`/`0`
- Same file: send = `/api/im/send`, `conversation_id`, `msg_type`, `content`, optional `extra_json` and stable `client_message_id`
- Same file: upload = `/api/common/uploadOSS`, multipart file field `file`, response URL at **top level** `url`, not inside `data`
- `feature/im/im_chat_page.dart` `_Outgoing`: image type 2 URL content; route type 3 content `[路线]`, `{cardType:route,topicId}`; location type 3 content `[位置]`, `{cardType:location,name,address,lat,lng}`. The wire content strings deliberately retain source Chinese tokens rather than translating the server payload
- `feature/im/chat_card.dart` plus `_SystemCardBubble`: only sender ID 0 may expose trusted review results; generic buttons are not business-write endpoints. Existing result fields are preserved by MessagingCardResult
- `im_chat_page.dart:65,547` and `im_list_page.dart:46`: source explicitly does **not** implement WebSocket. It refreshes latest history and read state. `data/models/im.dart` has text/image/card/system types, no IM voice type

No realtime handshake, socket ticket, reconnection or IM voice upload/playback was inferred. Those are source gaps, **not migrated features**. The pure IMRefreshGate models explicit refresh completion and invalidation, not realtime transport. No microphone, camera, photo library, location service, permission prompt or external navigation is invoked.

## Installed integration and deployment constraints

The following ownership hooks are now installed in the main checkout. Source files/catalog/project and the DEBUG fixture branch are integrated. Deployment providers remain gated.

1. Core/App/Test files are installed and the project was regenerated with the existing generator; no manual UUID patching
2. The 36 `im-expanded-localizations.json` entries are merged into Resources/Localizable.xcstrings, preserving existing translations. Keys are English and Simplified Chinese; `action.cancel` is reused
3. AppSession now instantiates `IMExpandedWriter(service: nil, session: { ... })` by default with caches keyed by account/epoch/conversation and an epoch-scoped conversation starter. The concrete IMExpandedService also defaults `writesEnabled: false`. If an explicit configured deployment is permitted later, supply IMExpandedService with existing APIConfiguration and a bounded, no-redirect authenticated HTTPTransport. The new token capsule IMExpandedSession is intentional: existing session token fields are fileprivate, so no existing token visibility was expanded
4. Conversation detail host: create IMScope using the exact loaded account/epoch and conversation ID. Hold IMExpandedCoordinator per that scope. Present IMConversationControlsView only after a successful current-scope history load. Pass the host’s live identity. onReceipt(.read/.muted) must refresh existing conversation data; do not assume a local unread/muted value is a current server list response. .sent receipt can trigger the existing explicit history reload. No automatic read-on-appearance side effect was added
5. Conversation-list host: present IMStartConversationView with an IMConversationStarter that requires account/epoch but no fabricated conversation ID. Only `.started(id)` with a positive validated receipt may navigate. The route host owns navigation; these views do not open external links
6. Image composition: supply IMImageUploadCoordinator with the same scope, writer, and default IMDormantImagePicker. Only an approved native picker may replace it. Picker must downsample/re-encode, strip metadata, verify decoded dimensions (<=32M pixels), enforce byte budget during acquisition and never return outside the requested scope. Provider permissions are not implemented in this package
7. IMImageComposeView separately obtains selection and upload consent. `.uploaded(url)` is passed to `onReviewImage` which constructs IMOutgoingIntent(scope:payload:.image(url)) and reviews it through IMExpandedCoordinator. Upload never auto-sends. Unknown upload remains unknown across dismissal and blocks another selection in this owner. No upload retry or idempotency contract is invented
8. Keep SocialMessageMediaView for received-image preview: it already provides explicit user opt-in, metadata-safe origin display and dimension checks. Do not replace it or auto-load image URLs
9. Message detail host may render IMCardActionsView and receive typed IMCardDestination. `.topic(id)` can call the existing native topic destination. `.review(result)` is local display-only. Unsupported arbitrary paths remain disabled with explanation; source action strings do not grant navigation or execution authority. No broadcast telemetry is sent by this module
10. Explicit-refresh host may use IMRefreshGate.begin(scope) / finish(generation,scope) / cancel to reject stale results. This is an integration helper; existing MessagingHistory generation guards are not replaced
11. For UI tests, QuestifyApp now has an explicit launch-argument branch before ordinary production navigation: when `--im-expanded-fixture` is present, read its following scenario (`dormant` or `route-review`) and use IMExpandedFixtureRoot(scenario:). This is synthetic-only and bypasses AppSession construction. Ordinary Account → Messages navigation now passes IMExpandedNavigationContext; no live feature flag was enabled

## Safety and exact remaining gaps

- All service instances are injection-only; no production host, credentials, endpoint enablement, socket or storage origin is defaulted
- HTTPTransport returns buffered data. New 2MiB response and existing 12MiB image limits do not replace a streaming bounded transport. The transport must block redirects (especially auth redirects) and cookies. Requests explicitly disable cookie handling. Device deployment stays gated until this is verified
- Upload supports vetted JPEG/PNG bytes with fixed safe filenames. This is a conservative client policy, not a claimed server upload restriction; other source-picker formats need an approved decode/re-encode provider
- Signing/storage URL origins must be an exact explicit set. No wildcard storage host, arbitrary signed-URL logs or raw URL UI
- Source card click-back telemetry is intentionally not executed. Arbitrary internal action paths outside the allowlisted `/topic/<positive ID>` projection are not integrated; unsupported button is truthful, never “handled” without a receipt
- Mutable backend state after HTTP acceptance and before interruption cannot be inferred. Unknown mutations retain immutable intent/client ID and require explicit unchanged retry. Sending is not a delivery/read confirmation
- Account messaging now includes start and current-history controls, image review composition and typed card actions while retaining the existing native list/history/text/image-preview components. Missing native picker and transport grants are visible as unconfigured
- Unknown-intent owners are retained for their exact account/epoch/conversation in AppSession memory. This package does not claim crash/relaunch durable upload reconciliation or cross-epoch anti-replay storage. Live deployment requires an approved durable recovery policy; no server reconciliation or upload-idempotency endpoint is invented
- Swift compiler, Xcode target membership, Apple SDK availability, simulator/device UI and permissions: **NOT_RUN**. No runtime parity claim

## Verification

`python tools/check_im_expanded.py`: source/structural assertions only

`python tools/check_swift_syntax.py <changed Swift files>`: supplementary Tree-sitter parse only, not typechecking

Authored XCTest cases cover exact form paths/fields, source route/location payload, upload consent binding/MIME/size gates, response envelope, stale refresh generations, account/epoch mismatch, unknown outcome retry identity and untrusted review cards. UI tests have the described DEBUG host fixture branch installed. Tests are synthetic; no real messages or uploads were performed.
