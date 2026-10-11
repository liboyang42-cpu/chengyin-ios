# Merchant registration availability editing

## Independent baseline

Actual upstream / exact preimage: `41571fed5c27d4766d0bebb02e2800d798f1edbd`. No unsubmitted dependency on batches1–11: only merchant Content paths and newly dedicated Core/App/test/localization files change. Existing shared Content files must still be merged incrementally into a newer combined tree, never overwritten with standalone after-images. Previous eleven archives are immutable.

## Concrete source, not a proposed API

MASTER v10 W05.2 requires operating-time constraints; W06.6 describes actual fulfillment availability; merchant responsibilities225–226 retain the brand-center boundary. The exact implemented Mini interaction is `pages/topic/merchantapply/index.js:439–518,566–590`, SHA `ba42feac177669bbc704eb8c94d162341a7a9033`, at `f1fe895f34c3664783aafd6145cf93e0de15878d`: inclusive date range, daily same-day time range, and existing registration update JSON with startDate `00:00:00`, endDate `23:59:59`, cooperateDate `HH:mm-HH:mm`.

The exact update contract is:
- ApiRegistrationMerchantController156–172, SHA `f92d1066db7998b19d8670e193207dea5affb368`: existing POST `/api/registration/merchant/update`, PROJECT_MANAGE, authenticated merchant-owner resolution. Existing `/info?id=`181+ is the readback path.
- RegistrationMerchantDTO, SHA `0a5d824ed43772aca8102bba1942b70c0e7740a2`: Date startDate/endDate and String cooperateDate. This is the actual input DTO, distinct from the similarly named MerchantRegistrationDTO.
- MerchantRegistrationEditServiceImpl68–95, SHA `94d499c5d58d4b5765a17365dfb79de46c016ceb`: whitelists the three fields, checks ownership / topic not started / review eligibility, uses conditional state update. Rejected applications re-enter review on the backend.
- CmsRegistrationMerchantMapper.xml210–240, SHA `1fa1ada71832d6856f5ca8fe8aea7b8faf325ec8`: non-null patch values update start_date/end_date/cooperate_date; null omissions preserve originals. Read mappings21–23 return those fields.

## New flow

Existing registration detail → Edit → Choose dates and daily hours. Source values remain visible as received. A separate sheet buffers both days and daily times, supports Cancel, Apply and Restore saved availability. Unknown/missing source receives an explicitly labeled proposal, never an automatic edit. A recognized unchanged source is omitted rather than reformatted. Existing off-five-minute source values remain selectable; no silent rounding.

Apply requires real Gregorian dates, inclusive end day on/after first day, and same-day end time after start. Calendar controls use a fixed UTC carrier solely to extract day components. The payload follows Mini civil strings without converting dates into phone-zone or server-zone instants. No overnight clock, deadline inference, duration cap, guessed capacity or clearing contract is invented.

Only the update command uses `fieldsIncludingAvailability`; normal fields and the creation contract are unchanged. A nil replacement omits all three fields. The immutable existing review now also shows human-readable original/new availability and the re-review boundary. Existing full registration update fields remain present; this is not a new three-field-only save endpoint.

After this new availability-changing update is acknowledged, the coordinator rereads the same registration ID with fresh existing authorization. Returned values become the source even when they differ from the submitted values. On failed readback, the old snapshot is removed and the consumed receipt is retained, preventing repeat submission. A dedicated read-only reload recovers without replaying the update. Unrelated registration edits retain their previous behavior. Account, source, draft, review, background and dismissal changes retire open sheet buffers.

## Existing enablement boundaries

The existing MerchantContentService has no production write capability enabled: `permitsWrites` still requires `injectedOfflineHarness`, an offline-marker transport and its journal. This increment adds no independent write endpoint, no new approval switch and no production configuration. It is usable for real authorized reads/local edits/review; save/readback is verified with authored injected-offline tests only, pending existing upstream production enablement.

A separate pre-existing status/audit mismatch was handed to root and remains unchanged: native accepts status0/2 with audit!=1, whereas the f1fe edit service permits (0,0) or (2/3,2), and also checks the topic start. This feature makes no eligibility claim and never bypasses the server gate. The existing synthetic fixture retains its legacy status values; it demonstrates this feature's request/readback behavior, not backend eligibility acceptance.

## Verification and registration

New runtime sources: Core/MerchantRegistrationAvailability.swift and App/MerchantRegistrationAvailabilityPicker.swift. Add the dedicated Core/UI tests and merge 27 English/Simplified Chinese localization entries using the integration fragment. No central PBX/catalog/CI modifications.

Authored 22 Core tests cover calendar/clock validation, off-step times, opaque source preservation, omission/restore, exact update keys, unchanged create, fresh-baseline conflict, existing permission/execution gates, authoritative same-ID readback, failed-readback recovery/no-replay, wrong-ID rejection, unknown-write lock and scope changes. Three UI flows cover cancel/restore, frozen review/save/readback, and background dismissal.

PASS: 20 focused source checks (13 new availability + 7 existing station-time checks), pinned Tree-sitter parsing of 10 Swift files, whitespace/reverse-patch checks, exact allowed-path before-images, and unchanged prior eleven archives.

Native XCTest/UI, Swift typecheck/compile, Xcode/simulator/screenshots, VoiceOver/Dynamic Type and real backend saves are NOT RUN. The selected dot environment has no `swift` or `xcodebuild`; source checks and Tree-sitter parsing are supplementary, not native execution. No real sensitive write, payment, reward or upload was performed.
