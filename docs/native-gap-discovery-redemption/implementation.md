# Merchant discovery and city-node redemption

Two source-backed destination implementations, **not a claim of full migration, live redemption readiness, or visual acceptance**.

## Source evidence

Preserved Flutter baseline: `a63e9e9` (external source is not included in this native patch).

| Source | Verified contract | Native implementation |
|---|---|---|
| `lib/feature/merchant/merchant_discover_page.dart:29–42` | Six exact tonal tag strings; All invokes `searchByName('')` | `MerchantDiscoveryTag`; read-only `SearchMapService.merchantDiscovery` |
| `lib/data/api/merchant_api.dart:256–288` | `POST /api/merchant/list`, JSON `tags` or `name`, bare `data` list | Existing approved-host/token/cancellation transport boundary, distinct tag method |
| `lib/feature/merchant/merchant_discover_page.dart:45–61` | Role first, five separator characters, three chips maximum | `MerchantDiscoveryRow.chips` |
| `lib/feature/merchant/merchant_discover_page.dart:203–222` | Slogan then description; public home requires positive `memberId` | Typed owner-member destination; no row-ID substitution |
| `lib/data/api/roam_api.dart:257–281` | `POST /api/verify/citynode/redeem`, multipart `code` only; status and verbatim `msg` | `CityNodeRedemptionCode` / `CityNodeRedemptionResult` through dormant `MerchantBusinessService` |
| `lib/feature/merchant/city_node_redeem_page.dart:36–95` | Manual fallback, stop capture on first payload, single handling, ignore disposed callbacks | Existing `NativeQRScanner` lifecycle, session/generation gates and one-use confirmation |

Malformed discovery response shapes fail visibly rather than producing a misleading empty successful list. User-visible labels are English/Chinese; tag wire values remain exact Chinese backend strings. Merchant IDs and owner-member IDs remain distinct.

## Reachability and presentation

- Normal home search → **Discover merchants** → tag chips and merchant cards → existing owner-member public home
- Account → merchant workbench → business workspace → **Redeem city-node code**, only after authoritative `merchant:verify` permission
- Discovery is a full navigation destination because browsing/filtering and onward navigation require history
- Redemption is a focused native form. Manual text uses secure ephemeral input; keyboard is dismissed before review
- Camera is a separate native scanner sheet. A detected code is queued until sheet dismissal, then a short confirmation dialog is presented. The scanner never auto-redeems and no nested scanner/confirmation stack is created
- Cancel, back, account/region change and background clear pending code/consent; raw code is never restored as an unsaved draft
- Result content stays inline and preserves the server sentence exactly. An unknown-outcome message never instructs retrying the mutation

This uses Flutter business behavior as evidence, not as a mandate to copy Flutter modal styles. Actual visual, keyboard, VoiceOver, Dynamic Type, camera and transition acceptance: **NOT_RUN**.

## Security and operational boundaries

- All production mutation transports remain default-off. The new page cannot activate a live grant, configure an endpoint, request account/provider access, or run a real redemption
- Opening the page does not start camera capture, ask for camera permission, fetch location or send the code
- Preparing and confirming are separate steps. `access/me` is refreshed again after confirmation; permission, merchant identity and account epoch must still match
- Code is opaque, bounded to 16 KiB, in-memory only. It is not parsed as a deep link, copied, logged, serialized in a journal or included in an identifier
- Reserve the existing durable coarse `redemption` intent before dispatch. This is shared with other merchant redemption routes, so switching scanners cannot bypass an uncertain operation
- Valid success or explicit business-rejection envelopes preserve `msg`, settle their acknowledged intent, and permit a fresh next-code review. Transport errors, malformed bodies, interrupted writes and responses arriving after dismissal/session change remain locked
- No status range on transport errors, timer, restart, new epoch or Next button clears an unknown write. No invented reconciliation endpoint was added
- Existing approved image renderer is reused; unapproved remote image fetching remains absent

## Verification

- 20 new Swift domain tests authored (7 discovery, 13 redemption); **NOT_RUN**, no Swift toolchain here
- 9 new offline structural/source contract checks: **PASS**, including external source root
- Existing full Python contract suite with explicit external source root: **440 discovered, 421 passed, 19 explicit skips**, no failures. The skipped older tests require their separately hard-coded external checkout paths; they are not source passes
- Public checkout without external Flutter source: **440 discovered, 402 passed, 38 explicit external-source skips**, no failures. New native assertions run independently; only the added source comparison skips
- Existing search/map offline checks with explicit Flutter source: **26 PASS**
- Project generation + scaffold/catalog/reference checks: **PASS** (669 Swift source files, 5,179 bilingual keys)
- Supplementary Tree-sitter attempt: **NOT_RUN** because parser dependencies are absent from this worker's Python environment; this is not a compiler failure
- Apple compilation, Swift/XCTest execution, screenshots/XCUITest, real backend, account, location, camera/provider, device, signing and distribution: **NOT_RUN**

The deliverable closes these two missing native source surfaces at the code/dormant-contract level. Live and visual acceptance remain independent gates.
