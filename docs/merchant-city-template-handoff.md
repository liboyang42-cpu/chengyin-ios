# City-location game configuration handoff

Base: `077273784d7fed5397f84f17b2a659723f3f3b22`.

## Source and missing operation

The Mini city-node create page opens the full merchant template configuration page and consumes its `templateCreated` result before updating the local placement draft. Native placement previously had only an existing-template picker. This package adds that configuration-and-return journey as one feature.

Source reference: `95e499471eaa39c28f77d16125f0cc17b8c37123`.
- `chengyinhub-xcx/pages/merchant/citynode/create/index.js`: blob `1b639d5b7c43de7ff9edc97c3c1594db9a157aab`, lines 222–244.
- Matching WXML: blob `9a230b5383aa368dcd170662f46ee5ebc3e346a5`, lines 19–36.
- Album eligibility helper: blob `6c9b726c215f529c5337c037d8558f1ee778cedd`.

Private source originals remain in local delivery evidence, outside this product patch. This is not a separate filter, gallery rearrangement or duplicate placement form.

## Implemented behavior

- Open the existing complete merchant template editor at `.template(nil)`, retaining its image/assist factories, local controls, review, save gates and uncertain-operation journal.
- Register this exact new-template editor before accepting a return. A loaded unrelated existing template cannot impersonate its saved result.
- “Use saved game and return” requires a current positive ID, authoritative document/baseline/draft agreement, no dirty edits, no confirmation and no pending-save lock.
- Freshly read access for the same merchant, then refresh the parent's existing city-placement snapshot. Accept exactly one matching owned row and reject enabled album games.
- Replace only the placement template ID and mark that draft dirty. Preserve all other fields byte-for-byte, including coordinate formatting and address confirmation. Do not submit the location.
- Cancellation leaves the original selection intact. After a failed read, the placement-only recovery control restores the parent read surface without applying a saved ID. Missing rows and read failures offer read-only retry; no save is replayed. Account, parent snapshot, raw draft, editor identity, lifecycle and late-response fences reject stale returns.
- Background/disappearance ends this in-memory handoff. No new local persistence is introduced. Existing completed template writes are not undone when return is cancelled.

Malformed or unsupported advanced configuration fails closed rather than treating unreadable metadata as proven non-album. JavaScript truthiness for the actual `album.enabled` field is preserved.

## Required root integration

The delivery's `integration-proposal.patch` and exact anchor manifest are **NOT_APPLIED**. They contain only:
1. Optional return footer/cancel control in `MerchantOperationsDocumentView`, default nil for all existing callers.
2. Placement-only entry and atomic selection callback in `MerchantContentEditView`. Keep the entry mounted while reading. Protect the exact readback observation from delayed SwiftUI reseeding; do not wrap the entry inside the transient snapshot conditional.
3. Session-scoped factory and DEBUG fixture route in `QuestifyApp`.

Register the four Swift leaves in the app target and the new AppUnit/UI test files in their existing targets; Core and CoreTests use directory discovery. Merge the 17 English/Simplified-Chinese strings into the existing localization catalog. Existing shared files are not part of this leaf commit.

## Runtime boundaries and precise blockers

- Live template save is still gated by the existing `MerchantOperationsReading.canSave`, `saveTemplateReviewed(_:baseline:) -> Int?`, existing endpoint approval and pending journal. This package never enables it. Local configuration/cancel work without a live mutation approval; a new saved-ID return cannot be claimed until that pre-existing capability is available.
- Return uses existing `MerchantContentServing.load(.cityPlacement)` and its owned `api/template/my-list` page 1, size 100. If the acknowledged ID is missing from that read, selection stays unchanged. No new endpoint, pagination contract, synthetic row or ID is introduced.
- Production payments, rewards, uploads, deployment, DDL and permission configuration are outside this package.

## Validation

15 Python source-contract checks and supplementary Tree-sitter parsing cover the leaf and exact central preview. Native tests are authored: 12 Core, 13 AppUnit and 3 UI methods, including held read cancellation/scope/draft/lock cases, unknown-save locks, failed-read retry, album rejection, bilingual large text and local-field preservation.

Native execution: **NOT_RUN**. This environment has neither Swift nor Xcode/Apple SDK. Parsing and source assertions are not type checking, build, simulator or runtime acceptance.
