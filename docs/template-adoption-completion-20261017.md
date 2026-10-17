# Template adoption completion wiring

Source baseline: `64306a643d0243882e66f80a845bd49f42fa512c` on `migration/native-ios`.

## Closed source gap

The public play-template detail previously opened the bare authoring editor. Unlike the normal authoring launch, it did not host the existing saved-draft and publish-receipt result presentations or their owned-library destination.

The home template browser and the creator-project template detail now pass an explicit, session-bound completion destination. The detail creates a new navigation identity for each Adopt tap, captures the displayed source and request key, and retains one coordinator for that pushed visit. Reader/session changes retire the selection. Save and publish reuse the existing receipt-only completion controllers and the existing independently approved owned shelf. Read-only callers without an authoring factory remain read-only; standalone callers without a completion context retain their existing editor behavior.

No source ID is promoted to an owned-template ID. Adoption still uses the existing public-field projection; unknown writes retain their original pending identity, and only an authoritative matching receipt may show a completion. Old session, draft, close and timer checks stay in the existing controllers. No upload approval is introduced on the adoption route.

## Regression source

The existing registered `TemplateAuthoringSavedResultAppTests` and `TemplateAuthoringPublishResultAppTests` each gain five adopted-source cases:

- Source attribution survives a completed save/publish and differs from the owned receipt ID.
- Unknown outcomes neither navigate nor resubmit; reopening retains the pending journal.
- Cancelled review plus a retained confirm callback does not send or navigate.
- Same-account epoch and permission revisions reject old completion callbacks.
- Reopening a terminal visit does not replay the success panel or change source attribution.

These augment, rather than replace, the existing no-ID/synthetic/owner-change/background/draft-change/stale-dismissal cases. Tests remain in their existing Xcode app-unit source registrations. No test target, workflow or validation entry was added.

## Evidence limits and coordination

Source inspection and exact baseline-byte/hash comparison only. New and existing tests, compilation, UI/device flows, backend integration and CI were **NOT_RUN** for this change. No prior passing result applies to this candidate.

The current `IOS_START_PROMPT.md`, `IOS_HANDOFF.md` and `BACKEND_CHANGES.md` on the backend coordination branch were read before editing. This is UI composition only: no API or backend change, no contract/permission expansion, no money/rewards action, no DDL or credentials. Existing production authoring adapters and read approvals remain disabled by default. No merge, deployment or publication has been performed by the implementation worker.
