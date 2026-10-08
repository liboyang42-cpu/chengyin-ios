# P033: one-way system notifications

## Source-backed user-facing change

Account → Messages → a source-confirmed system conversation (type `2`) shows a
one-way-notification explanation instead of a text field or send/retry button.
Its More screen keeps read/mute/unmute but does not offer image, route or location
composition. Existing message reading, history pagination and card details remain.

This closes the P033 `onInput`, `onSend`, `onPlus` and `onPlusSelect` affordance gap
identified against the master document's mini-program page. It does not implement
report/block/delete, automatic read marking, polling, or a new message transport.

Source inspected directly at backend commit
`ce61c0bbace743ff835cb297ef41c89b52181636`:

- [Mini-program chat](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-xcx/subpackageB/pages/im/chat/index.js),
  blob `920c922a1e8a6cb022e9560395474611d1b24cba`.
  `onLoad` sets `readOnly = type === 2`; `_canSend` requires ready, not disabled
  and not read-only. `onSend`, `onPlus` and `_sendMessage` reuse that guard.
  Type `3` official/customer-service messages remain eligible for the existing
  send gates. A missing conversation type in a newly started native chat is not
  treated as proof of system status.
- The native baseline decodes `2` as `MessagingConversationKind.system` but mounted
  `MessageActionComposer` and all `IMConversationControlsView` send sections for it.
  The native exact source tree is `e562555019d9719c3abafe0d77741c7b43a750f0`, also
  published as `343fba15286e60d3ceddbbe1c1738d6e4cc8afd3`.

This is a client presentation/dispatch gate for a known source type, not a new
backend permission boundary. Direct, official, group, unknown and metadata-less
newly started conversations still depend on all existing reader/writer/identity
and server checks; the policy does not grant them a new capability. Invalid or
mismatched conversation IDs fail closed.

## Retained and interrupted interactions

- Text Send and explicit Retry create single-use tokens synchronously in the
  current button action. Queued work consumes its token, then rechecks the live
  reply/history gate and appearance before invoking the existing coordinator.
  Disappearance or replacement appearance invalidates old queued work. A denied
  token cannot be replayed after authority returns.
- Expanded Confirm/Retry also binds the exact original mutation and appearance.
  System conversations can read/mute, but a retained send cannot masquerade as
  those operations or acquire a retry button. Unknown sends keep their original
  message ID/payload in the existing owner; no automatic retry or replacement is
  added. Dismissal does not claim to cancel an already-sent network request.
- Image selection/upload has its own visible child lifetime and rechecks live
  reply permission before its queued task reaches the picker or uploader. Normal
  navigation makes the controls parent disappear, so the active image child owns
  its own gate. Applying an uploaded image still creates only a local review and
  returns to the parent; it never sends the image automatically.
- A retained app-layer authority binds a lease synchronously while the history
  route renders. It does not publish or start work. Old closures consult that
  authority plus their exact lease, so replacement metadata, reader or readiness
  cannot rely on later lifecycle callbacks to block a queued action. Returning to
  an earlier policy produces a new lease instead of reviving the old one. Reload
  and terminal pagination failure also invalidate the lease synchronously before
  changing view state, closing the pre-render readiness window.
- History readiness now also binds the exact reader object in addition to account
  epoch and conversation. A replacement reader or revoked configuration cannot
  borrow an old loaded snapshot to enable reply actions. No source/epoch changes
  are made in AppSession or the composition root.

## Verification

Executed on dot's Linux computer:

- All native Python contract checks: 2,374 discovered, 2,327 passed, 47 explicitly
  skipped for optional unavailable source inputs; zero failures. These are
  structural/contract checks, not Swift execution.
- Focused IM checks: 41/41 passed, including 8 new reply-policy wiring checks.
- `git diff --check`: passed.
- Tree-sitter 0.26.0 / Swift grammar 0.7.3: all six changed/new Swift files parsed
  without recovery nodes. This does not prove type correctness.
- Authored: 5 Core XCTest cases and 19 App XCTest cases covering actual shipping
  UI owners, source type behavior, preserved read/mute, queued close/reopen,
  revoked-then-restored permission, account epoch change, duplicate dispatch,
  original unknown-intent retry, late text completion, image-child return, and
  retained callback closures across policy/read-source replacement without
  lifecycle cleanup.

Swift/Xcode compilation, XCTest execution, simulator UI screenshots, VoiceOver,
Dynamic Type, CN/US device acceptance and real backend acceptance: **NOT_RUN**.
No Swift or Apple SDK toolchain is available in this workspace. No real message,
image upload, payment, permission grant or production mutation was performed.

Apple acceptance should verify system notices with and without send configuration,
normal direct/official replies, read/mute from system More, English/Chinese large
text, Close/Back during queued and in-flight actions, unknown retry after reopen,
and image selection → upload → local review → explicit confirm.

## Integration ownership

Existing files changed:

- `App/MessagingHistoryView.swift`
- `App/IMExpandedViews.swift`
- `App/MessageActionComposer.swift`

New policy, matching Core/AppUnit tests, one contract test, this document and the
2-key bilingual `Resources/IMConversationReplyPolicyLocalizations.fragment.json`
complete the exact nine-path patch. The integrator merges that fragment into the
main catalog and regenerates the Xcode project. Shared catalog/project/CI,
AppSession, composition root and Core transport/coordinators are untouched.

## Deferred location-map gap

P033 `onLocationTap` opens a map, while native detail currently displays the
location's address/coordinates as text. The source chat copies `wx.chooseLocation`
latitude/longitude, and [the backend card sanitizer](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ImServiceImpl.java)
(blob `e53e2a0db0999c1d14c79d13b64313e7ecff5621`) bounds the numbers and emits
`name/address/lat/lng` without a datum/version. The available IM contract therefore
does not establish Apple-compatible coordinates. This slice adds no MapKit pin,
coordinate converter, device-location request or external map action. A verified
coordinate-system boundary is required before implementing that separate feature.
