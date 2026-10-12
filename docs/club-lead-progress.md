# P045: Club owner lead-progress timeline

## Entry and user flow

The ordinary ClubDetailView's existing AppSession/governance block mounts ClubLeadProgressEntry with its actual Club reader, cooperationFlowReader, creatorContentReader and governance access. Only one line is added after batch17's invitation entry. Open the page, wait for fresh owner proof and the three read sources, expand/collapse the four stations, refresh/retry, and return to the Club. Reopening revalidates and reloads. This is the source's onLeadTimelineToggle/read-progress flow, not its separate onOwnerPrimary publishing/invitation actions.

## Exact source and contracts

Unique master: MASTER-v10-extracted-text.txt P045, lines1652–1655. Mini f859cd6e2618f618a53f5cd33949259828e86313 pages/club/detail/index.js blob b49b5fb14caf49d47e971cd93ffd73cd94d8e044 and index.wxml blob033ac08d82e76b8b92853b7eda9b4c65a7ce7804.

- JS49–66 stage names/order;544 default collapsed;1146–1175 loadOwnerProjects;1234–1315 updateOwnerStage/buildLeadTimeline/onLeadTimelineToggle;1992–2003 scopedManageTopics. WXML445–455 contains the stage and collapsible timeline.
- Fresh ClubReading.clubDetail requires exact club and owner before private source reads. Admin-only entry is not inferred as ownership.
- Existing governance .topics reads api/club/topics with id=clubID.
- Existing CoopFlow .invitations reads api/coop/list. Reuses batch17's validated current-club recipient / sent-topic projection; no invitation mutation.
- Existing CreatorContentReading.projects(.init(type:"all", state:"all", ownerType:"club")) invokes api/project/my, form pageNum1/pageSize200. Exactly the Mini query: type is not bizType. Filter returned projects by clubID and bizType != activity. No new transport, credentials, permissions or write surface.

## Projection and safety

For the owner, manageable topics are all returned Club topics. With no topics the stage is publish; a received accepted invitation referencing one of those topics has execution priority and no merchant timeline; otherwise any current-club non-activity project with acceptStatus=merchantAccepted reaches accepted. Otherwise pending current-topic sent invitations select pending, else invite. Four station states reproduce the source done/doing/todo ordering. Unknown invitation statuses remain unknown rather than coercing to pending.

If projects.isTruncated is true, show a partial-data warning. Positive returned acceptance remains meaningful, but absent acceptance cannot establish the complete stage: use partial with no timeline. The project page total is global to that query, never a Club denominator or Club project count. UI topic and invitation counts are only the scoped returned data. Native waits for a coherent successful snapshot; a failed source clears the old stage rather than retaining a misleading timeline.

Invitation-time summary intentionally follows Mini's createTime.slice(5,16) and lexical display selection. It is labelled month-day, with no claim of absolute latest time across years. Source discards the year; this packet does not modify that historical behavior. Server strings are not converted to device-zone dates.

The context captures Club identity/epoch, all reader objects, CoopFlow session, governance authorizationGeneration/storageNamespace and Creator reader's rotating credential-free scope. Ordinary AppSession constructs the Creator reader from the same account and gate.currentStamp (AppSession1765–1773); the protocol does not expose its account ID, so arbitrary injected readers cannot independently prove cross-reader account equality. No new reader factory is introduced. Fresh owner loss stops further reads. Latest request and visibility permits retire queued retries/older results; canceled active reads clear loading; context changes reset expansion; leave/reopen starts a new visibility period. All old accepted data fails the live-context check.

## Existing read-contract boundary for root

CreatorContentProjectPage decoding at Core/CreatorContentContracts.swift67 defaults absent/null rows to [];70–71 defaults missing/invalid/negative total to raw row count. Therefore the current typed protocol cannot prove raw rows presence or detect a truncated page whose total was omitted. This feature consumes the existing typed result; it does not claim stronger raw-response completeness. Root/sixth owns any shared decoder/service change. See packet evidence/creator-reader-handoff.md. Real production endpoint availability, auth configuration and response shape are NOT_RUN; ordinary injection is implemented, not a claim of live deployment acceptance.

## Integration and verification

Base49c68c6420270b0a0cc7ec8d18bc8561f329d796 + sealed17 ed4c0ae93b37a20543dbc3e301c4a378c9abe7c656dd31852819b6d60ad54405. Composite preimage tree1e57b599a967328394348590fd4803fed0a6c299; ClubDetail blobc47f400ec8cc89d82a6fd5323ede0a96a65a54cf. No other dependencies. Prior packets remain immutable.

Four new Swift source/test files and23 bilingual keys are registered by central fragments. 12 Core and10 AppUnit tests are authored, all22 NOT_RUN because Swift/Xcode are absent. Focused Python structural checks, existing12 governance contracts, exact Mini source-function oracle and5-file Tree-sitter syntax checks are the executable evidence. They are not Swift typechecking, UI acceptance, Apple builds or backend validation. No production write or external action was performed.
