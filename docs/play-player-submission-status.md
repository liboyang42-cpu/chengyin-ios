# Player task submission status readback

This is an offline, read-only native migration candidate. It does not establish
live gameplay, merchant verification, reward issuance, coupon use or redemption.

## Confirmed source and gap

Native frozen input: commit `37b49e2602da58a33a5d2b7fa0a679aec6059e22`, tree
`583a803d314ec40152063647547278177c6d3738`. The input's index tree and publication
manifest agree. Its older local HEAD is not used as a remote revision.

Mini-program/backend source: `liboyang42-cpu/chengyin` commit
`ce61c0bbace743ff835cb297ef41c89b52181636`:

- `chengyinhub-xcx/pages/play/index.wxml:1704–1714`, blob
  `c885d8e15dea1c0cd367bfccb667e596586aa036`: the “本站任务” inline panel shows
  the player's submission status, pending verification number and rejection reason.
- `chengyinhub-xcx/pages/play/utils/player-game-module.js`, blob
  `7b97856bb0ebf1ddeff746a7f08e0813dd0c58b3`: `normalizeMySubmissions` distinguishes
  PENDING, APPROVED, REJECTED and RECORDED; only rejection exposes its reason.
- `GameSessionRuntimeServiceImpl.java:1178`, blob
  `3d8ac26f10eb50ba9c48682d9b4cc7873c7a4862`: PLAYER view reads the current actor's
  submissions from the same game session.
- `GameSessionRuntimeMapper.xml:1010–1016`, blob
  `cd90aaf2a7b36f37693a8a28a12c98cee23ce33e`: fields are submissionId, nodeId,
  taskCode, status, reasonCode and reason. SQL limits by sessionId and memberId,
  orders newest first and returns at most 50; evidence URLs are excluded.

The native `PlayPlayerGameProjection` already receives `player.mySubmissions`
through `GET api/game/session/view?activityId=…&perspective=PLAYER`. It previously
used rows only to gate existing submissions, leaving players unable to read
verification progress or why a task was rejected. No additional API is introduced.

## Behavior and boundaries

- Keep the existing task panel and current submission controls. No submission
  eligibility, command payload, retry policy or reward calculation is changed.
- Show four distinct states. RECORDED means evidence saved; it does not report the
  task passed. Only PENDING displays the verification number.
- Match the current PLAYER session/activity/team/revision/node/task. A newest row
  for another task, unknown state, malformed identity or duplicate ID is
  unconfirmed; an old approval cannot replace it.
- R1 preserves the container's read-only shape independently of legacy submission
  rows. A valid empty array has no status card. A missing field, explicit null or
  non-array value displays “status not confirmed”. The mini-program tolerates
  omission by normalizing it to an empty array, but ce61's PLAYER view always
  supplies an array, so omission cannot establish a confirmed empty native
  readback. The existing `submissions = ...array ?? []`, all command eligibility,
  API routes and write logic remain byte-for-byte unchanged.
- A readback lease retains the original owner/epoch/namespace and game session.
  Refresh failure, unknown writes, revoked read lifetime, account change and
  disappearance hide status and reason immediately on the next render. Reopening
  requires a fresh read through the existing coordinator. Queued refresh after
  dismissal does not dispatch. Late results cannot reactivate the readback lease.
- No evidence URL, reason code, teammate-private field, position, QR or payment is
  rendered. Rejection copy is server text and rendered verbatim.
- W03 server-authority boundaries apply. W16 teaming, W19 home/resource restoration
  and W20 city settlement are separate scopes and are not implemented here.

## Validation

Focused Python source contracts and supplementary pinned Tree-sitter checks are
available. The Swift tests cover four-state mapping, rejection aliases, malformed
and duplicate rows, exact task identity, old approvals, refresh failure, account
replacement, session replacement, dismissal/late responses, cancellation and
fresh reopen. App-hosted tests cover empty/unconfirmed rendering, both locales
and accessibility text sizing.

Swift XCTest, Apple compilation, simulator UI, VoiceOver, screenshots and live
backend acceptance have not run in this Linux workspace. Static checks cannot
substitute for those results. The localization fragment must be merged by the
integrator into the existing catalog; this candidate does not edit the main
catalog, PBX project or CI.

Run focused static validation with:

`python3 -m unittest discover -s Tests/ContractChecks -p test_play_player_submission_status.py -v`

Apple follow-through: execute `PlayPlayerSubmissionReadbackTests` and
`PlayPlayerSubmissionStatusTests`, then open a synthetic task, refresh PENDING to
REJECTED/APPROVED/RECORDED, interrupt/reopen and switch accounts while a read is
pending. Confirm there is no stale reason, accidental success wording or write.
