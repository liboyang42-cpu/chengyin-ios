# Merchant refund aftercare progress

## Delivered scope

The existing authorized merchant aftercare detail now shows three separate facts: platform handling, merchant opinion and platform-confirmed funds outcome. It also shows recorded request, merchant responses and platform handover, plus the order's refund-policy snapshot. A merchant agreement is never presented as a completed refund. Missing amount and missing timestamps remain unknown.

This is an existing-detail read presentation. No endpoint, permission, payment, refund, award, redemption or evidence upload is added or enabled. Current respond/review controls retain their existing permission and fresh-snapshot checks. Signed evidence addresses are not copied into the progress projection, fetched or displayed. Evidence presence/unavailability is shown honestly; image preview remains unsupported in this slice.

## Source evidence

Backend and mini-program contract revision: `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/merchant/aftercare/detail/index.wxml`: independent platform/opinion/funds rows and handling-record destination. Blob `c09e968f2d70c8f50875f1bc5b6fd1b3538837c2`.
- `chengyinhub-xcx/pages/merchant/aftercare/detail/view-model.js`: `shapeAftercareDetail`, `buildAftercareTimeline`, `shapeResponse`; platform outcome is confirmed only for `processing === 'REFUNDED'`. Blob `f47577fd13b3800ab2f821076418e277234326ed`.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/MerchantAftercareDetailVO.java`: existing `createTime`, `platformTakeoverAt`, `refundDeadline`, policy and response fields. DetailVO itself does not emit a `refunded` bit. Blob `08d65d955392683bbbd48b93a9e381b168d990be`.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/MerchantAftercareResponseVO.java`: role-only response identity and `NONE/AVAILABLE/UNAVAILABLE` evidence status. Blob `21939cb11620919c120f8a1fbb14a5c0a1221b4d`.
- `chengyinhub-framework/src/main/java/com/chengyinhub/framework/config/ApplicationConfig.java`: Jackson explicitly serializes in `Asia/Shanghai`. Blob `8012b0f83d7572ec10e9f617b7a0daa794721227`.

Native read path remains `MerchantBusinessQuery.refund` → `api/merchant/aftercare/detail?refundId=...` → `MerchantBusinessService.document` → immutable `MerchantBusinessDocument.payload`. The transport preserves the real payload. The projection is validated at that document boundary and rendered only inside the existing current authorized snapshot. It does not replace the mutation baseline or retain its own data after dismissal.

Master reform plan W06/W07 preserves historical order/aftercare reads; W11.8 requires the support handling timeline. The pre-change native refund field list omitted `platformTakeoverAt` and a separate funds result, while responses were generic field rows.

## Time rules

Latest user direction: ordinary times follow the phone time zone; cutoff times use Beijing time.

- Source bare timestamps are strictly parsed with the verified `Asia/Shanghai` Jackson contract into `Date` instants. Invalid nonempty values reject the document rather than inventing a time.
- Request/response/handover times display the full date and UTC offset in the current phone zone. The view refreshes its zone on appearance and `NSSystemTimeZoneDidChange`, without refetching or altering the snapshot.
- Refund deadline remains explicitly labeled Beijing time, independent of the phone zone.
- Missing times remain unknown. No 24-hour countdown, refund ETA or synthetic platform-approval timestamp is inferred. Response source order is preserved; recorded handover is inserted by known instants.

## Validation and integration

Authored Swift tests cover all seven processing states crossed with the three merchant opinions; amount null/zero/negative; duplicate/cross-refund response rejection; invalid times and field types; unknown policy retention; evidence metadata without signed URLs; exact read adapter; dismissed/cancelled/account-changed reads; repeated refresh with an older late reply; phone-zone date rollover, zone change, DST spring gap and repeated autumn hour.

Python contract checks verify real host integration, existing lifecycle fences, immutable read-only projection, exact state separation and bilingual fragment completeness. These are structural checks, not executed Swift behavior.

Swift, XCTest, Xcode build, simulator, physical-device and accessibility visual checks are NOT_RUN in this Linux workspace. New Swift files and tests need the normal project generator/target membership integration. Merge the additive localization fragment into the main catalog through the integration owner. This patch does not edit the PBX project, main localization catalog, CI or app composition/session.

The merchant Home R1 static guard hashes the whole shared `MerchantBusinessViews.swift`. Its strict inverse adapter must account for the independently approved aftercare insertion before applying the unchanged Home hash checks. Any adapter must keep the original Home payload/hash and source-boundary assertions intact.

## Recorded verification for this candidate

- Merchant-focused Python suite: 131 tests, 128 passed, 3 explicit external-source skips, zero failures. The three skips require the optional Flutter checkout and are not source-parity passes.
- Tree-sitter Swift parser 0.7.3 / tree-sitter 0.26.0: all five changed/new Swift files parse without ERROR or missing nodes. This is syntax-only, not typechecking.
- 17 new Swift XCTest methods authored; zero executed here.
- `git diff --check`: passed.
- No push, production API request, real payment, award or redemption performed.

## Master-plan progress entry

W06/W07 merchant aftercare: native existing detail now consumes the source-backed refund read contract and exposes independent platform/opinion/funds states, recorded handover and responses, evidence metadata availability, and immutable order-policy snapshot. W11.8 support timeline parity advanced for this existing merchant refund surface only. Ordinary record times follow the phone zone; the refund deadline is explicitly Beijing time. This is a code candidate with offline structural/syntax evidence, not full W06/W07 completion or live operational acceptance.

Still unverified: Swift typechecking and all authored XTests, App target/resource integration and build, simulator/device visual/accessibility/clock-change behavior, authenticated real-backend acceptance, and signed-evidence preview. No MySQL transaction/concurrency or payment/refund settlement claim is made by this read-only slice. Existing backend authorization and production capability gates remain unchanged.
