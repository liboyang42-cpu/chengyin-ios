# P111 complaint preparation, increment 19

## Delivered and not delivered

The new personal component can use the existing normally composed cooperation reader
to load the authoritative complaint topic selector. It supports retry, successful empty,
selecting a topic, five optional complaint types, reason and contact fields, validation,
and immutable local review followed by return-to-edit. It is explicitly a preparation
screen, not submission. There is no report button, transport, writer, case receipt,
clipboard, sharing, disk persistence, or claim that the platform received the content.
Leaving/back/closing or backgrounding clears the ephemeral draft. Ordinary read failure
retains local text but disables editing/review until a successful retry. Authentication
and configuration errors clear private text. Successful empty clears an old selection.

Normal host mounting is pending the registration fragment. The read path is already
composed and does not depend on blocked PlayerJourney or OwnedOrderReadApproval gates.
Production complaint submission remains deliberately disabled. Apple compilation,
native tests and actual account reads were not run on this Linux executor.

## Source and contract

Sole MASTER v10 P111 maps to subpackageMember/complaint/index. Pinned Mini commit
f859cd6e2618f618a53f5cd33949259828e86313 JS blob ce1f47668ee56f8980202079d860da2d6ed352e7,
WXML c43ed31c86ef77ba5617e8d24c42da0072a5b804. Source events: loadTopics/onRetry,
openPickerSheet/selectPickerOption/onReasonInput/onContactInput/refreshSubmitState.
Only the reason assembly in submit is reused; the submit action itself is not exposed.

POST /api/coop/complaint/topics returns data[] with topicId/topicName/registrationId.
Existing CoopFlowReading.read(.complaintTopics) sends its existing authenticated JSON
empty object. Only positive unique topicId values can be chosen; registrationId is not
projected. Missing/duplicate/malformed IDs fail closed. No order-age window, payment
status inference, or synthetic eligibility. Missing topicName displays localized Activity
plus the actual topic ID. The selector service is authoritative, not a permanent grant.

ApiCoopController pinned blob fba059433b3f6a23d4ef546a20ab11b8f3628254 and VO
92b4e066978dc235870916f8d1f94f01a4ce1ea0 confirm topicId/reason only for report. Reporter
and registration association come from server eligibility; status, fault, handler, and
compensation must never be client-authored. Filing freezes the target settlement, so
this feature does not borrow any read access as authority to file a complaint.

Mini reason text: optional Chinese type in 【】 + trimmed reason + optional newline
联系方式： and trimmed contact. Preserve these wire labels independent of UI locale.
JavaScript UTF-16 length and trim semantics are retained (including BOM, excluding NEL).
Reason minimum 5, raw input maximum 500, raw contact maximum 50. Native rejects overlong
input rather than truncating pasted content silently. Review is a plain value only and
does not build or dispatch a request. No private draft is included in diagnostics.

## Isolation and integration

All ten files are new on actual 5dd3e53c1de104735b26d75811cb4ff46b2a340f; no prior
afterimage overlay is needed. Existing CooperationFlow files, ParticipationSupportView,
AccountView, AppSession, PBX, catalog, router, and gates stay byte-identical.

Mount ProfileComplaintPreparationLink(session: session) in the AccountView Form via
the additive registration fragment. Its base5dd patch is also replay-tested against
after13 and after18's proposed public mounting. Preserve every prior package and central
shared-page fix. Register source/tests/DEBUG fixture and merge the localization fragment
centrally. The fixture uses synthetic IDs and callbacks only; never production defaults.

The controller captures the exact reader and full CoopFlowSession; every dispatch,
success, error, edit and review checks the parent lifetime plus that session. Singleflight
and generation fences prevent late completion after retirement. The normal link captures
sessionRevision and the owner and keys presentation to revision. No service is created.

## Separate submission blocker

POST /api/coop/complaint/report is an authenticated JSON {topicId, reason} write with
server eligibility, duplicate-case checks and settlement-freezing effects. The existing
CoopFlowService.dormantWritesEnabled is false in normal AppSession construction;
complaint.requiresSeparateEnablement remains true and protectedDispatch permits only
the established offline transport route. Nothing here changes those constraints or
manufactures approval. Any future production filing requires its own authorized protected
dispatch/composition, current eligibility, explicit full-text review/confirmation and
verified receipt/unknown-outcome handling. Pinned CoopComplaintServiceImpl.create returns
a Long case ID (blob caa085f23787a656cf25a66321c79ed21e3272b1 lines40–48), while existing
CooperationFlowService.swift114 requires object for complaint. That pre-existing response
mismatch is separately reported to root and not repaired here. This package does not
promise any submission path.

## Acceptance

Exact pinned Mini synthetic cases and Python source/mutation checks are reported separately
from authored Core/App/UI tests. Source inspection is not Swift execution. See package
DELIVERY and evidence for actual counts, source receipts, fragment replay, and NOT_RUN.
