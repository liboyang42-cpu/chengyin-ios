# Merchant template: local participation plan

## Bounded W05.2 increment

The existing merchant template editor can explicitly add three structured planning fields: participation time in whole minutes, a maximum participant count, and an explicit employee-required / no-employee-required choice. The group starts empty, with no guessed staffing default. Both counts require positive ASCII decimal integers representable as Swift `Int`; whitespace is trimmed for validation and review, while original edit text is retained.

This is an optional, session-local planning group. Legacy templates are still readable/editable without it. Once the user adds the group, all three fields must be completed before the existing Review action enables. This increment does **not** complete W05.2 mandatory server-backed authoring; business windows, noise/filming, accessibility, offline fallback, failure exit and reward rules remain outside its scope.

## Existing entry and lifecycle

Merchant workbench → private template catalog → existing or new template → Participation plan (local). All edits go through the existing coordinator, dirty-state navigation guard and draft identity. Review freezes the full template and separately labels the three fields as local planning facts. Cancel retains edits; editing invalidates an old review; explicit removal restores the legacy template; discard, reload and leaving remove the session-local group. No persistent local store was added.

The form and review explain that these fields are not sent or saved to the server. **The whole draft cannot be submitted while this group is present**, even if an injected reader has write approval. The confirmation button is disabled, the coordinator refuses confirmation before reading/sending, and `previews()` rejects such a draft before the dormant service can construct or send requests. There is no success/save label for the group, and its fields are not silently omitted from a submitted template. Removing the group does not grant any new save permission.

## Evidence and authority

The MASTER W05.2 requires participation time, headcount limit and employee involvement among a broader set of operating/safety requirements. The increment adds these as merchant-entered planning facts, not AI-authorized or server-confirmed facts.

Exact preserved Mini source at backend commit `f859cd6e2618f618a53f5cd33949259828e86313`:

- `chengyinhub-xcx/pages/merchant/citynode/create/index.js`, blob `1b639d5b7c43de7ff9edc97c3c1594db9a157aab`: routes merchant configuration to `/pages/publish/temp/index?from=citynode&scope=MERCHANT`; comments retain the existing merchant template submit endpoint and safety checks.
- `chengyinhub-xcx/pages/publish/temp/index.js`, blob `76e39df5c326aaf029bda8da21562072fb352553`: form `players`/`duration` at lines 335/339; non-story validation at 2615–2616; citynode submission at 2746–2747; `toNodeTemplate` at 2756–2776 copies generic template values with selected remappings. Private detail hydration uses `players`/`duration` at 3045/3048.

Mini therefore has generic duration/player metadata. It does not establish an exact mapping of this new three-field group (integer minutes, maximum simultaneous participants, explicit staffing) into the current native contract. In particular, generic player counts must not be relabeled as an authoritative venue-capacity constraint, and there is no verified staffing field. No new API path or payload key was added. All ordinary method, image, coupon, answer and server-write grants retain their prior behavior. AI suggestion allowlists are unchanged and cannot fill these new facts. No payment, reward, stock, publishing or audit status is altered.

## Integration handoff

- Merge `Resources/MerchantTemplateParticipationPlanLocalizations.fragment.json` into the shared catalog through the integration line. It contains 16 English / Simplified Chinese entries.
- New Swift test files: `Tests/CoreTests/MerchantTemplateParticipationPlanTests.swift` (8 tests) and `Tests/AppUITests/MerchantTemplateParticipationPlanFlowTests.swift` (2 tests). Register with the normal central project/test process; no central PBX/catalog/CI file is changed in this slice.
- Production Core and App changes are inside already registered files.

## Verification boundary

Focused Python source checks and pinned Tree-sitter parsing are supplementary checks, not Swift typechecking. Core XCTest and synthetic UI regression cases are authored for the field validation, immutable snapshot, cancel/edit/discard/reload/session fences and no-submit behavior. Their execution, Apple compilation, simulator rendering, VoiceOver and Dynamic Type remain separate gates when no Swift/Xcode toolchain is available. No live provider or backend call is part of this implementation.
