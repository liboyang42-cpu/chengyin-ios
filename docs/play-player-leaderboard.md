# Player game-session leaderboard

Offline, read-only native parity candidate. The existing player game screen now
shows the source mini-program's optional “本局榜单” panel. This does not establish
live gameplay, reward issuance, production activation or Apple acceptance.

## Source and actual gap

Native input: frozen unpublished integration tree
`3eb25aa37ff73a9ad13f0d8dd8a908bad36449cb`, supplied after published parent `fb5e`.
The isolated Git archive and local baseline tree match exactly.

Mini-program/backend: `liboyang42-cpu/chengyin` at
`ce61c0bbace743ff835cb297ef41c89b52181636`. Reused source bytes were checked by Git
blob hash against the supplied `repository-tree.jsonl`:

- `chengyinhub-xcx/pages/play/index.wxml:1623–1631`, blob
  `c885d8e15dea1c0cd367bfccb667e596586aa036`: “本局榜单” renders server rank, public
  team name and collaboration score, plus an explicitly enabled/empty state.
- `chengyinhub-xcx/pages/play/utils/player-game-module.js:260–275,394`, blob
  `7b97856bb0ebf1ddeff746a7f08e0813dd0c58b3`: `normalizeLeaderboard` requires
  `visible === true`, positive rank/team ID and nonnegative safe-integer score.
- `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/GameSessionRuntimeServiceImpl.java:1142–1188`,
  blob `3d8ac26f10eb50ba9c48682d9b4cc7873c7a4862`: `playerView` establishes the
  player scope and includes the leaderboard only when the game session's
  `leaderboardVisible` is explicitly true. The entries come from that session.
- `chengyinhub-system/src/main/resources/mapper/business/GameSessionRuntimeMapper.xml:967–979`,
  blob `cd90aaf2a7b36f37693a8a28a12c98cee23ce33e`: public `teamId`, `displayName`,
  `rank`, and `score`; score is `count(distinct ... node_id)` only for normal
  `COMPLETED` outcomes, ordered by score descending and team ID ascending before
  assigning server row-number ranks. Fallback outcomes do not add score.

The native PLAYER projection previously discarded `player.leaderboard`; the
normal player view had no matching panel. This data is already returned by
`GET api/game/session/view?activityId=…&perspective=PLAYER`. The existing companion
and advanced-game leaderboards have different APIs and semantics and are not used
as substitutes. No inventory or reward API has been invented.

## Behavior and authority

- Only explicit boolean `visible: true` allows a card. Absent, null, false,
  non-boolean visibility or a malformed container hides all ranking information.
- An explicitly visible empty array has its own empty state. Missing/malformed
  entries under visible=true show unconfirmed; they never become zero scores.
- Malformed rows invalidate the entire visible board. Duplicate team IDs,
  duplicate/out-of-order ranks, nonpositive IDs/ranks, negative/unsafe/non-integer
  scores and invalid public names are rejected. No rows are silently filtered.
- Valid server rank, score and ordering are preserved, including rank gaps and
  zero scores. There is no client sorting, rescoring, tie breaking or rank
  reconstruction. Optional public team names use the localized “Team” fallback;
  names are bounded to 80 characters and rendered verbatim.
- The score label and footer describe the backend's collaboration metric. No
  score becomes wallet points, a reward, a completion command or an entitlement.
- No member or team drill-down, precise location, private evidence, extra query,
  write, persistence or reward action is introduced.

A small presentation lease consumes the existing player reader. It retains the
original supplied session value (account, epoch, namespace, token and role as provided), activity, game session,
team and a nondecreasing revision floor. Owner changes, unavailable/revoked reads,
loading/failed reads, pending/unknown writes and dismissal hide the board before
rows are rendered. When the service is bound to an interaction lifetime, its
revocation also hides the board. A changed session/team retires
the lease; a later rollback cannot restore formerly visible ranks. A newly opened
screen needs a fresh existing-reader result, and dismissed/cancelled work cannot
reactivate an old lease.

Composition/authority boundary: these are authenticated activity/game-session
projections, not anonymous data and not selected-node reads. The backend requires
valid paid registration and an active team; it emits leaderboard data only when
its visibility policy allows it. A root node-generation lease is not part of that
read contract, so adding one solely to satisfy an assumed gate would be unjustified.

`AppSession.playPlayer(scope:)` currently uses an unbound service and the normal
shipping configuration/transport keeps PLAYER routes closed. There is no evidence
of a live disclosure in that composition. The optional bound-lifetime tests prove
only their injected setup; they do not prove normal-host root-node revocation or
live PLAYER availability. The supplied session's default role also cannot establish
actual-role or approval-withdrawal/ABA coverage by itself.

Before separately authorized live PLAYER enablement, establish an explicit
activity/session read-authority binding to actual role, viewer revision,
account/token/epoch/namespace and approval issuance. Verify normal-host withdrawal,
ABA, suspended reads, Back/reopen, session/team changes and zero writes using
synthetic dependencies. Define root-refresh behavior deliberately rather than
implicitly revoking session-wide results on every node refresh.

The raw leaderboard container is independent of legacy submission eligibility.
All existing command construction, coordinator transport, pending commands,
receipt reconciliation and command validation bytes are unchanged. Existing
submission and team-status readback remain mounted and retain their tests.

## Verification and integration

- PASS: 31 focused player Python contracts, including 10 new leaderboard checks.
- PASS: broader play contracts, 192 run; 180 passed and 12 external-source skips.
- PASS: full contract suite, 2,428 run; 2,381 passed and 47 external-source skips.
- PASS: six changed Swift files have no Tree-sitter error/recovery nodes with
  `tree-sitter 0.26.0` / `tree-sitter-swift 0.7.3`. This is syntax-only evidence.
- AUTHORED, NOT RUN: 19 Core XCTest methods and 4 App-hosted methods, covering
  visibility, empty/malformed data, scoring/ranking fidelity, public-name bounds,
  scope/revision/revocation, read failures, unknown-write preservation,
  dismissal/cancellation, reopening, both locales and accessibility-size layout.
- BLOCKED pending central integration: `check_scaffold.py` stops at source-project
  membership equality. The approved candidate excludes central project/catalog
  regeneration, so the new production and App-test files are not yet in Xcode.
- NOT RUN: Swift compiler, Apple SDK/typechecking, XCTest execution, simulator,
  screenshots, VoiceOver and live backend checks. There is no Swift/Xcode here.
- NOT PERFORMED: push, deployment, production requests, real rewards or account
  mutations.

Integrator: merge the seven entries in
`Resources/PlayPlayerLeaderboardLocalizations.fragment.json` into the existing
catalog and regenerate the Xcode project. Preserve all prior source/test entries,
run scaffold/aggregate checks, then run `PlayPlayerLeaderboardReadbackTests` and
`PlayPlayerLeaderboardViewTests` on Apple. In the normal player screen, verify
both languages, hidden→visible→hidden refresh, empty/malformed results,
Back/reopen, interrupted refresh, unknown writes, owner/read revocation before
repaint, Dynamic Type and VoiceOver. Complete the activity/session authority and normal-host composition checks above before claiming live PLAYER integration. These checks need only synthetic data.

Focused command:

`python3 -m unittest discover -s Tests/ContractChecks -p 'test_play_player*.py' -v`
