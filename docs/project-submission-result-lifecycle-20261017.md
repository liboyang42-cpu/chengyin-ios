# Project submission result lifecycle

## Scope and baseline

Source baseline: `migration/native-ios` at `1ed4c9871d4c73c5cedb2dd7f43a4ca8e395683c`, tree `e8b113a43378341dc9f878ec65fc6341fdec8cc2`.
This is a narrow source correction to the ordinary professional project editor's acknowledged-result journey, not completion of all publishing requirements.

The existing contract in `docs/contextual-publishing/source-contracts.md` says that closing a publish result returns to its host project. That corrects the initial hypothesis that the shared close/navigation callback was itself a defect. The existing legacy two-second transition and bundle-result Done-to-host behavior are preserved. No new product action or manual-only result design is introduced.

## Verified source gap and change

Before this change, the legacy result delay was keyed only by receipt ID. Neither its completion nor the bundle Done button had an active-scene presentation lease. The navigation destination retained only a resource ID, not the submission's receipt, session and editor visit.

- A presentation-only lifecycle lease now requires a visible, active result, and consumes a completion once.
- Backgrounding and disappearance retire the timer and button capture. Returning to an active presentation creates a new timer key and runs the full existing two-second delay.
- A finished occurrence cannot complete twice. A later presentation cannot consume an earlier occurrence's capture.
- The host destination carries the exact acknowledged receipt, authenticated session and editor visit. The destination checks these again before constructing the host.
- Covering the editor with that host retires editor controls without invalidating the valid host route. Replaced session/epoch, editor visit or acknowledgment invalidate the destination.
- The result view is keyed by receipt ID. The pre-existing parent callback still verifies its exact receipt and editor incarnation before changing navigation.

The initial receipt remains an acknowledgment, not a current review decision or proof of an approved immutable release. Unknown-result reconciliation, readback, journals, provider calls and all default-off capabilities are unchanged.

## Source regression coverage

Five additional methods in the existing `ProjectSubmissionEvidenceTests` source cover background/resume, close/reopen, duplicate completion, inactive appearance, cross-presentation stale captures, host-push continuity, same-member epoch replacement before redraw, replacement editor visits, and a retired acknowledgment even when the old session value returns. They also assert retained durable storage. Existing evidence and UI expectations remain unchanged.

Manual source review covered ordinary launch composition, the two result layouts, completion callback, destination construction, the existing visit/session fences and preserved pending receipt. No test, parser, compiler, App, simulator, device, CI or real service was executed. Added tests are **NOT_RUN**. Runtime behavior, VoiceOver/large text, actual timing and navigation on Apple platforms remain unverified.

## Coordination

CY-HANDOFF: IOS. Existing author-save/result behavior, NO_API_CHANGE.
The coordination branch `codex/mini-bugs-backend-cloud-plan-20261015` was read at `60064301f61a72103e094cd9e5ec305bfe784b85`, including IOS_START_PROMPT, IOS_HANDOFF and BACKEND_CHANGES. This is a control-document snapshot, not a deployed backend SHA or permission to enable requests. No backend write, deployment, payment or new authorization is part of this change.
