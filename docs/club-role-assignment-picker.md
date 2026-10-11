# P054 guided role assignment selection

## Exact source and independent base

Base: `41571fed5c27d4766d0bebb02e2800d798f1edbd`. No overlay dependencies. The ten earlier packets remain sealed.

The only master is `MASTER-v10-extracted-text.txt`: P054 lines 1688–1691 lists `openMemberPicker`, `pickMember`, `openRolePicker`, `pickRole`, `assignRole` and cancellation actions. P045 lines 1652–1655 provides the role-management entrances.

Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:

- `pages/club/roles/index.js`, exact Git blob `82e53cfd9b3b3aa37d0857ea41828036f7c50221`: lines 93–147 project scoped definitions and members; 210–354 load permission/roles/members; 355–396 select, cancel and build assignment payload.
- `pages/club/roles/index.wxml`, exact Git blob `b2e136c3613b36a4954e81bc868032e06584c30f`: named member and role selectors, selected names and scoped role summaries.

Verified gap: the existing native `.assignRole` form required a manually typed `targetMemberId` and offered static role choices without loading the actual option catalogs.

## Flow

The existing ordinary `ClubGovernanceCommandForm` mounts `ClubRoleAssignmentPicker` only for `.assignRole`, passing its actual scope, identity and governance access. No fixture-only callback or new session composition is used.

The form reads `.roles` then `.members` through the existing `ClubGovernanceAccess.read(..., check:)` interface. The existing service performs its normal access preflights; both accepted snapshots must prove `ROLES` / `canManageRoles` for the same club/activity scope. A denied first read never dispatches the member read.

The user expands the member selector, chooses a named member identified by `memberId`, then chooses a returned role with its scope and summary. Inline disclosure selectors avoid another sheet inside the existing command sheet. Cancel closes a selector without changing either field. Names and member IDs are shown together to distinguish repeated nicknames. No role is auto-selected when opening this form.

Preview becomes available only when both fields are valid current catalog choices. It invokes the unchanged existing `coordinator.prepare(draft.command())`. That coordinator re-reads the roles and checks the selected member again. Existing review cancellation, confirm permission, durable journal, unknown-outcome locks, request IDs, fresh readback and acknowledgment behavior remain authoritative. The confirm method is byte-for-byte unchanged.

This feature does not enable a write capability. Ordinary confirmed assignment still requires the existing deployment authorization and service gates. No real role assignment, message or other backend write was performed.

## Scope and unknown data

- Club-scoped choices are returned `CLUB_CO_OWNER` / `CLUB_OPERATOR` definitions. Event-scoped choices are returned `EVENT_LEAD` / `EVENT_CHECKIN` definitions. No missing definition is synthesized from the static list.
- Definitions must have the expected scope, a nonempty source name and the existing permissions-array shape. Duplicate role codes fail explicitly.
- Owner rows are excluded. An unknown `isOwner` value is not defaulted to false; that member is omitted with an explicit unverified-identity notice. This is stricter than Mini's owner-only exclusion and exactly matches existing native `coordinator.memberProof`, which requires `.bool(false)`.
- Member IDs must be valid and unique; merchant/record IDs are never used. A contradictory club identity fails the read.
- A genuinely empty assignable roster, denied authority, a read failure and unverified eligibility are distinct states.

## Lifecycle

Read ownership is attached to the whole form, not a lazily recycled Form row. The form binds its exact read context without publishing during body construction. Visibility permits, request generation and a fresh snapshot UUID reject stale retries and stale rendered choices. Account/epoch, authorization generation, access instance and club/activity scope are checked before reads, between the two reads and after completion.

Leaving the form retires pending responses. A live editing closure prevents delayed selection/reload callbacks from altering a draft while preparing, displaying a review or locked after an outcome. The original draft bindings still handle dirty state and cancel the old review when a user makes a fresh choice. Refresh revalidates any retained member/role IDs against the new catalogs; changed or removed options cannot be prepared.

## Registration and evidence

The registration fragment lists one new App source, one new Core source, one Core test file and one AppUnit test file. Merge its 11 bilingual keys centrally. No PBX, aggregate catalog, CI, shared fixture host, AppSession, governance views, coordinator, command schema, base draft, service, validation or permission changes are included.

Executed in this workspace:

- 29 focused structural assertions: PASS, including exact preservation of confirm and all protected service/permission files.
- Existing governance contract suite: all 12 checks PASS.
- Both Mini blob hashes, eight projection cases and member/role open → pick → cancel retention / scoped assignment payload oracle: PASS. Source assignment calls were intercepted by a local payload spy; no network was used.
- Five changed/new Swift files: Tree-sitter parse PASS with no recovery/diagnostics. This is syntax evidence only.
- `git diff --check`, complete before + patch reconstruction, reverse-apply check and all ten sealed-prior SHA checks: PASS.

Authored: 11 Core tests and 10 app-hosted tests, including actual existing coordinator prepare/cancel with synthetic access and zero sends. **All 21 Swift tests are NOT_RUN**: Swift and Xcode are absent. No native build, simulator UI/VoiceOver test, screenshot, real-account read or live assignment acceptance occurred.

Apple acceptance after registration: club/event scope; owner exclusion and unknown ownership; repeated nicknames; selected-name consistency; cancel/reopen both selectors; preview/cancel/change selection; scroll long lists without restarting reads; source refresh; denied authority; stale old row tap; interrupted first/second read; account/epoch/role/region and scope changes; large Dynamic Type and VoiceOver; unchanged confirmation gate. Do not execute real role changes without separate authorization.
