# Square governance integration

## Scope and evidence

This isolated implementation adds account enforcement/appeal, notification/read/preferences and author-specific comment controls. It does not replace the Square composer, media, drafts, guidelines, post deletion, reports or general SocialAction flow. Those remain separately owned.

Primary source: `app-audit/lib/data/api/square_api.dart` 537–613 and 669–687. UI behavior: `square_governance_page.dart`; comment permissions: `square_detail_page.dart` 847–855. Raw comment aliases/version: `square_post.dart` 502 onward. Authentication: `core/network/dio_client.dart` 47 uses the raw Authorization token, without adding Bearer.

## File integration

1. Apply `patches/SquareContracts.version.patch` from the native project root (`git apply --check` then `git apply`). This narrow three-line model projection is validated against the current native source. `verification/SquareContracts.swift` is a parser-only projected copy; do not copy that whole file over newer work. Then copy all `Core/SquareGovernance*.swift`, `App/SquareGovernance*.swift` and prefixed test files into the matching native project folders. The Xcode generator compiles Core and App together, so App files deliberately do not import the separate SPM QuestifyCore test module.
2. Merge `Resources/SquareGovernanceLocalizations.fragment.json` strings into the application's existing catalog (60 English/zh-Hans keys). Do not replace unrelated strings.
3. Regenerate the Xcode project with the existing generator; run the normal aggregate checks and actual Apple CI. This bundle has not been Swift-typechecked or run on Apple.
4. Add `--square-governance-fixture` to BOTH the QuestifyApp fixture branch and its production-session construction exclusion list. Branch renders `SquareGovernanceFixtureHost()`. The fixture uses an ephemeral journal and canned transport; never constructs a production URLSession.

## Normal host hook

`SquareGovernanceEntryView(context:)` is an ordinary NavigationLink for the existing SquareBrowserView List or account screen, not a fixture-only route. Add an optional `SquareGovernanceContext` to the Square host and mount its entry inside the existing NavigationStack. Avoid nesting another navigation stack.

Create a retained `SquareGovernanceCoordinator` with `SquareGovernanceService(baseURL: actualConfiguredURL, transport: existingTransport)`. This ordinary initializer has reads and writes disabled by default. Do not opt reads into live access as part of this migration. A separate `dormantBaseURL:transport:readsEnabled:grant:` initializer accepts any HTTPTransport and defaults both reads and grants OFF. Its explicitly supplied `SquareGovernanceMutationGrant.reviewedInjection(Set<SquareGovernanceCapability>)` permits only named operations after normal immutable review and fresh scope/permission checks. No shipped app factory supplies this grant. It is a concrete executable adapter, not a permanently fixture-only contract. The convenience offline initializer still requires the clearly named SquareGovernanceOfflineTransport marker; never conform a real transport to that marker.

Use `SquareGovernanceSessionAccess(identity:token:freshComments:)` to supply dynamic, not captured, session values. Within AppSession's existing private scope, derive identity from account.id, gate.currentStamp and storageScope.service; token closure returns the current token only for that same scope. The host must observe AppSession and `.id(identity)` its subtree so logout/account/region/epoch changes dismiss old screens and requests. Retain coordinator/journal across ordinary navigation. Persistent journal keys deliberately exclude epoch so signing in again cannot bypass an uncertain operation lock.

The context's `openDrafts` closure must route to the separately owned Square workspace/drafts host. `openPost` must push into the existing Square detail route and honor `communityPostRead`. `signIn` uses existing login flow. No additional network work is performed by the entry itself.

## Comment freshness contract

Post author can approve only `PENDING` comments with a known nonnegative version. Comment author can delete their own comment. Moderator/admin role alone grants neither operation in this source. Do not substitute a general isModerator or post-owner deletion gate.

The included narrow patch adds `SquareComment.version: Int?` and assigns the source numeric field without a zero fallback. Four projection tests preserve IDs/author distinctions and check missing/null/string versions remain unknown. `SquareGovernanceComment(comment:post:)` bridges the refreshed native comment and post directly. The injected `freshComments` must obtain fresh comments and the post-author ID for the same post/session before enabling approval. Never fill missing version with zero, reuse a static fixture, or guess ownership. A missing version leaves approval locked. A host without a reliable scoped comment reader can pass the default empty list; account governance still works. No new moderator-access endpoint is invented.

## Fresh review and outcomes

Every mutation, including notification preferences and mark-read, requires an immutable review with account, exact target/change, timestamp and request ID. Confirm obtains the same loaded enforcement/notification pages, preferences and comment scope again, compares the full snapshot, and checks session before and after transport. Changed state requires a new review. Cursors use the minimum positive loaded ID; duplicate rows are removed. Lists request 30 enforcements and 50 notifications.

The journal consumes the target before dispatch. Any outcome is conservatively locked against repetition, including transport cancellation/malformed replies. It stores action/target IDs only, never token or appeal text. There is deliberately no automatic unlock: a future live implementation needs independently verified reconciliation and a deliberate recovery policy. It must not simply reconstruct a coordinator or change request ID to retry. The shipped bundle does not enable live mutations. Deliberate future composition-root injection can activate the concrete adapter only after separate review and per-operation grant; UI or server data cannot generate a grant.

A code-200 response yields only `acknowledgedNeedsRefresh`. It does not prove appeal approval, post/comment deletion, or moderation success. The UI keeps the original facts and prompts refresh. Synthetic writes intentionally do not mutate fixture facts, making this distinction testable.

## Unknown/source limitations

Enforcement type/status/appeal_status are raw server facts, not invented enums. Notifications accept object or string payload_json, show known event titles, and safely fall back for unknown actions. REPORT_STAGE publicNote is display text only. Preferences missing booleans stay locked; governance notifications cannot be disabled. Evidence asset IDs are always empty, matching the source's appeal method. Preference PATCH and comment-delete do not gain invented requestId/version fields. No appeal status endpoint, moderation role endpoint, request reconciliation endpoint or post deletion guarantee was inferred.

## Verification

Run `python tools/check_square_governance.py --flutter ../app-audit`. Run the shared strict Tree-sitter script with explicit paths since this isolated directory is not a git checkout. `docs/static-evidence.json` records source hashes and 52 assertions; `docs/parser-evidence.txt` records the pinned parser pass. Parser/static checks are not compiler or runtime evidence. 28 core and 5 UI tests are authored; Swift, Apple SDK, simulator and Xcode executions are NOT_RUN.

## Plain injected transport proof

`SquareGovernanceInjectedTransportTests` uses a fake conforming only to HTTPTransport (not the offline marker). It authors actual coordinator confirmation/dispatch coverage for all five wire requests through the dormant initializer, code-200 acknowledgement decoding, default-off rejection, denial of ungranted operations, and unknown-result target locks. These four new Swift tests are authored, not run in this toolchain-less environment. The pinned parser passes all 13 supplied Swift files; static checks verify the any-transport initializer and per-operation dispatch gate. No real network was used.
