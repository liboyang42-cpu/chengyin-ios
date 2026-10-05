# Chapter thought claim-only synchronization

Current mini exposes a capability beyond Flutter's legacy chapter-description renderer: reading a reached `thought` block can claim its thought. This packet implements the native runtime contract with a separately default-off `thoughtClaims` grant. There is no WeRun, HealthKit or fabricated native-step substitution.

## Source contract

- Mini `pages/play/index.js:2866–2887`: deduplicated claim keys and JSON POST `/api/play/journey/thought/sync`; `:3037–3045` collects only unknown thought keys before the first blocked/incomplete node; `:3056` initiates sync after projecting the visible chapter
- Mini `pages/play/index.js:586,2878–2879`: topic metadata plus activity scope when playing an activity; otherwise topic-only scope
- Backend `ApiPlayJourneyActionController.java:89–104,110–128`: claim-only sync is explicitly valid without encrypted WeRun data; missing reading is represented server-side, not by a client step count
- Backend `TopicRouteRuntimeServiceImpl.java:324–362`: scope/active-session checks, source claimability, per-key initialization only if not already earned, CAS update and incremented route version

The native projection only collects reached keys and never renders an unknown thought's authored name. The request has `topicId`, optional `activityId` and `claim` only. It sends no step count, encryptedData, code, iv or fabricated expectedVersion. The response must belong to the same route session and increase its version. Only fresh nodes/route readback displays earned thought facts.

An ambiguous claim stays pending within the retained runtime, blocks further base completion using stale route authority and offers readback only. Ordinary refresh/reopening does not automatically resend that pending claim. Auth/route-session changes discard the old view context; the server's per-key initialization is idempotent, and a new runtime must load authoritative state before collecting claims again. No local thought score, progress, reward or earned name is invented.

The SwiftUI task identity is stable during its own refresh, so snapshot clearing cannot cancel the very readback the sync initiated. New source snapshot changes can discover later reached thought blocks, while in-flight/pending guards prevent duplicate dispatch.

Six domain tests are authored for the claim barrier, exact JSON fields, cross-scope rejection, default-off grant, fresh readback and uncertain-outcome no-retry behavior. Static source checks, project regeneration and scaffold checks pass. Swift/Xcode, simulator/visual/accessibility and all backend/provider execution remain NOT_RUN in this executor. No live calls or sensor requests were made.
