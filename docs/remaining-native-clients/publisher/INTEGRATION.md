# CreatorApplication + PublisherLifecycle additive integration

Packet is isolated, no remote changes, no requests performed. Do not claim normal-host wiring until the edits below are applied in the integration checkout. No production grants are supplied. Concrete injectable HTTP clients and native consumers are implemented, not endpoint-only descriptors.

## Exact dependencies and copying

Copy the exact files in `manifest.json` into matching target directories. Core files belong to QuestifyCore and the app's core compilation as existing project convention requires. App files belong to app target; CoreTests to QuestifyCoreTests; AppUITests to the UI test target. Do not replace Package.swift, project.pbxproj, localization catalog, AppSession, existing UI files or other packages wholesale. Merge file references using the existing project generation process. No external package dependency.

Reuses APIConfiguration, HTTPTransport, AuthRequestBuilder, OperationEndpointApproval, OperationPendingJournal, OperationPendingRecord, OperationAdapterHTTP, ProjectEditJSON, PublishingCredentials/Session/Region, PublishedResource, CreatorContentCenter/ApplyStatus/Reading. Existing PublishModes/project editor/topic/CreatorContent readers remain owners of their workflows.

## Normal host hooks

1. Construct PublisherLifecycleHostContext in AppSession's existing publishing context, using the same ephemeral no-redirect transport/configuration and current credential closure as PublishingService. Its constructor hardwires `.dormant`; every production read and mutation remains OFF. If config unavailable, omit context and display existing unavailable copy.
2. Supply a freshAuthority closure using current source-backed existing project/detail/club-cooperation readers. It must read server state on every call, validate account ownership and return immutable target, owner, a complete stable server-state fingerprint/revision, beta flag, and eligible club IDs validated by existing source-backed club leadership/cooperation state. Never turn a navigation ID, UI isOwner, local role, guessed version, or empty revision into authority. If authoritative ownership/eligible-club proof is unavailable, throw `.unavailable`. No new authority/version/receipt endpoint is invented here.
3. In SessionPublishingModesView's existing detail destination or PublishingManagementViews project row detail, insert PublisherLifecycleProjectLinks with the immutable current PublishedResource, current topic owner/beta projection, and the existing club picker's eligible selection. Do not replace offlining/delete; cancellation is a separate destructive destination. TopicDetailView can accept this same optional link content from the existing host; do not add a second topic manager.
4. In ProjectEditView's saved-topic editor only, append PublisherXPBudgetSection(topicID:client:) inside its Form. This performs read-only XP budget display. Preserve the entire ProjectEditDraft, including hidden fields, unchanged. There is no XP mutation.
5. In CreatorContentCenterView append CreatorApplicationHostLink for .notApplied/.rejected and pass its existing reload operation as refreshCenter. Rejected displays the server limitation and never a reapply form. Pass the SAME account-scoped center reader. Successful affected-row response invokes that reader again and refreshes the original host.
6. Recreate context/destinations with `.id(publishingSession?.epoch)` / creatorReader.scope and invalidate context on logout/account, role, namespace, region, scene-background, or navigation cancellation. Host fencing is required even when grants are off.
7. Fixture launch branch: before normal app root, handle `--publisher-lifecycle-fixture` with PublisherLifecycleFixtureRoot(). This transport is actor-backed in-memory only and has no network client. Its read grants are fixture-only; its mutations are also OFF. Never install fixture authority or grants into AppSession.

## Gates and consequences

Production grants are separate: reads, pricing, cancellationRefunds, ownership, graduation, creatorApplication. Activation would require independent endpoint/account/deployment approvals and persistent pending journal in an approved composition root; do not enable as migration wiring. This packet does not grant authority to perform money/refund/ownership/application actions. Review is explicit, expires after 120 seconds, and is invalidated by session/field/navigation changes. Confirm rechecks fresh ownership and exact floor/lineup or paidPlayers. Cancellation reason is player-visible. Unknown mutation outcome leaves persistent target lock; there is no automatic retry or invented receipt API. Cross-action operations on one publisher resource share a lock. Creator application lock is account-wide.

Pricing preview JSON contains topicId/subType and guided-only leadCost/teamSize. Confirm deliberately omits subType and sends guidedPrice or selfPrice. Missing/non-numeric floor blocks; missing terms are not zero. Partner inspection refetches self pricing, matches toType/toId, validates terms, then retrieves exact public profile. Public labels never authorize settlement.

Topic/activity cancellation reads cancel_preview `data.paidPlayers` first and never substitutes signupCount. Topic cancel supports optional scope; activity cancellation uses id/reason only, and this coordinator refuses scoped activity cancellation to avoid a misleading preview/dispatch mismatch. Preserve response msg verbatim; success is acknowledgment, not fabricated refund completion. Transfer creates new club draft, offlines original, and initiator retains content ownership; numeric newTopicId is required. Beta graduation is owner-only and irreversible. XP uses server `over`, retains unknown optional fields, and exposes no transfer/mutation.

Creator apply uses multipart (not JSON), exact creatorName plus optional nonempty bio/avatarUrl. Numeric data > 0 is submitted; 0 is notSaved; missing/string/bool data is unknown. UI intentionally takes no arbitrary avatar URL input; an approved existing avatar selection may populate the draft programmatically. No avatar upload is introduced.

## Source evidence

- app-audit/lib/data/api/topic_api.dart:101–204,303–370
- app-audit/lib/data/models/pricing.dart; xp_budget.dart
- app-audit/lib/feature/topic/topic_pricing_page.dart:102–166; topic_pricing_partner_page.dart:117–202
- app-audit/lib/data/api/activity_api.dart:cancelActivity/cancelPreview
- app-audit/lib/feature/publish/my_projects_page.dart:533–585; feature/activity/cancel_activity_sheet.dart:82,134
- app-audit/lib/feature/topic/transfer_to_club_sheet.dart:69; topic_detail_page.dart:433–442,521
- app-audit/lib/data/api/creator_api.dart:44–71; feature/creator/creator_center_page.dart:71–85

## Verification limits

Pinned tree-sitter is supplementary parsing only. Core and UI XCTest are AUTHORED, NOT_RUN. Apple SDK compiler/typechecker/build, simulator/device, accessibility runtime and live backend acceptance are NOT_RUN. Fixture launch hook and normal-host additive steps require parent integration, then Apple verification. A syntax pass is not a successful native build.
