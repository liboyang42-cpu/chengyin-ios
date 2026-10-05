# Native live Roam session

The ordinary Roam entry now composes a real stateful session controller and service. It is dormant in the shipped app: there is no approved live configuration, enabled OS provider, endpoint grant or location purpose string in this change. Browsing and opening the screen do not ask for location or create a session.

## Business behavior

- Prepare reads protected recovery metadata locally. Start requires the displayed foreground-location purpose to be accepted, an explicit gesture, a scoped approved service and a fresh device fix. A manually chosen map/search centre is never accepted as location evidence.
- CN fixes are projected explicitly from WGS-84 to GCJ-02 using the existing audited projection. Fix age must be between -2 and 30 seconds and accuracy at most 80 metres. Out-of-order samples and jumps are rejected; movement under 3 metres is ignored, jumps over 120 metres reset the anchor without distance or tile credit. Resume starts a new anchor, so paused gaps never become distance.
- A lowercase 32-character clientSessionKey is stored before the first reveal. POST reveal uses sessionId=0 only with that stable key. Batches contain at most 200 geohash7 tiles. No random or demonstration coordinate enters production requests.
- The write-ahead journal persists the pending reveal/finish marker before dispatch. A timeout, malformed response, cancellation, app interruption or write-back failure leaves the record recoverable. GET session by the same client key is read-only. An ACTIVE or appropriate NOT_FOUND response permits an explicit subsequent resume; it never automatically repeats a reward action. Finished facts with unresolved tile batches remain blocked for review.
- Reads populate nearby Roam POIs and registration shops. Discovery is an explicit user action, gated by a new fix and the source radius + 30 metres. Shop visits use 100 + 30 metres. Registration shops use map/nearby's id and sourceType=2, never nodeId/topicId. Roam merchants use sourceType=1 and the Roam POI id. A shop is confirmed only by recorded=true. Discovery XP fields are not rendered as awarded XP.
- Arrival targets are write-ahead locked before dispatch. Ambiguous discovery/shop outcomes are not automatically retried and remain locked across relaunch/recovery. A final complete server settlement is the authority for aggregate reward and shop totals.
- Presence has a separate endpoint grant and user opt-in. Reports occur no more often than every 30 seconds while actively moving in the foreground. Pause, back, background and finish stop reporting. The screen correctly states that previous visibility can last up to the backend's five-minute expiry; it does not promise instant disappearance.
- Finish drains pending tiles, writes its intent before dispatch, then reads GET session. Only a matching FINISHED fact with all required settlement fields can display confirmed rewards and enter history. History-write failure retains the fact and journal for readback/retry. Repeated archiving deduplicates by server session id.
- Precise locations, live route samples, neighbouring people and tokens are not persisted by the recovery journal. It stores protected account/deployment/namespace-scoped key, coarse pending geohashes, measured aggregate distance and operation/target identities. The route sketch is ephemeral. History stores measured distance and server-confirmed settlement totals, not fabricated route samples.

## Composition and lifecycle

`NativeRoamLiveDependencies` defaults to dormant. A reviewed composition can inject `approved(approval:transport:)`, or a deterministic test provider. `RoamLiveApproval` requires the CN market, exact deployment, namespace, account and complete endpoint set. Presence is independently opt-in. `RoamLiveService` captures the full credential/epoch session and rechecks it around every request. Account or token replacement invalidates the controller and clears private in-memory state.

Real-device acceptance still requires the reviewed `NSLocationWhenInUseUsageDescription` to be installed, legal/privacy acceptance appropriate to the deployment, explicit screen consent, OS When In Use authorization and acceptable precision. There is no background location mode, always-authorization request, remote configuration bypass or launch-flag live grant.

## Related native surfaces

- Rules are a normal native sheet available before and during a walk. They describe implemented native behavior and do not invent legal terms, fixed rewards or retired Hangout behavior.
- History detail now has a local card renderer and explicit system save/share sheet. Optional route sketch defaults off. Rendering never uploads or posts; the user chooses an export destination. Current-mini public-square snapshot/posting channels are not claimed as implemented by this local export.
- Roam's Nearby Teams entry reads the existing typed TeamCoordinator `/my` path before passing owned rows. An unavailable/error result is no longer disguised as successful empty My Teams data.

## Verification boundary

Added Core XCTest cases exercise consent, dormant/scoped gates, protected storage failure, keyed bootstrap, unknown outcome/relaunch, cancellation, location freshness/accuracy/jump filtering, pause/resume, identity replacement, source-domain mapping, explicit arrivals, uncertain target locks, finish/readback and archive. DEBUG-only UI fakes cover Start → Pause → Resume → Finish and unknown bootstrap → readback → explicit resume. Fakes have no HTTP transport or OS location manager.

Local checks are Python source-contract tests and pinned Tree-sitter syntax parsing only. Swift compilation, XCTest execution, simulator/device behavior, visual/accessibility review and live backend acceptance must be run in Apple CI/the approved test environment. No live mutation, OS permission request, third-party message, public deployment or store release was performed to validate this change.
