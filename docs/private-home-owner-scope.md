# Private home: inactive native owner settings slice

This document records the original owner-settings packet. The later bounded [session-composition follow-on](private-home-session-composition.md) adds explicit opt-in transport and durable-journal wiring; shipping remains unconfigured. The original packet boundaries below are historical, not an activation instruction.

## Contract evidence

Native baseline tree: af6f4312d437cfa1b41558784c44801f13e14614.
Backend reviewed commit: c37bbd27ff6d15e6735484a0e82854b2496b2a24; tree c1150dc0db873ea400d0ccb7813650f0e3dbfbe1.
Verified public transport facts from ApiPrivateHomeController (blob ab8d771cc1f5d9c85e3b76f7a2d54557857f9717), DTO contract (61e9eb241911d8153e0bf150bc8a82e67984f2fd), and validation facts (57a907833a2ecab44e4e097af547fdb95d8c8a03).
Only conditional GET/PUT/DELETE api/native/home. AjaxResult code/data envelope; no proof or restore route. WGS84 six-place maximum, label <=40 UTF16 units without surrogate/control values; mutation request IDs 1..64 token characters. Payload never contains caller ownerId. No private backend implementation copied.

## Scope and explicit gates

AccountView's optional coordinator defaults to nil. Production account entry shows unconfigured content. Both service and coordinator default disabled. This packet does not change runtime route grants, AppSession, feature configuration, authentication, location permissions, keys, server adapters, or production activation.

A concrete Keychain journal candidate is supplied in the separate follow-on, but is not composed into production and has not run against Apple Security. Without approved integration of that durable journal, reads may be composed only under separately reviewed authorization and writes remain unavailable. Fixtures are DEBUG-only, synthetic and in-memory exclusively for tests. They are not a production fallback.

The future confidential journal must retain exact pending mutations across process death and logout, atomically insert-if-empty or accept identical retries, atomically compare full pending mutation identity and content tag on clear, reject cross-account/realm access, and throw on unavailable/corrupt reads. Never log payloads, store them in defaults/plain files, or silently erase an unknown outcome. Only a matching validated receipt settles a mutation. GET refresh alone cannot settle it. A conflict settles the old request and requires a fresh read and new explicit review.

## Future composition hunk (not authorized/enabled by this packet)

After exact owner-route permission and secure-journal review, extend the existing runtime composition seam to supply:

1. PrivateHomeService with approved APIConfiguration, injected no-cache/no-logging HTTPTransport, immutable PlayExperienceSession owner and current-session closure. Do not construct URLSession in this feature.
2. PrivateHomeSecureJournaling scoped using the canonical deployment namespace and account ID. Do not use UI language as realm. Scope must match the owner.
3. PrivateHomeCoordinator with the same owner/current closure and reviewed secure journal.
4. Pass that coordinator into AccountView(privateHomeCoordinator: ...), respecting its existing account and callback argument order.
5. Synchronously call coordinator.invalidate() before logout, account/realm/token revision or session replacement; invalidate old retained instances and discard them. Epoch fencing suppresses late responses; synchronous invalidation also clears displayed confidential values before another operation.

Never wire the DEBUG fixture journal into production. No shared/public map, NPC or merchant-ownership integration is allowed. Private home is App-only and does not establish W20 ownership.

## Verification

Authored Swift Core, AppUnit and UI tests use synthetic coordinates and recording/fake transport only. They cover exact body/headers, missing journal/default-off, explicit review cancellation, unknown outcome and coordinator recreation, matching replay, failed storage read/save/clear, conflict/new request, logout, scope mismatch, strict input, maximum version, and delete duplicate submission.

Local gates are Python source contracts, Tree-sitter syntax only, deterministic Xcode project regeneration and structural catalog checks. Swift compiler, Apple SDK typecheck, Core XCTest, AppUnit and simulator UI runtime are NOT RUN here. They require authorized publication and exact-commit Apple CI. UI timing estimates remain unmeasured; merge the supplied estimates and run shard feasibility at the publication boundary. Do not claim this slice production-ready or that native publication cancellation is resolved.
