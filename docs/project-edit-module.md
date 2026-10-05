# Professional project editing migration

## Delivered source-only scope

Home's pencil action and Account → Route editor now open a local authoring chooser for city orientation or free exploration. The existing Official Events entry and project read previews remain intact. Guests can edit and review an in-memory blank draft; they cannot save or send it. Signed-in, deployment-scoped sessions can save/restore an account-bound draft in native device-only Keychain storage. Missing configuration is explicit on every editor/review screen.

Native forms cover route copy, date strings, existing cover/gallery references, manual verified category IDs, chapter creation/reordering/removal, opening story, text/image-reference/audio-reference/node story blocks, stop copy/address/coordinates/duration, and ticket names/price/stock/team size/schedule/meeting point. A city chapter must have genuine opening prose before adding a stop. A nil/empty ticket price differs from explicit zero. Free exploration always needs a recruitment deadline. The first-pass form uses native Form, NavigationStack, accessibility labels, a shared status badge and a persistent review action. There are no external image fetches.

Existing-project edit detail decoding, source payload construction, WHITELIST restrictions, and end-to-end simulated review/confirmation are implemented and fixture-accessible. Production edit-detail requests and production publication remain disabled. No existing server project is represented as successfully edited.

## Audited source

- `lib/data/models/publish_draft.dart`: product types 1/2, complete draft state, chapters, story blocks, tickets, metadata and legacy atmosphere aliases
- `lib/data/api/publish_api.dart`: create/update JSON paths, edit-detail form route, data shapes, merchantStatus→openMerchantPool, totalInventory→totalStock, cmsTopicNodeList→nodes, nodeId→local node reference, AI precheck route
- `lib/feature/publish/publish_draft_logic.dart`: story prerequisite; zero/bounds coordinate checks; free-explore deadline; ticket schedule/price distinctions; story ordering; 200-block limit; source payload keys; `openClubPool=0`; fixed ticket mode; whitelist fields; replacement chapter carry-over
- `lib/feature/publish/pro_editor_draft_store.dart`: account-checked secure envelopes, separate new/topic buckets, base revision conflicts and active draft pointers
- `lib/feature/publish/publish_pro_page.dart`: 400 ms autosave, edit suppression of repeat Creative Square publication, owner scope and pre-submit checks
- `lib/feature/publish/publish_capability.dart`: explicit zero quota blocks, nullable quota is not zero

The Swift decoder rejects unknown edit scopes/products, wrong topic IDs, absent revisions and broken story references rather than inferring permission or discarding content. Date validation is deliberately stricter than the Dart regular expression. Wall-clock date text is preserved without inventing a timezone. These are conservative native differences, not a claim of complete behavioral equivalence.

## Safety and persistence

`ProjectEditDisabledService` remains the default composition. A separate ProjectEditHTTPService now implements scoped dormant source-backed reads/writes, immediate acknowledgment and persistent dispatch-start locks. It requires explicit approval and secure pending storage; no production grant is provided. DEBUG simulation and HTTP acknowledgment have separate outcomes and copy. See [operation adapters](operation-adapters-module.md) for the current dispatch design and remaining gates.

Confirmation binds an immutable payload, snapshot and complete session epoch/namespace/account. Existing fixtures recheck revision and scope after confirmation. Creates recheck capability/quota. The full draft/active pointer and durable pending intent must save before a synthetic submission begins. Pending intent is reread immediately before submission, preventing a second coordinator from replaying the same target. Unknown outcomes persist across navigation, coordinator recreation, session epoch changes and process restarts. Only a terminal receipt for the exact operation/target can resolve uncertainty; matching field reads are not enough. Completed fixture receipts remain persisted to prevent same-draft replay. No backend idempotency capability is claimed.

Local envelope identity includes member, exact deployment namespace, draft identity, product, owner scope and base revision. Existing restore requires a known equal revision. Secure storage is non-synchronizable, unlocked-only, this-device-only. There is no Flutter bucket import, cross-region migration, plaintext fallback or UserDefaults draft storage. Corrupt/unavailable pending storage blocks submission. Native drafts are a separate schema, not a promised byte-compatible Flutter migration.

## Integration

- New files: `Core/ProjectEdit*.swift`, `App/ProjectEdit*.swift`, corresponding Core/UI/source-contract tests
- AppSession retains one production-disabled new-draft coordinator per product; its session closure uses the real account, credential epoch and reviewed RegionalSessionStorageScope service
- SessionHomeFeedView and AccountView expose the local chooser. Home sheets dismiss on session revision change; the chooser is also keyed by the current session revision
- ModuleFixtureSupport routes `--uitesting-module projectEdit` without constructing a production session
- Fixture flags: `--project-edit-blank`, `--project-edit-edit`, `--project-edit-whitelist`, `--project-edit-free-explore`, `--project-edit-disabled`, `--project-edit-unknown`
- Catalog fragment: `docs/project-edit-localizations.json`, 128 English/zh-Hans keys merged into the app catalog
- Generated project includes all owned app/core/UI files. SwiftPM already includes all Core and CoreTests files. UI shards discover every class automatically

## Exact remaining parity

Not implemented/enabled: live capabilities/identity ownership and category search; production edit-detail loading and mutation adapters; tested CN/US backend contract and idempotency/terminal receipt guarantees; AI draft generation and safety precheck; upload/crop/gallery/audio recording; media preview; POI/map picker; gameplay/template creation/selection/editing; collaborator picker and publisher/club/merchant identity selection; self-play, medals/coupons and merchant terms editors; ticket refund policy, sale-window and gathering-coordinate editors; complete publish chooser/activity/simple/AI publish modes; multi-draft inventory/new-draft-after-completed-simulation controls; publish/shelf/delete/refund/payment actions; Flutter secure-storage migration. Existing supported metadata is retained where decoded, without claiming full unknown-field replacement fidelity.

Category IDs, media references, coordinates and date strings are editable first-pass fields with explicit missing-picker notices. Source-native rich pickers and date/time presentation still need UI refinement. No production switch may be enabled simply because source checks pass: exact contract fixtures, capability/auth tests, actor/type checks, secure-store behavior, cancellation/timeout recovery and Apple runtime evidence are still required.
