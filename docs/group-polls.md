# Group polls and club chat entry

Implemented against backend commit `2cd0d28327daf46e417d4673aca621a27a244ff7` and native base `89763410a1e6782552ce818764a50ce86206b1db`.

## Native flow

Existing type-4 group conversations remain in the ordinary messaging list. Team/club group history exposes a native poll composer. Type-4 poll messages render a typed card, then open fresh options/results. The composer supports 2–10 options, optional deadline, immutable review, keyboard dismissal and draft-discard confirmation. Votes and creator-only closure each require explicit review. Counts and the user's selected option come exclusively from validated server results.

Club detail now exposes the App-only club-chat entry for a server-reported owner/joined member. It reads membership again, calls the exact club get-or-create endpoint, then checks the returned conversation against the messaging list and `club_<clubId>` before opening ordinary history. A club ID is never passed as a conversation ID.

## Exact source contract

- `POST api/im/poll/create`: JSON `conversationId`, `clientPollKey`, `question`, `options`, optional `deadlineAt` in epoch milliseconds
- `POST api/im/poll/vote`: JSON `pollId`, `optionId`
- `POST api/im/poll/close`: JSON `pollId`, `expectedVersion`
- `POST api/im/poll/result`: form field `poll_id`
- `POST api/club/chat`: JSON `id`, response `data.conversationId`
- Poll mode is `SINGLE`, visibility `PUBLIC`; one vote per member, no withdrawal or change. No unimplemented anonymous/multi-select/participant-list switch is shown
- Message type 4 contains only the `pollId` reference in `extraJson`. Creation is not sent through generic IM sending
- Poll audience/write SQL currently covers club and team groups. Nearby-hangout chat is preserved, but its poll entry is not enabled
- Results permit current members or the historical poll audience. Write authority remains current membership; only the creator may close, using server version CAS
- Creation receipts contain placeholder option counts; the UI does not treat them as results. It asks for result refresh before voting/count display
- Deadlines use Jackson's numeric Date input. Result dates accept epoch milliseconds or ISO-8601 with an explicit offset; ambiguous local wall-time strings fail closed

## Safety and interruption behavior

Independent runtime features are `imPollResult`, `imPollCreate`, `imPollVote`, `imPollClose`, `clubChat`. All remain OFF in ordinary runtime dependencies. Factory grants constrain exact account, namespace, CN deployment, method/path, role, session epoch and token before/after awaits. No backend request, notification or real poll/group is issued by implementation or fixtures.

The existing operation journal retains only deployment/account-scoped operation and target IDs. An uncertain vote or closure is locked across navigation/relaunch until authoritative readback proves a recorded choice or closure. An OPEN/no-choice read never unlocks an uncertain vote. Creation may explicitly retry only its original immutable bytes and stable key while retained; after relaunch the real poll message can reconcile a matching create key. Journal failure blocks dispatch. No background polling, automatic vote/create retry, participant identities or fake totals are added.

Historical result viewing does not grant current membership. Every write refreshes both server poll state (when applicable) and the current group list. A changed version, account, role, session, membership or dismissed preflight prevents dispatch/navigation. Dismissal after dispatch retains the replay lock.

## Verification status

Authored: 27 Swift contract/state/HTTP/session tests, plus 5 synthetic UI tests covering ordinary group/message navigation, vote confirmation/cancel, uncertain result locks, creator closure review, non-creator restriction, Chinese dormant state and composer cancellation. Fixtures have no HTTP transport and bypass production session construction.

Executed locally: native Python contract suite, Python tooling suite, deterministic project regeneration/scaffold, supplementary Tree-sitter parse. Apple Swift typechecking, Xcode builds, XCTest execution, screenshots, VoiceOver/dynamic type and real backend/device acceptance are separate gates owned by CI. No local Swift compiler is present; authored tests are not claimed as passed.
