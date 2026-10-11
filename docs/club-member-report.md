# P045 contextual member report entry

## Exact delta

The previous native member list opened public profiles and customer records but had no `reportClubMember` action. The existing generic platform-report form also ignored entry target seeds, defaulting to a club report.

This slice adds a separate report button for other members, displays the selected member's name, and freezes the `MEMBER`/member-ID pair. It reuses the existing governance form, read/review path, coordinator, confirmation, acknowledgment and durable outcome-lock rules. A report remains a platform review request; it does not directly remove or ban a member. No production capability was enabled and no real report, invitation or member mutation was executed.

## Source and base

- Native base: `53bbc93ea77bcb66a2ed1701e3e0ef8896d30e13`.
- Overall product document: P045 `reportClubMember` and its existing P050 `reportTarget` destination.
- Exact Mini revision: `f859cd6e2618f618a53f5cd33949259828e86313`.
- `chengyinhub-xcx/pages/club/detail/index.js`, lines 2316–2330: membership and non-self guard; `clubId`, `targetMemberId`, and bounded display name.
- `chengyinhub-xcx/pages/club/detail/index.wxml`, lines 339–345: member-row report action distinct from profile navigation.
- `chengyinhub-xcx/pages/club/governance/index.js`, exact blob `9a933c330d107d6aad6adcbb083e6bbb2c6de98f`: entry target normalization, access/me preflight, report reason and exact request contract.

The source was read at the exact blob through the authorized read-only connector. Private source evidence remains outside the public repository. This patch is independent of the preceding calendar patch and does not touch its files.

## Boundaries

The selected member must occur exactly once in the currently accepted directory for the same club. The viewer must be a signed-in member/owner and the selected member cannot be the viewer. Display names are normalized and bounded; they are never added to the request body.

The form's scoped seed becomes immutable anchors. Only the reason is editable. Partial or malformed seeds fail command validation instead of silently changing the target to the club. Adding an editable field over an anchor is also rejected. Unseeded generic report forms retain their original target selector and default behavior.

Reload clears the accepted reporting directory and any report sheet before reading. Queued callbacks cannot open an old member target after refresh, account/epoch/viewer-revision/authority/access changes, or while the list is covered. Returning to the list re-reads it. A context change closes the report form and retires its pending review. The report and public-profile buttons have separate borderless actions to avoid SwiftUI list row multi-button activation; the report button has a 44-point hit area and a member-specific accessibility label.

## Focused validation

Executed locally:
- 15 focused source/static checks passed.
- 7 exact Mini action cases passed with navigation stubbed; no external action occurred. This validates the source oracle, not the Swift code.
- Supplementary pinned Tree-sitter parse: five Swift files, zero recovery diagnostics.
- Patch whitespace and before-to-after application/hash checks passed.

Authored: nine Core tests covering exact anchors, source payload fields, ordinary/owner admission, no self/guest/foreign/duplicate target, refresh and identity fences, invalid seed rejection, immutable target overrides, default form compatibility, and reuse of read-only review with disabled dispatch.

NOT RUN: Swift compilation/typechecking, these nine Swift tests, Apple UI/VoiceOver/simulator checks or real backend acceptance. The current computer has no Swift/Xcode toolchain. No prior UI failures were investigated or modified.

## Integration

Merge `ClubMemberReportLocalizations.fragment.json` and register the new app/Core sources and tests using the existing integration process. The exact additions are in `club-member-report-registration.fragment.json`. No PBX project, aggregate localization catalog, CI workflow or existing fixture host was edited.
