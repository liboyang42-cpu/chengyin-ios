# P075 recommendation navigation

Loaded insight recommendations now have typed read-only destinations. Topic cards use the final response's `topicId`, open the existing merchant recruitment reader, and place the uniquely matching loaded topic first with a focus label. A missing or duplicate target produces an explicit unavailable message and never matches another topic by display name. Partner cards use only `memberId` for the canonical public merchant profile. `merchantId`, generic `id`, names and AI-generated route strings are not substituted for that owner identity.

The authorized workbench supplies the source merchant ID and operations-reader scope. This origin is independent of recommendation target identities. Recommendation controls are enabled only after the matching insight read completes for that origin, session and surface. The callback rechecks the whole insight snapshot, session and current origin; selection is cleared when origin/account scope changes. The host factory checks the current operations-reader scope again. The recruitment destination also compares its freshly authorized merchant ID with the source merchant ID before rendering. The public profile reuses the existing read-only scoped merchant reader so a later scope change cannot complete an old profile read.

The three legacy AI suggestion string tokens remain an explicit whitelist. The destination enum adds a typed associated recommendation case, while its existing `rawValue` initializer still accepts only those three suggestion tokens; recommendation URLs/IDs are not parsed from model text. The existing `allCases` value is retained as the three parseable suggestion choices. The navigation factory receives validated positive JavaScript-safe IDs through native values. No openURL, new endpoint, new AI generation path, write or entitlement is introduced. All service and AI/settlement grants remain unchanged and off by default.

The focus uses only the current loaded recruitment list. It does not claim the list is complete, query another scope, automatically apply to a topic, or create a new recruitment entry. This increment adds host/category/reason context when available, but does not alter date formatting or time-zone rules.

## Exact source

The same saved construction plan SHA-256 `eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133`, P075 paragraphs 1771–1774, lists recommended topic and partner navigation. The caller calls this saved file v9; its cover still says edition 8. The plan remains unchanged.

Private repository `liboyang42-cpu/chengyin`, commit `ce61c0bbace743ff835cb297ef41c89b52181636`, was read only; no private source file is copied into the candidate.

- `chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.js`, blob `b127d26613e45d1c670e7e5e5d47939c78115bb3`, lines 295–305: topicId goes to cooperation-center focus; memberId goes to canonical merchant home.
- `chengyinhub-xcx/pages/merchant/coop-center/index.js`, blob `7270d99e9aeca6500a013dd210ab490b529ecebe`, lines 95–97, 120–138 and 175–187: the existing marketing-home recruitment rows are located by exact ID and then open merchant topic detail.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantInsightServiceImpl.java`, blob `437e35e44e897d3d3af8eebc5d55bd24d3f65f22`, lines 169–185: profile has no source merchant ID, so it must not be guessed; 304–316: final topic rows use topicId and hostName; 351–361: partner merchantId and memberId are distinct, with memberId intended for canonical home.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ai/MerchantInsightResp.java`, blob `11b6457518fb1e5ae364c746b1336931197d96d4`, defines the existing profile and recommendation lists. No extra insight request was made during this work.

## Exact integration scope

Base tree `4f324aeb26386a4a6db274846d3a0d11113462d4`, after featured activity selection. Seven approved product paths: `Core/MerchantMarketingModels.swift`, `App/MerchantMarketingView.swift`, `App/NativeEntryLandingView.swift`, `App/MerchantContentViews.swift`, `App/MerchantHomeView.swift`, and new `Core/MerchantInsightRecommendation.swift`/`App/MerchantInsightRecommendationRows.swift`. MerchantHome has only the current-origin argument hunk; NativeEntry and Content have only the recommendation factory/focus hunks. Apply shared-file hunks to the aggregate candidate; do not overwrite the full files. Public merchant home/status files, AppSession, service/coordinator implementations, default grants and backend U2 are unchanged.

Merge six unique bilingual entries and register the new files centrally. The focused localization check supports both the isolated fragment state and a fully merged catalog with exact per-key equality; a partial/conflicting merge fails. No UI method, timing budget or CI timeout changes.

## Checks and limits

Seven focused Python checks passed. Seven affected Swift files parsed cleanly. The eighth file, MerchantHomeView, retains a pre-existing Tree-sitter grammar error on the unrelated Label/icon trailing-closure region; an exact-base probe reproduces the same diagnostic one line earlier, and that region is byte-identical. This is not a Swift compiler pass.

The legacy `tools/check_merchant_marketing.py` could not run because its required external `app-audit/lib/data/api/merchant_api.dart` is absent. It fails before executing its assertions; no Flutter checkout was fetched or fabricated. The new checks and unchanged service/coordinator hashes provide bounded local evidence only. Ten Core XCTest cases are authored but unrun. Apple compilation, navigation/UI/accessibility runtime, aggregate checks and live acceptance remain deferred. No prior merchant feature suite was rerun.
