# Customer directory read authorization

This narrowly ports the reviewed directory policy onto native baseline commit
334b93752e26bc4f005f7aec3e5bc3fa89a15947, tree
09334269bacd076a5cdb4da03a5da1b4ec0156ea. The reviewed policy source is local commit
ada71dbd10f630c683b4cb37c87a6c9ebb22a4f3. A new integrated candidate needs its own
verification; this document does not transfer an earlier test verdict.

MASTER-v10 P044 identifies the club customer directory and P043 its existing
detail route. Both Mini pages use the club member-management access gate. The
three backend CRM list, count, and detail endpoints all require club governance:
owner, active legacy administrator, or matching club-wide member-management
permission. Contact-list visibility is a separate server-side phone-text policy.

The native CUSTOMER_DIRECTORY selector precedes generic permission/event
fallback and controls only customers, customer and customerCount. Valid current
scope and active same-club evidence remain mandatory. Operator or co-owner role
labels alone, contact visibility alone, event-only grants, a literal selector
permission, invalid scope and foreign-club evidence cannot authorize a read.
The server still decides; no client role or server permission is granted here.

The existing workspace and customer-history route consume the same selector.
Existing transport/session/viewer/authorization-generation/cancellation fences,
request payloads, phoneText shaping, endpoints and write capabilities are kept.
The saveCustomer write selector is unchanged, but its existing reviewRead is
customer: its prerequisite read therefore correctly requires the same directory
policy. This indirectly tightens that preview path; it does not add a tag editor,
acknowledged-save readback, write dispatch or retry behavior.

Only two already registered Core source files carry production changes. Their
complete prior content is restored by exact whole-file hashes and bounded
inverse spans. The original production-test fixture receives member-management
in its allowed directory case; all original methods and assertions remain.
The new seven Swift cases preserve allow/deny matrices, denied access-only reads,
exact payload/server phone text, server denial and both cancellation stages.
Their options dictionary is literal, so no separate query-presentation feature
is imported. Their unrelated check-in expectations describe the unchanged
published baseline, rather than importing a different check-in policy.

The public Python source gates do not need private source access. Three explicit
backend provenance checks are retained in local verification evidence with
their pinned source hashes. Public discovery never reports those unavailable
checks as passed or skipped. Those checks inspect Java source, not executed
server behavior. Private-source paths and oracle bodies are not distributed
with the public gate. No scanner ignore is added for provenance checksums.

Central admission appends exact source inverses and support hashes without
changing earlier rows, UI methods, costs, shard counts or deadlines. The scanner
input adapter is independently scoped to this change. It admits all new inputs,
then reconstructs the entire exact historical contract before the existing
scanner test evaluates its original assertions. Historical findings, line IDs
and ignores stay unchanged; new text receives no old ignore. The current raw
contract still has a strict digest and is not generally interchangeable with
other JSON encodings. The input adapter also accepts the exact original baseline
only with its exact old readiness reader and no new support files. It rejects
mixed baseline/current source, reader and support states.

PBX, Package.swift, resources, UI, commands, service, coordinator, validation,
server and Mini source do not change. Filter/keyword presentation, check-in
presentation and permission, topic-customer policy, notification refresh and
acknowledgement, tag editing and save readback are outside this increment.

Verification is intentionally bounded to source contracts, exact inverses,
negative controls, original relevant gates and patch/tree replay. Swift type
checking/XCTest, Apple compilation, actual navigation/VoiceOver/device behavior,
live backend authorization, full aggregate CI and publication remain NOT_RUN
until actual platform results establish them. No real notification or business
write is part of this source verification.
