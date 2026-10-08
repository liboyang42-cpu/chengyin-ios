# Existing professional ticket meeting point

Bounded city-ticket authoring inside the existing ProjectEditTicketView. This is not a new publisher, map picker, coordinate converter, place-verification service or live publication activation.

## Verified source and gap

Private source pinned to `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`. Exact source captures and independently recomputed Git-blob hashes stay in the private review packet, outside this public repository.

- `chengyinhub-xcx/pages/publish/fabu/index.js` (`5b530a2f42df49f7e4b526a5626de4440252b85b`): `chooseTicketMeetingPoint` at 5134–5145 captures name, address and coordinates. `saveTicket` at 4970–4977 writes `meetingPoint`, `meetingPointAddress` and numeric `gatherLng`/`gatherLat`. Its shared `pickLocation` use is explicitly identified as GCJ-02 at 7072. Native does not copy mini's zero-as-missing coercion: zero is a valid coordinate component.
- `TopicCreateDTO.java` (`b0451d181b295dae6792eff3a3b35ca4143c90d9`) declares `List<ActivityTicketRequest> tickets`. `ActivityTicketRequest.java` (`e7f46b370fc5c049a657f285d962d6c548595335`) and `OmsTicket.java` (`4affc89834a0f6642e3b3cd53109461c1613768c`) declare the meeting-point address as String and coordinates as BigDecimal.
- `CmsTopicServiceImpl.java` (`28828abb5070e72bd5ff0bcde2a7743c5d8a66fb`) `saveTickets` at 5247–5311 copies the DTO into OmsTicket, validates the ticket, and either inserts it or calls the scoped rebuild operation.
- `OmsTicketMapper.xml` (`393727b5eb497ed81bd661d6ee76cf7f4387ac24`) maps these columns for readback and explicitly replaces `meeting_point_address`, `gather_lng` and `gather_lat` in `updateTopicTicketOnRebuild`. Its existing ownership and inventory conditions are unchanged.

At native baseline `343fba15286e60d3ceddbbe1c1738d6e4cc8afd3` (tree `e562555019d9719c3abafe0d77741c7b43a750f0`), the ticket form exposed only a meeting-point name. Numeric coordinate readback was passed through a string-only helper and became empty, the address was not included in the full ticket payload, and edited coordinate strings were sent as strings. This increment closes that bounded authoring/readback gap.

## Behavior

The existing city ticket form opens an explicit meeting-point sheet with name, optional address and optional paired GCJ-02 coordinates. A name is required to apply. Coordinates must both be absent or both be finite decimals within longitude −180…180 and latitude −90…90. Zero and boundary values are valid. No device location or map provider is requested, and coordinates are never converted or verified against a physical place.

Apply changes only this ticket in the current working draft. Cancel, opening, no-op apply and stale callbacks perform no draft or storage write. The existing parent autosave, local-save, restore and immutable review flows continue to own persistence. Apply is not a saved/published success acknowledgment. The read-only summary and frozen submission review share one source-aware projection.

Each opening binds controller and host identity, account/epoch, draft identity, editor incarnation, structural revision, exact draft bytes and monotonic mutation revision. Removal/reordering, same-byte replacement, ABA changes, restore/discard, navigation retirement, a replacement host, mode/scope change or pending/uncertain operation invalidates the opening. Duplicate ticket IDs cannot open. Queued Apply and old dismissal callbacks cannot act on a new presentation. The existing uncertain chapter-removal storage freeze remains intact and blocks this editor too.

No new required stored fields are added. The existing ticket localMetadata retains meetingPointAddress and source values. Numeric metadata from older local envelopes is used when the old string-only decoder left coordinate fields empty. Explicit coordinate clearing stores null, so old numbers cannot reappear. Untouched missing/null values stay distinct; unrelated metadata and ticket identity remain unchanged. Known source types are String/null for names/addresses and Number/null for coordinates. Unsupported original types, including numeric-looking coordinate strings, remain preserved and read-only. Full submission is blocked rather than silently dropping or defaulting such values. Existing malformed numeric pairs can be corrected explicitly.

The full payload emits only the four existing meeting-point field names; coordinates are JSON numbers. Unknown siblings stay local. WHITELIST returns before all ticket fields and is not broadened. Free-exploration tickets do not gain this city-only editing entry; their existing valid fields remain carried through without introducing a meeting-name requirement.

## Verification and limits

Ten Core XCTest methods and nine app-hosted XCTest methods are authored for number/null/missing shapes, bounds and zero, unsupported-value retention, explicit clearing, older envelopes, exact readback/payload, target-only changes, no-op/cancel, cold restore and review, stale/ABA callbacks, host replacement, account/epoch, WHITELIST, duplicate IDs, existing uncertain-storage freeze and unknown submission.

The companion Python checks are structural contracts only. Tree-sitter is supplementary syntax parsing, not Swift typechecking. Apple compilation, Core/AppUnit/XCUITest execution, simulator/device rendering, accessibility and live API/database acceptance are NOT RUN in this Linux workspace. No existing AppUITest is changed. Root integration owns generated project and localization-catalog regeneration. All production capabilities remain off; no push, deployment, backend change or real record write is included.
