# P056: Topic merchant/station list

## Ordinary flow

Club governance -> topics -> topicOverview -> the existing recruit link now renders the source-specific merchant list. It consumes the parent's real authorized .recruit snapshot, excludes OPEN recruitment slots, and displays each returned merchant and station in source order. Loading, permission/network/server failure, refresh/retry, and native Back remain the existing parent flow. Returning and reopening uses its existing read task. No new default-nil callback, fixture-only entry, service or command is introduced.

The scope is each node/station record, not unique merchants. The same merchant across two stations remains two rows; node IDs are never interpreted as merchant IDs or member IDs. Unknown names have explicit fallback labels. Exact state OPEN is excluded; unknown states remain visible and are not described as accepted or unconfirmed. Optional returned state is displayed verbatim. Missing nodes is malformed, not an empty list. Included node IDs must be positive and unique; provided root/row clubId and topicId must match the current scope.

## Source and contract

Unique MASTER-v10-extracted-text.txt P0561696–1699, loadMerchants/closeMerchants/copyPhone. Exact Mini f859cd6e2618f618a53f5cd33949259828e86313:
- pages/club/topic-detail/index.js blob5be9212843f38ce85bf43c4ab9ed5cf4ba3df5dd,786–826 open/close/load/buildMerchantRows,829–832 copyPhone.
- index.wxml blobc399d352d0fafe4e899bbaa8be2ed2956c26b159,472–496 list sheet, error/retry/empty and merchant/station rows.
- Existing .recruit POST api/club/recruit/overview fields clubId/topicId, permission club:content:manage. No broadening of that permission.

The new App gate requires the same reader object, signed-in identity/epoch, authorization generation, configured reader and accepted current read generation. The Core projection checks operation/scope and snapshot permission before existing validation. The component is stateless: no cached snapshot, selected record, asynchronous task or late route callback. Parent source fencing and visibility/refresh behavior are preserved byte-for-byte; this packet does not claim to repair parent reader lifecycle issues.

## Contact boundary

Mini copies a server-returned raw phone, only showing a mask. Existing native ClubGovernanceValidation.sanitize strips phone/mobile/phoneNumber recursively (146–154), so the authorized native contract cannot support that action. This feature never restores those fields, infers confirmation from their absence, substitutes masked text as a usable phone, or adds a dead copy button. It shows a neutral contact-unavailable note and the useful independent merchant/station list. This is not full copyPhone parity. Exact evidence and interface gap are in packet evidence/contact-read-handoff.md; any future contact capability requires a separately approved contract.

## Integration

Actual base5dd3e53c1de104735b26d75811cb4ff46b2a340f. Apply sealed14->15->16 exact patches; their GovernanceViews before/after SHA256 chain is in START.json. Composite treeafc1eb472e805d2e0acca5668307ec3d5b40dfd2; GovernanceViews blob7bf0e89e7c436df721cc7230fb8f535f4b82b677. Batch19 adds exactly two lines for one .recruit branch between .roles and .topicOverview. The existing roster/series/settlement modifications and all other branches/entry links/read logic are retained. No dependency17/18.

Central integration uses the registration fragment for4 new Swift source/test files and7 bilingual keys. No PBX/catalog/workflow edits. Before/after, delta patch, manifest, exact source copies and check scripts are in the delivery packet. All18 previous packet hashes are checked unchanged.

## Verification limits

10 Core +8 AppUnit tests are authored. Swift/Xcode, Apple builds, native UI/runtime/typechecking and real backend validation are NOT_RUN. Executable checks are focused Python structural checks,12 existing governance contracts, exact Mini source-function oracle and5-file Tree-sitter syntax parsing. These do not establish production deployment readiness or phone-copy support.
