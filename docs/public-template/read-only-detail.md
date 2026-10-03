# Public route-template detail

This is an offline-first, read-only native slice. It does not enable a deployment,
credential, capability, purchase, installation, adoption, recruitment application,
or a module-license endpoint. An independently reviewed public catalog/detail composition read grant is now
available; shipping composition remains unconfigured. See [the exact read boundary](composition-read-grant.md).

Contract verification: backend commit `2bb251830b25822ddbabc72f4fabde63b81686e0`.
`POST api/template/topic-template/info` uses form field `id`, an optional current
credential, and the ordinary `code` / `data` envelope. It is distinct from private
route info and standalone play-template info. No private source is included here.

The decoder is a field allowlist. Public topic/chapter/game IDs remain server IDs.
Nodes intentionally have no server IDs and use position only for presentation.
`locationCount`, `templateCount`, and chapter `nodeCount` are authoritative scalars;
missing counts remain unknown and zero remains zero. They are never recomputed from
preview rows. Detail `totalTime` is seconds. Route silhouettes accept only normalized
0–1 points and have no map, coordinates, navigation or location access.

Included games are inert previews from this response, never a second data fetch.
Recruitment uses only the returned aggregate and explicit server viewer flags.
No applicant identities, private answer/hint/story objects or raw JSON are displayed.
Optional public metadata outside this initial allowlist is intentionally not rendered.

The memory-only owner is scoped to account, role, realm and session revision.
Account/role/token/session lifecycle changes synchronously invalidate all retained
coordinators; the request epoch also fences failures before session expiration. A coordinator applies
unauthorized expiration only after accepting its current generation, so superseded,
canceled or dismissed reads cannot expire the current session; current failures still do.
Dismissal clears the projection and rejects late replies; reopening reloads it.
The endpoint/realm is immutable within an AppSession; a new realm uses a new owner.

## Verification scope

Core tests exercise the actual JSON decoder, request path/body, status precedence,
response identity, malformed shapes, preserved scalar counts, role-scoped projection,
overlapping reads, late failure, logout, account/role/realm changes and dismissal.
UI fixtures cover content, empty, loading, failure, unavailable and merchant views.
App-hosted unit coverage checks normal dormant construction makes no HTTP request,
and uses the shared coordinator construction path with synthetic reads to exercise
a real AppSession’s superseded, dismissed, canceled and current-401 expiration effects.
The separate composition recorder tests grant only synthetic public catalog/detail
requests and cover the normal transport boundary; no live deployment is enabled.
These Swift/Apple tests are authored, not executed in the Linux editing environment.
Tooling, structural and Python contract checks do not substitute for Apple compilation,
simulator tests, visual review or live deployment validation.
