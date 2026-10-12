# P045 owner primary action flow

The club detail lead-progress entry now receives a live AppSession destination factory. The already-delivered timeline remains unchanged. A primary action is offered only for an accepted owner-scoped progress snapshot.

## Existing destinations
- publish: existing SessionClubProjectLaunchView; its actual editor/provider gates still apply.
- invite: existing merchant search and existing public merchant profile, without sending an invitation.
- pending: existing ClubInvitationFeedbackView, initially on Sent; every previous entry still defaults to Received.
- accepted: existing club topics list and original topic overview.
- executionAccepted: existing event topics list and original event operations.
- partial, unavailable and loading snapshots produce no action. Existing retry stays available.

On tap, the same ClubLeadProgressReadModel re-reads club ownership, owner topic IDs, cooperation invitations and ownerType=club projects. The freshly read stage must equal the displayed stage before navigation. A changed stage updates the source; it does not silently redirect. The action creates no invitation, project, payment or authorization.

Account, epoch, reader identity, project scope, namespace, governance authorization/revision, scene visibility and queued-tap generation fences apply. Source is kept mounted through its own refresh. Returning closes the immutable route and refreshes the same club through the existing model. Destination screens retain their own authorization and command gates.

## Dependencies and boundaries
All source dependencies are already in published f329ff5180551ef3956b2718cb9ef071e2635409, tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd. No dependency on later P042/P045 report/P056/P055/draft packets. Normal configuration reuses AppSession's existing club, governance, cooperation and creator readers. Default navigation context is unavailable; no API origin, approval, credential, grant or writer is created. Project editing remains unavailable wherever its existing provider is unavailable.

Existing CreatorContentProjectPage decoding accepts missing/null rows as empty and defaults total; this packet does not change that older contract. Its exact root-owned handoff is in delivery evidence. This new flow consumes the existing typed projection and blocks explicit truncation. Raw-wire completeness remains an existing dependency, not claimed solved here.

## Evidence
Master P045 pages/club/detail/index includes onOwnerPrimary. Mini f859cd6e2618f618a53f5cd33949259828e86313 detail.js 1317–1334 is executed with local fake navigation in the delivery oracle. Original WXML merchant section explicitly locates actual cooperation initiation inside a project. Original read-only lead-progress packet excluded action navigation.

31 XCTest methods are authored, including a fake vertical owner-read → stage → fresh revalidation → route → close/return read and negative scope, late callback, stage-change and visibility controls. They are NOT_RUN without Swift/Xcode. Static assertions, actual Mini JavaScript oracle and supplementary Tree-sitter syntax are reported separately; they are not Apple build or runtime tests.
