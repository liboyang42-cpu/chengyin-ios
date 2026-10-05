# Creator and published-content native batch

## Source and boundaries

Audited Flutter source at a63e9e91:
- lib/data/api/my_project_api.dart (`page`, source fixed pageNum 1 / pageSize 200)
- lib/data/models/my_project.dart (business-scoped IDs, destination routing, server labels)
- lib/feature/publish/my_projects_page.dart (type/owner/state vocabularies)
- lib/data/api/creator_api.dart (`center` only)
- lib/data/models/creator_center.dart (four known states, nullable metrics, income)

Only `/api/project/my` and `/api/creator/center` are dispatched. Both are authenticated multipart POST reads. No host is embedded. No real backend was contacted. Unknown creator states stay unknown rather than source's permissive not-applied fallback; no application capability is exposed. Invalid/nonpositive project IDs fail the response instead of routing ID zero.

Published content has topic/activity/template filters, publisher and state filters, compound business-type/ID deduplication, source detail callbacks, empty/error/login/unconfigured states, visible fixed-cap notice, fresh reads, foreground refresh and cancellation guards. Server category/state/acceptance labels are verbatim. Topic/activity/template IDs can be equal without merging identities. Source `/api/project/my` template rows are supported; the separate template-library management screen and `templateApi.myList` are not migrated here.

Creator center represents not-applied, pending, approved, rejected and unknown independently. Missing metrics stay missing, numeric zero stays zero. Rejection reason and backend repeat-application restriction are explicit. Income is only the supplied record, with no invented currency or balance/payout claims. Original money strings remain exact; numeric JSON amounts are stringified without currency formatting.

## Integration

1. Copy Core/CreatorContent*.swift, App/CreatorContent*.swift and Tests/CoreTests/CreatorContentTests.swift into matching native directories. Add file entries with the existing project generator; do not assume Xcode auto-discovers files.
2. Merge localization keys from docs/creator-content-localizations.json into existing resources. These are fragments, not replacement files (48 bilingual keys).
3. Construct CreatorContentService with the same reviewed APIConfiguration and existing ephemeral/no-redirect HTTPTransport. Construct CreatorContentSessionReader with a closure returning `try? CreatorContentReadSession(accountID: account.id, epoch: sessionEpoch, token: token)`. Never persist the token or put it in a view model.
4. Wire onUnauthorized to the existing session invalidation path only for the supplied captured session; reader already suppresses canceled/stale errors before callback. Host should observe account, token, market and epoch changes and reset both destinations with `.id(reader.scope)`. A same-account new token or epoch must change scope. Config changes require a new reader.
5. Add account NavigationLinks to CreatorContentProjectsView(reader:onOpen:) and CreatorContentCenterView(reader:). Use existing native topic/activity/template destinations for the three typed callback cases (.topic, .activity, .playTemplate); no URL guessing. Gate unavailable destination implementations explicitly rather than silently sending to topic.
6. DEBUG module `creatorContent` should mount CreatorContentFixtureHostView. Add five CreatorContentFlowTests to AppUITests and the exhaustive UI shard inventory. Harness has `--creator-failure`, `--creator-guest`, `--creator-rejected`, `--creator-empty` flags; synthetic data is explicitly labeled and no fixture dispatches HTTP.
7. Run the full Swift core suite, unsigned iOS builds and all UI shards on Apple CI. Check English/Chinese, large type, screen-reader semantics and dark mode visually. No Apple toolchain exists in this worker environment.

## Verification actually run

- Ten Python source-only contract checks pass (`python -m unittest discover -s Tests/SourceTests -v`).
- Pinned Tree-sitter advisory parser passes all eight Swift files with zero diagnostics (tree-sitter 0.26.0, tree-sitter-swift 0.7.3).
- 21 Swift core tests and five UI tests authored, NOT executed here. Apple compilation/typechecking/runtime/UI screenshots were NOT run. Source guards/parser are not compiler evidence.

## Remaining parity

Creator apply including nonzero integer acknowledgment, publication/drafts/editor/image upload, deletion, visibility changes, cancellation/refunds, analytics/player/contact data, creator payouts and standalone template-library administration remain deferred. No completed-write state or active control pretends these exist. Source project API exposes no next-page argument; fixed 200-result cap is disclosed rather than inventing pagination. This is an additive read batch, not full creator/publishing parity.

## Template routing verification and preview distinction

The destination enum explicitly names `playTemplate(Int)`, not a generic template. Mapping uses only source `bizType` and positive `id`: topic → `.topic(id)`, activity → `.activity(id)`, template → `.playTemplate(id)`, anything else → nil. Source `MyProject.detailRoute` explicitly maps bizType template to `/template/:id`; `app_router.dart` mounts `TemplateDetailPage`, which uses `templateDetailProvider` / `TemplateApi.info` / `/api/template/info` returning `PlayTemplate`. This is the same entity read by native DiscoveryTemplateDetailView. PlayTemplate.packType 0/1/2 are node/story-pack/store-IP-pack forms of that same entity; they are not TopicTemplate.

The distinct TopicTemplate model (cms_topic / is_template=1) comes from `/api/template/topic-template/list`, with name/subtitle/chapterCount/locationCount/previewOnly/templateStatus and no supported independent detail endpoint. It must use a supplied DiscoveryTopicTemplatePreview, never DiscoveryTemplateDetailView. MyProject has no source-backed subtype discriminator declaring a TopicTemplate; `projectType` and projectTypeText are category metadata, not authority to reinterpret IDs. This batch does not fetch or invent TopicTemplate data.

Note: source `_ProjectCard._open` opens draft/rejected topic editors or the project-management home, rather than the public topic preview. This read-only batch intentionally exposes existing native topic detail previews only, and does not claim management/editor parity. The separate source template tab uses TemplateApi.myList; that administration endpoint remains deferred.
