# Personal theme backpack integration

Base: `8471b69d1f33c5fd11f132a1be7dfd229ec7168d` in the public iOS repository.

## Delivered code

- Personal `USE`, `DISCARD`, `RECEIVE` only. TEAM, trades, quests, chapter progression and zero-HP actions are not part of this writer.
- Existing read-only display/fixture construction remains supported. A separately injected `PlayThemeBackpackActions` provides native buttons, a confirmation sheet, progress, original-request retry and unavailable states.
- Before dispatch, an independently encrypted CAS journal saves the original account/realm/role, activity/topic, session ID, version, action ID, operation and exact JSON body. Replays do not replace IDs, versions, selection order or omitted fields.
- A current-process dispatch remains active. An old-process record may be explicitly reclaimed. GET projections never acknowledge a POST. Only a validated response to the exact POST/replay can be persisted as acknowledged and cleared.
- Acknowledged results are checked against original session/topic/activity and `expectedVersion + 1`; newer projections are not overwritten by an old replay. A fresh regressing read blocks new actions.
- Account, role, realm, epoch, view lifecycle and issued reader lifetime are checked. Cancel/background/account changes never erase an unresolved command. Storage failures have no memory fallback.
- Active reservations and known capacity failures are blocked before new requests. Server rejection remains unresolved because the public envelope has no immutable proof that this particular original action never committed.

## Shared-owner integration

`l5-personal-backpack.diff` is a proposal against the exact base, **not an applied shared-file change**. It covers:

1. Explicit `RuntimeDependencyConfiguration` acceptance and issuance fields, all false/nil by default. Reads do not grant writes.
2. An AppSession factory retaining actual role/owner/viewer fences, exact separately approved endpoints and the fixed OS storage factory. Its selector bypasses cached runtime configuration and rechecks the current approval at every boundary.
3. The existing auxiliary store's normal backpack construction, keyed by acceptance and the same parent reader lifetime; obsolete instances are suspended.
4. The normal SessionPlayRuntimeView consumer and successful-action callback to refresh the parent route.
5. A dedicated CompositionHTTPTransport read/write exit. It verifies a one-use exact durable POST permit and fresh approval before and after dispatch. Generic send remains unchanged and closed for these routes; GET state is not admitted through a generic read flag.

**This proposal is not permission to activate a new production grant. The shared owner must obtain the required approval before enabling a new capability.** Apply/reconcile it only through the shared-file owner. New Core files require the normal project generator/manifest registration. This delivery does not modify the project, manifest, workflow, production acceptance or endpoint permissions. A lane branch without this composition remains read-only in the normal App.

Required new production files:
- `Core/PlayThemeBackpackActions.swift`
- `Core/PlayThemeBackpackRecovery.swift`
- `Core/PlayThemeBackpackDispatch.swift`

New native tests:
- `Tests/CoreTests/PlayThemeBackpackActionsTests.swift`
- `Tests/CoreTests/PlayThemeBackpackRecoveryTests.swift`
- `Tests/CoreTests/PlayThemeBackpackDispatchTests.swift`

## Completed-session backend blocker

Frozen public backend `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4` accepts a completed-session RECEIVE branch, but `TopicRouteSessionMapper.updateStateCas` requires `status=0`. Completed sessions have status=1, so that branch rolls back with 409. `themeBackpackCompletedReceive` remains false until the backend owner fixes and verifies this contract. The UI reports this unavailable state; the confirmation/owned-item selection path is not enabled by default.

Sources:
- [themeAction and exact stored replay](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/TopicRouteRuntimeServiceImpl.java#L4539-L4595)
- [CAS mapper](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-system/src/main/resources/mapper/business/TopicRouteSessionMapper.xml#L85-L88)
- [Original personal client behavior and copy](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-xcx/pages/play/utils/theme-backpack.js#L209-L251)

GET `theme/state` is not a side-effect-free receipt lookup: a running session may synchronize/version-update and broadcasts may be marked delivered. Explicit `sessionId` preserves the original run; the response's activity is independently checked. No production requests were made during this implementation.

## Verification limits

The new Python source-contract checks inspect the actual candidate. They are not Swift runtime tests. Swift/Xcode, XCTest, native UI, device storage and backend end-to-end tests were not run on this Linux worker. Existing fixtures and assertions are unchanged. No CI, PR, public comment, production transaction or main/integration update is part of this delivery.
