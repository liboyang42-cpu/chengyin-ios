# Customer first-page empty-result recovery

The CRM directory is an existing module in `docs/merchant-business-module.md`. This increment closes its missing empty-result recovery behavior. Previously a nonempty segment-count summary could suppress the native generic empty message entirely. Search, group and advanced-filter results did not offer the source-specific recovery action.

## Behavior

The native first-page customer response now has seven distinct empty presentations:

- Search within a group: view all groups, retaining the keyword and advanced filters.
- Search across all groups: clear only the keyword.
- Advanced filters: clear only tag, source type and source dates, keeping the selected group.
- A group with no other narrowing: view all groups.
- Missing, malformed or negative overall count: statistics are unavailable; reload.
- Positive overall count but no returned rows: list is unavailable; reload.
- Explicit zero with no active narrowing: honest no-customers text.

The choice uses the current response's `segmentCounts.all`, never a stale count or a sum of other groups. Source-like numeric and numeric-string counts are recognized. Invalid/nonfinite/Boolean/structured values stay unknown and never become zero. Populated lists, later-page Previous/Next navigation and noncustomer domains stay unchanged.

The native form has an explicit Apply step. Incoming applied filters now initialize its fields. Recovery is disabled while those fields contain unsubmitted edits, and the callback checks this again before changing anything. It also rechecks the current scope/authorization-bound coordinator, exact response snapshot, query, failure and busy state. Recovery changes only the selected source filter fields, clears stale selected customer IDs, returns to page one and invokes the existing read-only reload. Every existing request/authorization/mutation implementation is unchanged.

This adds no cooperation navigation or fake call-to-action to the true-zero empty case. No new endpoint, contact/clipboard/export action, payment, permission, provider, persistent state or backend work is introduced.

## Exact mini source

Pinned private ref: `liboyang42-cpu/chengyin@ce61c0bbace743ff835cb297ef41c89b52181636`.

- `chengyinhub-xcx/pages/merchant/customer/index.js`, blob `89859d7d4b55253409a952b4ee13f4d756c3737a`: lines 355–370 scope each clearing action; 483–502 derive empty text from the current returned counts; 527–583 specify search/group/advanced/statistics/list-empty distinctions.
- `chengyinhub-xcx/pages/merchant/customer/index.wxml`, blob `afa7ac2fbfa95ea1aac01d9bb6ba8e1e91ea8928`: the first-page empty component binds its title, description and recovery action.

The source was already verified for this task series and was not fetched or audited again. No private-source files are included in the native increment.

## Integration and unfinished execution

Base tree: `73e081ad4a1f3524f803ba6d9dac8806b745e880`. This patch is independent of the earlier contact-summary increment. It edits `App/MerchantBusinessViews.swift`, while contact edits `App/MerchantBusinessRecordViews.swift`.

The added exact-inverse helper strips only the pinned new customer-empty layer before all previous merchant Home/aftercare/settlement/customer/roster/review guards. It verifies the full original file hash and rejects changed or unrelated bytes. Existing historical tests remain unchanged except for invoking this layer.

Root should add the 19 unique keys in `Resources/MerchantCustomerEmptyRecoveryLocalizations.fragment.json` and regenerate the project normally. The shared catalog, project, CI, AppSession, Muse-reserved paths and backend/U2 are not edited. No UI test method or timing estimate is added.

Eleven Core XCTest cases are authored for action precedence, filter preservation, missing counts, real zero, late-page exclusion, unsent drafts and refresh replacement. Only 8 focused source checks, the 25 existing merchant-boundary checks, and supplementary parsing of four Swift files are run here. Full aggregate checks, Swift compilation/XCTest, Apple UI/accessibility and live-backend execution are intentionally left for the consolidated verification stage. Source parsing and inverse preservation are not runtime acceptance.
