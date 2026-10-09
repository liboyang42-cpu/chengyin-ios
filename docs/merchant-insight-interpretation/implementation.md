# P075 opportunity and problem interpretation

The existing AI interpretation now displays its returned opportunity and problem text with separate labels. MerchantMarketingInsight projects only actual nonblank strings, retaining exact returned text. Missing/null/numeric/array/object values do not become invented advice. Both paragraphs use Text(verbatim:) and have no buttons, links or route parsing. The existing finite AI suggestion destination parser remains unchanged.

The inserted paragraphs require a matching loaded source merchant/read scope and insight, a nonnil current service scope, and no pending reload. They share the existing low-sample notice beside the interpretation. Existing summary, audience rows, generated time, AI-error degradation and read-service behavior remain unchanged. These checks bind the new presentation to the current response; runtime invalidation timing has not been measured.

## Evidence

Plan: Questify城瘾全面改革施工计划.docx P075 paragraphs 1771–1774 and PA10. Document SHA-256 eb23c8aefc22954bcd6f73ef800c32b763e7f8c4e3d4c68b0a0956756fd50133.

Reference source: liboyang42-cpu/chengyin at ce61c0bbace743ff835cb297ef41c89b52181636. No private source implementation is copied into native product files.

- chengyinhub-xcx/pages/merchant/marketing/ai-insight/index.wxml, blob 7dc487b2fd50d781190384c827474498e10e8bd5, lines 158–166: low-sample context, summary, opportunity and problem.
- chengyinhub-system/src/main/java/com/chengyinhub/business/domain/vo/ai/AiMerchantInsightResp.java, blob e72fe94febc4d0fb01f9fa4447f709e5163137b3, lines 15–22 and 47–52: summary/opportunity/problem are String response fields with ordinary getters/setters.
- chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/MerchantInsightServiceImpl.java, blob 437e35e44e897d3d3af8eebc5d55bd24d3f65f22, lines 123–145: existing AI response assignment, low-sample summary handling and separate failure degradation. No extra AI call is added or executed.

## Integration and checks

Base tree ae67f6a20233d01cbda5f0c252839c7d6667cad4, following the attribution package. Two product paths: Core/MerchantMarketingModels.swift adds strict optional projections; App/MerchantMarketingView.swift inserts the two paragraphs into its existing AI section. Both exact hunks are supplied separately; preserve aggregate changes. Two bilingual keys are supplied as a fragment for central catalog merge. No new product Swift file needs project membership; central tooling may still regenerate test membership according to its existing workflow.

Actually run: three focused Python source/connection/localization checks and three Swift Tree-sitter parses. Four Core XCTest methods are authored but unrun. Swift/Apple compilation, simulator UI, Dynamic Type, VoiceOver, runtime scope invalidation, aggregate and live acceptance are not run. Outer freeze artifacts record whitespace, protected comparisons and exact-base replay. No AppSession/service, permission, new endpoint, AI invocation, UI budget/timeout, live save, deployment, commit or push change.

The first shared clone hit Git alternate-store depth before a checkout existed. Recovery used a direct shared clone of the frozen 73e source plus hard links to 219 immutable incremental Git objects. Prior/frozen candidates were not changed, and exact-base replay is the content acceptance check.
