# P089 cooperation inbox topic scope

Normal flow: My account → Cooperation → Topic scope → choose a loaded topic → switch received/sent, open the existing invitation detail or candidate destination → Back → Show all topics. No manual ID entry. Options derive only from successfully loaded invitations/applications/registrations; visible source names are retained when supplied, with exact topic IDs always shown.

The scope is local display state, not an ownership or permission claim. It binds to the reader object and reader scope and clears on account/authentication changes. A stale picker closure cannot replace the current selection. Direction changes keep the chosen topic; if it has no rows in the new direction it remains selected until explicitly cleared. Refresh preserves the same-scope selection but never invents rows/options from failed sources.

All three existing native source sections use exact topic IDs. Missing topic rows are excluded only while scoped. Original order, duplicate server IDs and original ordinal view identities are retained. Section errors, partial notices and registration hasMore warnings remain unchanged. Clearing shows all loaded rows without making a new request or resetting navigation. Existing invitation/candidate routes are unchanged.

Source: master P089 and real Mini pages/coop/list/index.js blob b8ee043546dd7fda8da0886b687703787cb80ede, applyTopicFilter/clearTopicFilter/onTabChange. Mini supports a topic-scoped entry; this native affordance selects among already loaded topics on the existing inbox. It does not add a missing official-invite endpoint, payments, subscriptions, writes or any canceled action.

One new Core source is registered in the existing app sources phase. Core tests use the existing SwiftPM discovery. EN/ZH supplied. Full after is private /tmp; future brand-image App rename belongs to root and must be preserved when merging PBX. Native tests are authored, NOT_RUN (Swift/Xcode absent).
