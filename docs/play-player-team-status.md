# Player team collaboration status readback

Offline, read-only native migration candidate. This closes the missing public
team collaboration panel in the existing player game screen. It does not establish
live gameplay, team management, task completion, rewards or production activation.

## Verified source and actual gap

Native input: published commit `343fba15286e60d3ceddbbe1c1738d6e4cc8afd3`, frozen tree
`e562555019d9719c3abafe0d77741c7b43a750f0`. The isolated candidate was copied from that
exact tree; its local baseline commit is only a worktree checkpoint.

Mini-program/backend: `liboyang42-cpu/chengyin`, commit
`ce61c0bbace743ff835cb297ef41c89b52181636`. Each evidence file's Git blob hash was
checked against the supplied repository-tree manifest:

- `chengyinhub-xcx/pages/play/index.wxml:1612–1622`, blob
  `c885d8e15dea1c0cd367bfccb667e596586aa036`: existing “队伍协作” panel displays
  public nickname, role code and collaboration status, plus a location-privacy note.
- `chengyinhub-xcx/pages/play/utils/player-game-module.js:241–258`, blob
  `7b97856bb0ebf1ddeff746a7f08e0813dd0c58b3`: `normalizeTeamActions` names the seven
  statuses and their public labels, and the PLAYER normalizer consumes `teamActions`.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/GameSessionRuntimeServiceImpl.java:1142–1188`,
  blob `3d8ac26f10eb50ba9c48682d9b4cc7873c7a4862`: `requirePlayer` establishes the actor's
  scope; `playerView` asks for the current game session and that player's team only.
- `chengyinhub-system/src/main/resources/mapper/business/GameSessionRuntimeMapper.xml:981–1007`,
  blob `cd90aaf2a7b36f37693a8a28a12c98cee23ce33e`: `selectTeamActionProjection` selects
  only `memberId`, `displayName`, `roleCode`, `status`, scoped to the same session
  and active paid team members, preserving `m.id` order. It omits phone numbers,
  precise coordinates, registration and evidence materials.

Native `PlayPlayerGameProjection` previously discarded `player.teamActions`, and
`PlayPlayerSessionView` had no corresponding panel. The source field is already
returned by `GET api/game/session/view?activityId=…&perspective=PLAYER`; no new
endpoint, query, network reader or API permission is introduced.

## Read-only behavior

The seven labels are distinct:

- JOINED: Awaiting role assignment / 待分配
- ASSIGNED: Awaiting role confirmation / 待确认身份
- CONFIRMED: Role confirmed / 身份已确认
- IN_PROGRESS: In progress / 行动中
- SUBMITTED: Waiting for verification / 等待核验
- COMPLETED: Completed / 已完成
- FALLBACK_COMPLETED: Completed through fallback / 已通过兜底完成

These are public member collaboration statuses as supplied by the server, not a
client verdict that a task, entire run, reward or redemption succeeded. There is
no inference from a role, the current player's submissions, badges or a local
completion count. The source SQL prioritizes the member's latest node outcome,
then submission, then role status; this candidate does not recalculate that order.

A valid empty array hides the panel. Missing/null/non-array data, malformed member
identity, duplicate identity, unsupported or missing status, and malformed display
text show “status not confirmed”. Unknown status deliberately does not inherit
the mini-program's ASSIGNED fallback. Optional missing names use “Teammate”; a
missing role remains absent. Public text is rendered verbatim. No lookup, identity
matching, member detail navigation, invitation, location or evidence UI is added.

The new presentation lease consumes the existing game coordinator's successful
read. The existing submission readback still owns first load and refresh. The
host records the accepted result after its first read and observes ready-phase
and projection changes, including a successful retry after initial failure.

The original account/epoch/namespace/token/role owner, game session and team stay
bound to the screen lease. Read-grant and authoritative node-lifetime revocation
are checked before projecting any rows. Failed/loading/unknown writes, pending
commands, owner change and dismissal hide names and statuses. A session/team
replacement retires the lease; a revision floor rejects rollback. Late or cancelled
reads cannot reactivate a dismissed screen. Reopening creates a fresh lease and
uses the existing reader again. There is no second cache or transport.

All existing player command construction, eligibility, receipt reconciliation,
submission readback and server/node authority are unchanged. W16 interest matching,
W19 home restoration and W20 city settlement are outside this slice.

## Validation and integration

- Focused Python contracts: 9 new plus all 12 existing submission contracts pass.
- Broader `test_play*.py` contracts: 182 run, 170 pass, 12 explicitly skipped because
  their optional external Flutter baseline is unavailable. These are static checks.
- Full contract suite: 2,375 run, 2,328 pass, 47 explicit external-source skips.
- Scaffold check currently stops at Xcode source-membership equality, as expected
  before central regeneration includes the new Swift files. It is not a pass.
- Pinned supplementary Tree-sitter: six changed Swift files parse without recovery
  nodes (tree-sitter 0.26.0 / tree-sitter-swift 0.7.3). This is not typechecking.
- Authored: 16 pure Swift tests and 5 App-hosted tests. They cover seven states,
  source order, absent/unknown/duplicate data, public-field bounds, failed reads,
  original ownership, game/team changes, rollback, unknown writes, read revocation,
  dismissal/cancellation and fresh reopen. App tests include both locales, optional
  display names, and long content at accessibility text size.
- Apple compilation, Swift XCTest, simulator/UI execution, screenshots, VoiceOver
  and live backend acceptance: NOT RUN. Swift and Xcode are absent here.

The integrator must merge the 12-key localization fragment into the existing
catalog and regenerate the Xcode project to include the two new production Swift
files and App-hosted tests. Shared catalog, project, scaffold counts, CI and
AppSession are intentionally outside this candidate's approved edit boundary.

Focused check:

`python3 -m unittest discover -s Tests/ContractChecks -p 'test_play_player*py' -v`

Apple follow-through: execute `PlayPlayerTeamReadbackTests` and
`PlayPlayerTeamStatusTests`; verify the normal player screen in both locales,
refresh transitions, denial/revocation before repaint, changed team, interrupted
reads, Back/reopen, Dynamic Type and VoiceOver. No real-account data is required
for these synthetic checks.
