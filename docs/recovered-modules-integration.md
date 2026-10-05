# Recovered Play, merchant business/content and cooperation integration

Integrated locally on 2026-10-02 UTC. The input packages were already source-verified; this report describes the actual merged app, not the earlier isolated overlays. All runtime execution remains unverified.

## Mounted routes and boundaries

- Activity detail now mounts observed `SessionPlayRuntimeView` for journey and director, identified by the actual AppSession revision. Preference, summary, stillness and prefab destinations use additive session factories. No topic/activity ID substitution or hardware provider activation was introduced
- Account → Merchant retains the existing access reader and adds business, content and cooperation workspaces. Business reader/journal, content service and cooperation reader use the current signed-in session; unauthorized callbacks check captured identity and epoch before expiration. Business intent storage also includes deployment namespace
- MerchantContent → supply uses a typed bridge and Cooperation's own eligible-template read for PERK. Unknown/missing terms remain blocked, including active offers. Application, chapter and offer IDs remain distinct. Forms only preview local requests: no coordinator dispatcher, terms acceptance or financial action is mounted
- DEBUG fixture hosts are also excluded from production session restoration; all 230 authored UI methods are included exactly once across the existing six class-level shards
- Default production capability sets, dormant hardware providers, empty backend approval configuration, macOS 14 package floor and iOS 17 app floor remain unchanged

## Merge corrections

Applied only the hash-verified 31-entry Play extension manifest and additive module files. Shared AppSession, navigation, catalog and project files were merged, never replaced with stale snapshots. Play localization pairs were normalized into the existing catalog. Recovered runtime-interpolated localization keys were corrected to explicit dynamic-key lookup; computed Cooperation fallbacks now use the in-app environment locale. Supplementary module source checks were scoped to their module files after integration and validate dynamic-key prefixes against the catalog. Cooperation's catalog fragment is documentation only; its runtime strings are in Localizable.

The top-level type-name scan found no new duplicate types; the sole duplicate text declaration is the pre-existing mutually exclusive DEBUG/release ProjectEditServiceAuthority. No schema, production gate or test exclusion was changed to obtain passing checks.

## Verification of the final integrated source

- Authored Swift tests: **1,497 Core; 230 UI in 35 classes**. These are method counts, not executed XCTest results
- Six exhaustive UI shards: **39 / 39 / 39 / 38 / 38 / 37**
- **3,923 bilingual English/Chinese keys**
- Deterministic project/scaffold PASS: **452 App/Core/UI Swift files**, 416 app/core project sources, two runtime catalogs
- Python contract suite PASS: **271**, including 12 new integration regression checks
- Tooling unit suite PASS: **16**; pinned-parser advisory suite PASS: **14**
- MerchantBusiness module checks PASS: **14**; MerchantContent source/46-endpoint/catalog checks PASS; Cooperation static assertions PASS: **296**
- Existing ClubGovernance, SearchMap, Settings source/legal and Team checks PASS
- Focused pinned Tree-sitter PASS: **70 new/changed Swift files, zero diagnostics**
- Unfiltered whole-tree pinned Tree-sitter: **547 files, same 10 existing recovery diagnostics in six files**. MerchantHomeView's pre-existing split Label/icon syntax is one of these; the other five files are unchanged by this integration. No filtering or suppression changed the whole-tree result
- `git diff --check` PASS
- Swift compiler/test execution, Xcode builds, simulator/UI/screenshots, device/accessibility and live backend/provider acceptance: **NOT_RUN**, Swift/Xcode absent here

`recovered-modules-integration-manifest.json` records package-derived and shared integration file hashes. `ui-shard-inventory.json` is regenerated from the actual UI target. No remote repository write, CI execution, real account/provider/device action or deployment occurred in this integration.

## Still blocked separately

Apple compilation/typechecking and runtime acceptance require the approved Apple environment. Production activation additionally needs backend and permission acceptance, secure persistent journals for relevant Play operations, provider/device acceptance and source-authorized legal/financial actions. Unknown active-offer terms, missing source authorization evidence, source prefab artwork provenance and documented module gaps remain explicit blockers rather than guessed data or enabled actions.
