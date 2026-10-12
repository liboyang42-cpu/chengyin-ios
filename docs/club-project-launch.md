# P045: Create a Club-scoped local project

## Normal user flow

The existing ClubDetail owner/AppSession block now has one direct entry after the AI-design row. The new page freshly reads the exact Club and requires ownership. Choose city navigation or free exploration, or cancel without opening any editor. Each choice reads ownership again before constructing the real existing AppSession.projectEditor(product:) and ProjectEditView. The seed is the existing ProjectEditDraft defaults with only product and clubID selected. Opening the editor does not submit or publish anything. Close/swipe the editor to return and recheck ownership; Back/Cancel retires queued reads and selections.

The ordinary editor owns all local-save, restore/discard, review and submission logic. No AppSession, ProjectEditModel, coordinator, storage or service changes are included. If an old local draft exists, its existing restore/discard UI remains authoritative and incomingSeed stays pending; this entry does not delete or silently replace it. A restored older draft may retain its original Club until the user explicitly applies the incoming new draft. The entry explains that distinction. The existing editor's first-point/starter flow is retained; this packet does not implement Mini's automatic initial continuous-point-picker presentation.

## Evidence and contract

Unique MASTER-v10-extracted-text.txt P0451652–1655, onCreateTeam. Mini f859cd6e2618f618a53f5cd33949259828e86313 detail/index.js blobb49b5fb14caf49d47e971cd93ffd73cd94d8e044:2402–2417 opens two choices and navigates fabu?clubId=...&mode=1|2;2604–2631 handles open/cancel/selection. detail/index.wxml blob033ac08d82e76b8b92853b7eda9b4c65a7ce7804 binds onCreateTeam. Source also permits canManageActivities; this packet is intentionally owner-only under its approved scope.

Existing ProjectEditProduct.city=1/freeExplore=2 and ProjectEditDraft.clubID are reused. Existing AppSession.projectEditor(product:) returns the current retained coordinator. Actual ProjectEditView receives the captured coordinator, session revision and seed; no fallback demo/dormant callback is substituted. Core context captures Club reader object, identity/epoch, ClubID/ownership, configured-read flag and projectEditorContextID. A presented editor additionally captures the full ProjectEditSession, including storageNamespace/viewer/configuration revisions. An unavailable or mismatched project session cannot be presented.

## Lifecycle and authority

Every async owner read has a visibility permit and latest-request nonce. Wrong Club, owner loss, account/epoch changes, reader replacement, project context changes, cancellation or leaving cannot create a valid target. Rapid selections only retain the newest successful mode. A changed full editor session hides the destination. Old-account dismiss/retry callbacks cannot dispatch a new old-context read. Refresh removes any old target before reading. The new launcher never calls project preflight/submit/confirm/publish, does not bypass existing write grants and never changes another role's authority.

One source-flow limitation is explicit: the entry proves owner/Club/product handoff, not new publication permission, a new independently named draft bucket, or full Mini destination parity. Existing retained-editor/restore behavior remains unchanged and is covered by authored integration tests. Actual editor rendering and local persistence still need Apple execution.

## Base and integration

Actual5dd3e53c1de104735b26d75811cb4ff46b2a340f + sealed17→18 exact patches, with before/after ClubDetail hash chain in START.json. Composite tree5c7662504f5720285b32617e869764655c7dfe73; ClubDetail preimage blob33f5993650b342920690f623f109e44750be7f49. The only shared edit is one new Section/NavigationLink line; original AI, invitations, progress and all other code remain byte-identical. No other batch dependencies.

Central fragments register4 new Swift source/test files and8 bilingual keys. Complete before/after/delta/manifest/evidence are in the packet. Prior19 packet hashes remain unchanged. No PBX/catalog/workflow or remote edits.

## Checks

8 Core and12 AppUnit tests authored: exact products/defaults/ClubID, owner/session fences, stale/late/canceled reads, return refresh, real ProjectEditModel seed application, existing restore preservation and full editor-session replacement. All20 Swift tests, Apple build/native UI/runtime/typecheck/live backend are NOT_RUN because Swift/Xcode are absent. Executed evidence consists of focused structural checks,12 existing governance contracts, two exact Mini blobs with actual choice-sheet method oracle,5 Swift-file Tree-sitter parsing and patch reconstruction checks. These are not production acceptance.
