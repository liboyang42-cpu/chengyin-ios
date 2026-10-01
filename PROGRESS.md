# Native iOS migration progress

Status: migration in progress, not release-ready.

## Working convention

Continue implementation and validation on `migration/native-ios`. Do not open a new PR for every small slice. Open one overall migration PR when the complete scope is implemented and its acceptance evidence is available. Earlier small draft PRs remain historical evidence; closing them does not mean their features are complete or merged into main. The migration branch preserves their commits.

## Last verified code revision

`1860c2880b24e4d82805a9bcb5f2cd5f8ec07a4d`

[Native checks run 36848589415](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/36848589415)

- 94 Swift unit tests passed
- 6 Python importer tests passed
- 9 iPhone Simulator UI tests passed
- Unsigned simulator Debug and device Release builds passed
- Gitleaks passed

The five entry UI cases cover persisted language switching, repeated player/merchant entry dismissal, unconfigured login blocking, repeated Settings presentation after cold launch, and the scanner's unsupported-Simulator/Cancel path. They do not exercise real credentials, business data, camera recognition or payment.

## Implemented, with limits

- Independent SwiftUI project with iOS17 provisional minimum; English/Chinese resource catalogs and app language preference
- Existing-account password sign-in code, Keychain session storage, bootstrap/logout/cancellation guards; live server and physical Keychain behavior unverified
- Read-only activity client, searchable/paged native list, detail, ticket display, MapKit for valid coordinates and explicit club gate; four isolated offline UI scenarios passed in run 36848589415; visual screenshot review and backend validation remain outstanding
- Registration request/response contracts, quote signature preservation and stable retry identifiers; no order/payment execution
- VisionKit/UIKit scanner component, permission/lifecycle/retry/one-shot-delivery handling; outside production navigation pending a validated business host, and physical-device recognition untested
- Reviewed-key ARB conversion tool; candidate resource conversion is not completed UI translation

## Not yet completed

New-account registration; native Apple/WeChat provider flows; the full original home and primary navigation; roam and game/check-in loops; registration/quote/order/payment/ticket verification/refund UI; merchant and club workflows; messaging/collaboration; remaining source features; full content localization; accessibility/visual/device acceptance; signing and distribution.

No migration percentage is claimed. Source route declarations, resource keys, test counts and compiled files are different measures.

## Next acceptance sequence

1. Add controlled activity and session UI fixtures, screenshots and lifecycle regression coverage
2. Complete a discover → detail → quote → registration/order-status vertical slice with explicit confirmation and authoritative status readback
3. Migrate remaining player, merchant, club and messaging workflows against source contracts
4. Validate using an approved non-production API and purpose-built accounts/data; do not use production data as disposable tests
5. Complete device, privacy/legal, accessibility, asset-license and release checks; release/signing/production changes require separate authorization

## Known verification history

An earlier UI run failed because the test queried a native Picker option as StaticText; another inherited a Picker identifier onto its children. Tests now use the observed native Button labels. A later run lost a synthesized Settings tap; readiness/post-navigation checks and repeated cold-launch coverage were added. One rerun also encountered Xcode simulator launch/DTX failures. These failures remain recorded; subsequent green runs do not erase them or prove universal runtime reliability.

## Activity UI regression follow-up

Run 36846622633 compiled both app configurations and passed the existing five entry UI cases, but all four newly added activity cases failed. The rendered hierarchy exposed an empty detail destination before its loading task started, inherited accessibility identifiers, and scrolling obscured by the keyboard. Concrete state roots, leaf identifiers and unobscured gestures passed all four cases in run 36848589415. These failures are not excluded or relabeled as passing.

Registration networking now includes source-aligned quote/create and one explicit known-ID status readback, with 25 synthetic service tests. It remains unwired to live UI/credentials/payment.

## Parallel module batch (awaiting integrated CI)

- Discovery home, separate route/game template shelves, play detail and read-only route preview; six source-backed public reads
- Personal orders with fresh detail, participant information with owned detail, badge wall and badge detail; session-isolated reader
- Merchant access/me gate, owner dashboard, permission-scoped filtered orders and hosted projects with summary sheets
- Explicit guest browse entry; account tab returns guests to identity/login selection
- 228 new bilingual module keys plus guest entry; the catalog now has 317 keys
- 86 new synthetic domain/service tests authored across the modules; three offline module UI smoke cases and guest navigation case authored

These are partial read-only module migrations, not complete workflows. Publishing/editing, verification/refunds, full feed, chat, club and play loops remain outstanding. The static mapping report fixes the source denominator at 130 mini-program mappings plus six extra App-route splits; it is not a work-completion percentage. The latest pre-batch a17b4ff run passed domain/build checks but timed out in one search UI expectation, so full regression remains open.

## Second parallel read batch (awaiting integrated CI)

Club home/directory/detail/member visibility, manual-area roaming map/list/details, and conversations/history have been integrated with session-scoped readers. No location permission, GPS sampling, message sending, marking read, join/invite, payment or other remote mutation was executed. Roaming has no default real location: the manual coordinate form is empty, keeps data in memory, and explains how a configured search uses its center.

114 additional synthetic domain/service tests and 214 bilingual keys were authored in this batch. Integrated totals are 315 authored domain tests and 531 catalog keys, not pass counts. The previous 1846552 batch passed 201 domain tests and both unsigned builds; its UI run passed 12/13, with a strict separate-text match for the order number failing. The updated assertion also recognizes the native combined label and retains the required reference value. It awaits revalidation along with the new module flows.
