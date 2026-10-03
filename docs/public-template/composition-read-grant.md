# Public route-template composition read grant

The source-reviewed `ReviewedAppDeployment.ReadGrant.publicTopicTemplateCatalogAndDetail`
closes the normal `AppCompositionRoot → AppSession → DiscoveryService` transport gap.
It is independent of `homeAndSearch`, authentication capability evidence, and the
private-home owner/realm/role grant. Shipping composition remains unconfigured and
`reads` defaults to an empty set. Neither an API host nor a logged-in account grants it.

## Exact request surface

Both URLs are constructed beneath the same independently approved HTTPS API base,
including its deployment path. URLs must match exactly; query strings, fragments,
encoded alternate paths, another origin/base path, and other verbs are rejected.

- `POST api/template/topic-template/list`: exactly JSON `{}` and Content-Type
  `application/json`, as emitted by the existing native catalog reader.
- `POST api/template/topic-template/info`: exactly the canonical native multipart
  form with one positive integral `id`. Content-Type must carry the same valid
  boundary. Extra/duplicate fields, alternate encoding, malformed framing, streamed
  bodies, and unexpected payloads fail before dispatch.

The backend permits an optional `recommendedOnly` catalog form filter, but this
native slice does not emit it and this grant does not authorize it. Adding that
shape requires separate source/composition review.

No home/category route, aggregate template-home route, standalone play-template
list/info, private topic/node info, install/use, publication, recruitment action,
provider, or mutation endpoint is included. Optional categories in the existing
browser remain unavailable without a separately reviewed route; successful topic
catalog loading does not depend on that optional request succeeding.

## Viewer and lifecycle boundaries

Guest requests have no account, role, or Authorization header. Authenticated requests
carry the current complete account/role/token context; partially restored identities
are rejected. The local role is never an instruction to include recruitment data.
The existing decoder still requires the explicit server merchant/publisher viewer
flags and still excludes private node identities, answer/story objects, coordinates,
and applicant identities. Included games remain inert response projections.

The immutable deployment supplies the realm. Existing transport checks fence epoch,
account, role, and token before returning success or failure. The AppSession owner
still synchronously invalidates projections on context changes. A separate viewer
revision advances on every identity transition, including role-only `/userInfo`
refreshes that do not advance the login gate. This prevents role A → B → A from
making an old response current again. Discovery completion checks this revision
before unauthorized expiration as well as at the transport boundary.

The topic browser creates a viewer-bound read request and defers unauthorized
expiration until its `DiscoveryLoader` accepts that request's generation. Thus an
older 401 cannot log out after a newer successful catalog load, and cancellation
cannot expire the session. This generation belongs to the individual loader;
independent catalog consumers and unrelated home/category/detail loads do not
supersede one another. The current accepted 401 still expires the matching session.
Detail coordinator generation checks retain the same side-effect ordering. No
session, DTO projection, or provider grant is widened.

`AppSession.discoveryTopicTemplates()` remains a direct read adapter with current-viewer
401 handling. It does not own a UI load generation. Catalog UI entry points must use
`publicTopicTemplateCatalogRequest()` with `DiscoveryLoader` so a superseded UI
request cannot expire the session before its generation is rejected.

## Source facts and verification limits

Contract checked against backend commit `2bb251830b25822ddbabc72f4fabde63b81686e0`,
tree `719fca650deb4601e484e09db31fb1a9ba8e7853`: exact controller mappings and
SecurityConfig anonymous POST rules; public catalog/detail VO field types;
public-eligibility-before-count aggregation and server viewer projection in the
service. No private implementation is copied into this repository. This read grant
changes no backend schema, migration, metadata, deployment registry, or source
eligibility rules. Source evidence does not establish deployed database readiness.

`PublicTemplateCompositionTests` exercises the actual normal AppSession/transport
with synthetic requests and an in-memory vault. Coverage includes guest and authenticated
viewers, absent grants, independent home/private/game boundaries, malformed
requests and URL escapes, guest-to-member and logout, each identity component,
account/role/token ABA, stale 401, current 401, superseded detail and catalog failures.
Role-only refresh ABA uses the real AppSession `/userInfo` path with an unchanged
credential; catalog loader regressions also cover cancellation/reentry, independent
concurrent consumers, and rejecting a request captured before an ABA transition.
The existing detail tests retain dismissal/cancellation coverage. Every recorder
runs offline. Python structural contracts are supplementary only.

Apple compilation and XCTest execution require the existing unsigned CN/US/build,
Core, app-unit and UI aggregate CI gates against the exact integrated commit. No
Swift/Apple runtime pass, live deployment, credentials, provider activation, signing,
or release acceptance is claimed by local source/tooling checks.
