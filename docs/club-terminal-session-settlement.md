# P056 current-session settlement navigation

Base: f329ff5180551ef3956b2718cb9ef071e2635409 (tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd).

## Ordinary flow
The existing Club detail governance button supplies the current read-only context from AppSession. In the original workspace, open topics, then a topic. The new entry loads fresh topic activity choices through the original governance access, keeps explicit selection when multiple sessions exist, and requests fresh canDirect for that exact club/topic/activity. A sole session is selected automatically; no sessions stays empty. There is no manual ID field or invented activity.

The provider calls only the existing GET api/game/session/view?activityId=…&perspective=CLUB decoder. It captures the already accepted runtime context and read approval issuance, checks them before/after suspension, and retires irreversibly when an observed lease changes. It exposes no command API. No approval, configuration, credentials or directorCommands capability is added.

Topic review/rejection always precedes session status. Topic status1 is merely approval; date, displayed sessionStatus and an end-time guess never confer a terminal state. Only an authoritative FINISHED/CANCELLED projection with a positive session ID can open the settlement action.

At that action, topic membership, canDirect and projection are all refreshed. A changed session ID or regressed revision rejects the old action. Fresh access/me must grant club:finance:read; the existing ClubGovernanceReadView(.settlement) then independently reads the summary with its original finance check. The existing ClubSettlementRows and exact record detail remain responsible for same-topic multi-record selection and money strings. No total, payout, success or verification is inferred from terminal status.

Dismiss settlement to the same selected activity and refresh. If it disappeared, show failure rather than switch to another session. UUID-bound returns, provider revocation, source snapshot/generation, identity/epoch/namespace/authority and current UI/scene checks prevent stale routes and late responses. Repeated taps cannot duplicate a flow or settlement route.

## Delivery status
Source and normal factory wiring are implemented. Production read configuration is intentionally still PARTIAL/default closed. The ordinary root must independently supply its existing accepted .reads provider, exact endpoint approval and issuance identity; this package cannot activate it. No real network or settlement operation was performed.

This batch includes exactly three Xcode references and ten bilingual localization keys registered in its isolated candidate; the fragment remains an audit record. AppSession is delivered as a narrow patch with exact before/after blob witnesses, never as a wholesale replacement. Existing creation, governance, story and settlement contributions remain intact. Root CI and cancelled/PARTIAL unrelated features are untouched.

## Verification
33 authored XCTest methods cover fake transport/provider and access negative controls, route return, audit priority, mismatched source, finance denial, revocation, held late responses and zero writes. They are NOT_RUN because Swift/Xcode are unavailable. The local pinned Mini oracle, directed static checks, Tree-sitter parsing, actual indexed forward/reverse application and exact unchanged-tree witness are separately recorded; parsing is not compilation or App testing.
