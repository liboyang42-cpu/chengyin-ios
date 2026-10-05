# Play-template authoring and prefab narrative preview

## Delivered slice

This isolated slice implements local SwiftUI play-template authoring. It is not a claim of full publishing, whole-route editing, complete Prefab Life gameplay, or release acceptance. No source uploads, backend/provider calls or remote configuration changes were performed. The parent subsequently authorized shared app integration; only the additive module and its named integration surfaces were changed.

- Native intro → name → editor replacement steps, own-template list view, review sheets, local player/story preview, editable completion/reward/story/audio modules
- Exact `TemplateDraft.toJson` field set and module-dependent omission; text, multiple-choice, photo, QR, GPS and no-validation codes stay distinct
- Typed `AuthoringPlayTemplateID`, with strict decoding; adoption retains `originalTemplateId` without reconstructing public-projection answers or conflating topic/activity/node IDs
- All 25 advanced section defaults retained exactly, with seven source-enabled authoring panels plus timer; selection disables other game sections while preserving modifier state
- Source range/length validation and active-section normalization for those seven panels; unrecognized or unsupported active sections survive locally but block submission
- Complete dormant JSON/multipart wire request builder, exact request descriptors, response envelope handling, duplicate-name/moderation classification, and fake-transport execution
- Device-only, unlocked-only, non-synchronizing Keychain drafts scoped by region/deployment namespace and account; no plaintext fallback or implicit legacy migration
- Immutable review snapshot with account, credential epoch, authorization revision, generation and draft equality checks; persistent pending intent before dispatch; terminal and uncertain records survive re-entry
- A separate 13-scene prefab state engine, source profile classification/dice/gain/observations/version-restore semantics, and account-scoped local narrative-state preview
- English and Simplified Chinese catalog overlay; Dynamic Type-friendly forms, system controls, accessible identifiers and no motion-dependent interaction

## Verification

Executed in this workspace:

- 21 module Python source/structure tests and all 207 aggregate source checks passed
- 23 new/edited Swift files passed the pinned Tree-sitter supplementary parse, zero recovery nodes; full-tree parsing retains ten pre-existing diagnostics in six files across 457 files
- Exact source defaults and full template payload field set checked against the retained Flutter files

Authored, not run:

- 65 Swift domain/safety tests
- 10 synthetic XCUITest flows

NOT_RUN: Swift typechecking/tests, Apple SDK build, iOS simulator, screenshots, VoiceOver, actual Dynamic Type rendering, Keychain runtime, CN/US acceptance, full publishing/provider/backend behavior. `swift` and `xcodebuild` are absent in this Linux workspace. Tree-sitter is not compiler evidence. The Debug fixture host is mounted; it has not been executed on Apple tooling.

## Source map

| Flutter source | Native implementation | Scope |
|---|---|---|
| `data/models/template_draft.dart` | `TemplateAuthoringDomain.swift`, `TemplateAuthoringContract.swift` | Every source payload field and module omission; draft/publish validation |
| `data/api/template_api.dart` | `TemplateAuthoringContract.swift`, `TemplateAuthoringService.swift`, `TemplateAuthoringWireRequestBuilder.swift` | my-list, draft, publish, library toggle, delete; exact JSON vs FormData |
| `feature/template/template_detail_page.dart` `_adopt` | `TemplateAuthoringDraft.adopt` | Public-field adoption + source attribution, no secrets |
| `feature/template/template_creation_navigation.dart`, intro/name pages | `TemplateAuthoringView.swift` | Replacement-step native state; no stacked stale wizard pages |
| `feature/template/template_edit_page.dart` | `TemplateAuthoringView.swift`, `TemplateAuthoringDetailForms.swift` | Completion/reward/story/audio configuration and preview |
| `feature/template/advanced_game_configurator.dart`, `_view.dart` | `TemplateAdvancedDraft.swift`, advanced SwiftUI form | Seven source-enabled scalar games and timer |
| `data/models/advanced_play_config.dart` | `TemplateAdvancedDraft.swift`, `advanced-source-defaults.json` | Exact complete defaults; selected-panel normalization/ranges; preservation gates |
| `data/models/node_game_catalog.dart` | `TemplateAdvancedDraft.swift` | Exclusive game-section selection; coin/dice are not timed games |
| `feature/template/template_dict.dart`, `data/api/registration_api.dart` | `TemplateAuthoringDictionaryOption`, `.dictionary` | Nonempty fallback options, exact dict request descriptor |
| `data/models/validation_method_labels.dart` | `TemplateAuthoringMethod` | Authorable codes 0–5; code 5 is GPS arrival |
| `feature/prefab/prefab_story_engine.dart` | `PrefabPreviewEngine.swift` | Thirteen scene IDs and engine functions; local scoped persistence |
| `feature/prefab/prefab_life_page.dart` | `PrefabPreviewView.swift` | Explicit narrative/state preview only, not full scene gameplay |

## Deliberate native safeguards

- UTF-16 counts match Dart string-length bounds, including emoji
- A removed/empty correct multiple-choice option cannot be submitted
- Typed play IDs reject zero/negative values when created or decoded
- Bad advanced/story JSON is surfaced and preserved, never silently replaced by an empty configuration
- Unknown schemas/unsupported active advanced sections cannot be serialized for submission; no lost-data fallback
- Existing server-template edits cannot be initialized from a public projection; no owned `/myinfo` route was invented
- Source prefab storage's activity/topic numeric collisions are avoided by separate typed buckets
- Integer arithmetic in prefab state is overflow-safe without changing normal source ranges

## Remaining integration and parity gaps

1. Shared integration is complete: account authoring entry, protected local factories, public play-template adoption, narrative preview entry, Debug fixture isolation, 211 bilingual keys, deterministic project generation and six exhaustive UI shards. Existing operation modules were left intact.
2. `TemplateAuthoringLaunchView` now mounts the distinct create-play-template, own-play-template and prefab preview destinations from Account. Normal public-play detail from Home and creator routes passes a typed adoption factory. Topic-template preview does not receive that factory.
3. AppSession retains coordinators keyed by source play template (zero is the new draft). It constructs `TemplateAuthoringSecureStorage(scope:)` from the verified `RegionalSessionStorageScope`. It constructs `TemplateAuthoringSession` from the authenticated account, that exact namespace, session epoch and authorization/role revision. A live closure and the account/epoch/role identity fence the destination, rather than a frozen session snapshot.
4. Production adapters remain nil/hard-off. To accept a real backend later, independently validate permission/current-session checks and every endpoint/response in the target deployment. The dormant builder creates exact wire bytes, but does not send them. Only synthetic transports are executable in this slice.
5. Existing owned-template editing needs a verified full draft read contract, including hidden answers, revision and permissions. The audited `TemplateApi` exposes public info and `my-list`, not owned full detail. List/library/delete request adapters are complete; library-toggle/delete management UI and guarded management coordinator are not implemented in this slice.
6. Dictionary/category read descriptors and complete fallback models are present; editor currently uses explicit source-value fields. Native fetched-option pickers and category chooser integration remain. Category IDs must not be guessed or populated from topic-template identities.
7. Media references can be edited and preserved. Uploads, media pickers, remote image/audio playback and choice-option media editing are not implemented here. Existing `questionOptionMediaJson` data remains in domain/payload and survives local saves.
8. Seven source-enabled advanced panels are implemented. The broader advanced schema's other editing panels and full native gameplay remain outside this slice. Their data is preserved and gated, not claimed complete.
9. `PrefabPreviewView(store:identity:sessionRevision:currentSession:)` is a local narrative-state preview, not a replacement for the source's 3,220-line gameplay page. Dream-card artwork/text deck, individual scene puzzles, photo/location/sensor actions, animated staging, job/story presentation, synchronization and real rewards still need migration/acceptance. The play-runtime worker was told not to mark preview steps as completed gameplay.
10. No audited operation-receipt/status contract exists for template writes. After an uncertain response, the record remains locked across navigation and same-owner reauthentication. A matching title in `my-list` is not proof of success and never authorizes a retry. Terminal synthetic records also remain locked to prevent duplicate submissions in tests.
11. Validate rendering and behavior on Apple tooling before enabling routes broadly. Source checks and authored test counts are separate from passing runtime tests.

## Integration commands

From the shared app checkout, after copying this module's files:

```sh
python3 docs/write_template_authoring_localizations.py Resources/Localizable.xcstrings
python3 tools/generate_project.py
python3 -m unittest discover -s Tests/ContractChecks -p test_template_authoring_contracts.py -v
swift test
xcodebuild -project Questify.xcodeproj -scheme Questify -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The catalog path must be the existing app catalog, not a new duplicate. In the Debug launch argument dispatch only, route `--ui-template-authoring` to `TemplateAuthoringFixtureHostView`. No synthetic values belong in production routing. The confirmed guide route was also corrected from Club tag 2 to the actual Roam tag 3, with a source assertion deriving the target from the real tab tags.

## Final integrated inventory

1,200 authored core methods; 193 authored UI methods in 28 classes; 2,561 bilingual keys. Six exhaustive shards: 33/33/33/31/31/32. Includes the concurrent one-test social numeric reward-total fix. All 207 source checks, 16 tooling tests, 14 parser self-tests, deterministic project/scaffold and whitespace checks passed. No CI or publication was run.
