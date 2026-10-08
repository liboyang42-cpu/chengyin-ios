# Merchant public-transfer detail: progress and reference copy

## User-visible result

The existing owned batch detail now adds its payment summary, independent invoice state and a three-step payment timeline. The new Copy payment reference button rereads current merchant access and that exact batch before copying only the reference to the local device clipboard. It does not pay, refund, confirm reconciliation, update an invoice, unfreeze funds, redeem, or change any server record.

The existing batch fields and earning/adjustment rows remain intact. The added presentation is only in the detailed batch row with `merchant:finance:read`; list rows and unrelated detail kinds are unchanged. Missing/unsupported typed fields keep the existing generic detail without inventing a successful projection or a copy button. All existing production capability switches remain unchanged and disabled where previously disabled.

## Source alignment

Private source repository `liboyang42-cpu/chengyin`, exact revision `ce61c0bbace743ff835cb297ef41c89b52181636`; files were read through the connected repository tool, not inferred from the Flutter mirror.

- `chengyinhub-xcx/pages/merchant/ledger/batch-detail/index.js`, blob `44709510df68bbb1a9156dacaca9a74a99fecad5`: existing POST `/api/merchant/finance/public-transfer-batch-detail`, JSON batchId, copyVoucher, payment/invoice presentation and status-driven milestones.
- Same directory `index.wxml`, blob `23bea1a7f458a66deb06a1103daa8989b7545c10`: finance access gate, reference-copy action for a paid platform-to-merchant batch, earning/adjustment rows and progress.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/PublicTransferBatch.java`, blob `99ba3e6e64edc8433fd72b95da5556d9c97eac8f`: four independent axes, period, amount, paidAt and payVoucherNo. This DTO has no createdAt or confirmedAt.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantFinanceQueryService.java`, blob `b6ff358286d6b6df3855b8ef0a72bdacca924eb1`, publicTransferBatchDetail and toPublicBatch: merchant ownership lookup; PLATFORM_PAYS_MERCHANT / ZERO / MERCHANT_OWES_PLATFORM; malformed PAID evidence becomes PENDING with LEDGER_ERROR even if artifacts remain present.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/MerchantPayableBatch.java`, blob `707cb2e678502e5bd0bcedd972874e2714f7e656`: PENDING / CONFIRMED / PAID; NONE / ISSUED / RED invoice axis; FROZEN pauses reconciliation/payment without changing the amount or rewriting historical payment.

The native route, request shape, session reader and permission are reused as-is. No new endpoint, account, credential, capability, persistent store or production configuration is introduced.

## Truth and lifecycle behavior

- Timeline completion follows payment state. A date or voucher attached to PENDING/CONFIRMED never makes it paid.
- ZERO and MERCHANT_OWES_PLATFORM do not display the platform payout timeline. Negative money is not clamped or recomputed. Missing money remains unknown.
- LEDGER_ERROR suppresses the timeline and copying. Unknown payment/direction/hold values do not invent milestones. Unknown invoice values remain unknown, with original raw fields retained.
- Native PAID presentation/copy additionally requires a positive reported amount, a nonblank paidAt and a nonblank voucher. Incomplete PAID cannot produce copy success. Invoice and freeze state do not rewrite a historically valid payment fact.
- Generated and confirmed steps have no dates because the actual DTO supplies none. PaidAt is an ordinary event: both its existing batch field and timeline display the parsed instant in the current phone time zone, with full date, seconds and UTC offset. A system time-zone notification rerenders the same instant without a read or change to payment facts. Missing/malformed values show time unavailable, never a made-up date. No deadline, countdown or estimated payment date is added. Frozen next steps are shown on hold, following the backend pause semantics.
- Copy is user-click-only. Before the fresh read it requires a current detailed snapshot, finance permission, a valid paid batch, configured reader and scope. After the read it checks the same UI intent, scope, authorization generation, current snapshot, merchant access, batch ID and exact displayed projection.
- A fresh copy read uses the normal session reader's access/me then owned batch detail sequence. A changed merchant/grant/batch/reference, denial, cancellation, account change, navigation dismissal or replacement cannot copy. Repeated taps share one pending attempt. Old completions cannot clear a newer attempt.
- Final checks and clipboard write are synchronous on MainActor with no intervening await. Clipboard uses localOnly and a 120-second expiration; no clipboard read, provider call, universal clipboard transfer or diagnostic logging of references is added.
- Backgrounding, appearance disappearance, scope/authorization changes and changed displayed progress invalidate the UI intent. A previously queued click cannot restart after an invalidate/reopen.

## Integration boundary

Based on frozen native source published as `1161bf975172091f49ba6b33fe49ce515ff9eca4`, tree `0ed2ed6d6ac55a13e54fa2e7b6c1e6286776acfc`. The supplied publication/tree manifest and its 42 changed-file hashes were verified before copying the source. No local HEAD is represented as the remote publication.

Only one existing `MerchantBusinessViews.rowView` detailed-row call is extended with the reader/current-snapshot closure. The exact postimage is protected by a new single-hunk inverse before the existing aftercare inverse and Home inverse. All existing Home and aftercare assertions remain, with negative controls for changes outside the approved splice. `MerchantBusinessRecordViews` keeps the original fields and adds the detailed batch presentation.

Merge the 27-key English/Simplified-Chinese fragment into the main catalog and regenerate the project only in the integration step. This candidate does not edit AppSession, CompositionRoot, PBX, CI, main Localizable or another worker's files. It adds no UI-test budget.

## Verification

Local completed checks:

- 9 settlement source contracts passed (R1 adds live phone-time-zone wiring checks).
- Full `Tests/ContractChecks`: 2,261 tests, OK with 46 explicit skips. This is Python source/structure evidence, not Swift execution.
- Home access plus settlement exact inverse/negative controls: 19 tests passed; original aftercare presentation contracts: 5 passed.
- 13 native merchant-business checks passed separately. The unmodified legacy `tools/check_merchant_business.py` source-parity check fails because the optional sibling `../app-audit` Flutter checkout is absent. It is not counted as a source-parity pass; the exact mini-program/backend evidence above was independently retrieved.
- Supplementary Tree-sitter 0.26.0 / tree-sitter-swift 0.7.3: all 6 changed/new Swift files, zero diagnostics. This does not typecheck SwiftUI or Apple APIs.
- 17 Core XCTest methods and 11 App-hosted XCTest methods authored. Five R1 methods cover bare/ISO instant equivalence, explicit fractional/offset handling, cross-day phone zones, DST gap/repeated-hour offsets, live-zone reformatting, malformed/missing time, and unchanged paid/pending/copy facts. App tests inject an in-memory write spy and never touch the real clipboard.

NOT_RUN: Swift compiler/SwiftPM/XCTest, Xcode builds, simulator/device rendering, VoiceOver/Dynamic Type behavior, real clipboard, live accounts/backend and production transactions. Swift and Xcode tools are absent from this workspace. No push, PR, merge, deployment or real payment operation was performed.

## R1 timestamp correction and exact serialization evidence

R0 is preserved as a separate candidate. R1 changes only the timestamp presentation within the existing approved paths, and supplies an R0-to-R1 patch. The voucher-copy model, authorization predicates, payment state rules, endpoints, session reader and App-hosted copy tests remain byte-for-byte unchanged.

Rechecked exact ce61 files:

- `ApplicationConfig.java`, blob `8012b0f83d7572ec10e9f617b7a0daa794721227`, sets the Jackson time zone to Asia/Shanghai.
- `PublicTransferBatch.java`, blob `99ba3e6e64edc8433fd72b95da5556d9c97eac8f`, declares paidAt as an unannotated java.util.Date. The persistence entity's bare-format annotation is not on this wire DTO.
- `chengyinhub-admin/src/main/resources/application.yml` (`64b6ade229455a6902d3fcbb4d9a7abf16bd50b0`), `application-druid.yml` (`10db48f6fff2c493583d2a8cc9b3c90a991a4e08`) and `ResourcesConfig.java` (`b44407573918ea591ed10c8e16f4787923cc8f2d`) contain no overriding Jackson date-format configuration. The root POM pins Spring Boot 2.5.15.

Therefore the source-default shape is offset-bearing ISO, not an assumed bare string: [Spring Boot 2.5.15's mapper defaults disable numeric date timestamps](https://docs.spring.io/spring-boot/docs/2.5.15/reference/htmlsingle/#howto.spring-mvc.customize-jackson-objectmapper), and [Jackson's standard textual date serializer uses ISO with a numeric offset](https://fasterxml.github.io/jackson-databind/javadoc/2.12/com/fasterxml/jackson/databind/util/StdDateFormat.html). This is a source/configuration inference, not a captured live response.

The bounded paymentTimestamp adapter accepts this explicit-offset ISO form and the existing bare Shanghai compatibility form. It validates calendar components strictly with MerchantAftercareTime.parse, respects ISO offsets through the existing OrderLifecycleTime.date, and renders using MerchantAftercareTime.event. It does not add a global date rule, change deadlines, or use a displayed/parsed date as payment evidence. Offsetless ISO, impossible calendar values, missing/blank strings and malformed values produce no date. The raw server field remains part of the immutable equality checks, so a time-zone change cannot change copy authorization.

R1 local checks: 9 focused contracts, full 2,261 Python contract tests with 46 skips, and 4 modified Swift files parsed with zero supplementary diagnostics. All new Swift tests and device time-zone notification behavior remain NOT_RUN pending an Apple toolchain/CI.
