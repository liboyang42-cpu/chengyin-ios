# Merchant project browser (batch 13)

## Scope and evidence

Actual iOS baseline: `49c68c6420270b0a0cc7ec8d18bc8561f329d796`, tree `4c834dfe65b9bf9b7a7d36ec238cb5fa9b42487c` (equivalent integration commit `221f2fb8f711349ff4d8947cc88809f2cb366878`). No unsubmitted batch dependency. Apply the incremental patch to the recorded shared-file preimages; never replace newer shared files wholesale.

Unique MASTER v10 extracted text, merchant responsibilities lines 225–226 and W05 lines 399–427, establish merchant facts/fulfillment and distinct merchant/theme authority. The concrete existing interaction is pinned Mini `subpackageA/pages/myproject/index.js` at `f1fe895f34c3664783aafd6145cf93e0de15878d` (blob `93bc7dc9e0846bd3dc2d5c8ec616830c01786fcc`): lines 10–18 remove identity/state filters and use type tabs; 55–58 specify rejected/draft/pending priority and the 200 cap; 168–239 fetch once and derive local tabs; 648–710 specify card role/address/pending-count facts. Templates already have their separate native browser and are not duplicated here.

The same revision's `ApiProjectController.java` (blob `b988d01794915296646a546a102eaeacfdcdb11c`), lines 195–211, 268–309, 350–390, 431–482, documents merchant-owner scope resolution, aggregated paging, and topic/activity card fields. `POST /api/project/my` keeps the existing multipart fields: `scope=MERCHANT`, `ownerType=all`, `state=all`, `type=all`, `pageNum=1`, `pageSize=200`. Existing `PROJECT_MANAGE` server authorization and native access guards remain unchanged. No new API, write grant, default-closed write capability, backend change or external action is introduced.

## Usable flow

1. Open existing merchant Projects. The loaded page defaults to Themes, with Themes/Activities tabs. A conditional Other tab preserves discoverability of an unknown future server kind without pretending to know its semantics.
2. Switch types without another read. Rejected, draft, pending are sorted first; each priority group and all remaining rows retain original server order. Missing/unknown raw state receives no invented attention.
3. See loaded-page-only count and the existing partial-page warning. An empty selected type is distinct from an empty collection and offers explicit switches to types containing loaded records.
4. Cards and existing summaries show source address, known organizer/fulfiller role and the exact optional pending-verification count. Only `bizType=activity` and `ownerType=merchant` expose that count. Missing is unknown; zero remains zero. Unknown owner/kind displays no guessed role. Neither acceptance text nor signup count can manufacture fulfillment facts.
5. Open the existing summary, return to the chosen type, or use the existing topic-only workspace route where already allowed. Type/source/context changes retire presentation leases. Source/session/merchant identity and fresh workspace checks remain intact. Source refresh/retry remains the existing explicit read flow; no local filter persists across a new account context.

## Integration and acceptance

Register Core `MerchantProjectBrowser.swift`, App `MerchantProjectBrowserControls.swift`, Core test `MerchantProjectBrowserTests.swift` (two XCTest classes), and UI test `MerchantProjectBrowserFlowTests.swift` in the existing targets. Merge the 13 English/Chinese entries from `MerchantProjectBrowserLocalizations.fragment.json` into the central catalog through the integration owner; `pendingCount %lld` uses `%1$lld`. No central file is changed here.

Dedicated `--uitesting-merchant-fixture projectBrowser` is wholly synthetic, including 9 rows, total 205, unknown kind/state, rejected/draft/pending priority, and pending counts 2/0. Its read-count label measures fixture reads; it is not production telemetry. Three UI tests cover local tab changes/no extra reads, fulfillment summary/return, and old owner-fixture empty-theme recovery.

The new default Themes tab means any external UI automation expecting the legacy activity-only owner fixture immediately on entry must explicitly choose Activities or its recovery action. No existing production fixture payload is replaced.

17 Core XCTest methods and 3 UI XCTest methods are authored. They are NOT_RUN on dot because Swift/Xcode are absent; there is no simulator/device screenshot, native build/type-check, localization runtime or production/network acceptance claim. The focused Python source/fixture suite and selected existing guard checks are supplementary, as is tree-sitter parsing. Historical global/byte-inverse gates are not repaired or presented as native acceptance.

The package includes START, exact source excerpts, before/after files, binary-safe patch, SHA256 file manifest, integration fragment, targeted check logs, previous twelve archive hashes, and explicit PASS/FAIL/NOT_RUN summary.
