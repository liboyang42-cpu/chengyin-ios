# Club operations native slice

## Implemented and mounted

- Club Home → Create club; governed Club Detail → Club workspace
- Source-canonical club type and up to three activity preferences, name/city/introduction/keywords/style fields
- Existing logo and cover preservation, member priority-signup and non-negative reserved-place form, join-policy editor only when the server declares support
- Owner-only public visibility, member-post permission and merchant-cooperation settings, with individual immutable reviews
- Owner-only legacy administrator promotion/demotion, target member/account/club IDs shown in review, two non-owner administrator ceiling, self/owner/unknown-role/duplicate-target guards
- Source-account role and owned-club preflight for creation, fresh profile/role/target reads before review and confirmation
- Account/epoch/token guards in reads; retained per-account/target coordinator with review ownership, double-submit prevention, late-result rejection, no retry and conservative unknown-outcome locks
- Bilingual native forms, native sheets and discard confirmation, text-field accessibility labels, semantic status identifiers, source-only full-bleed card with no border, Reduce Motion-aware state transition

The module is mounted in normal navigation, but production submissions are hard-off. The dormant `perform` implementation now requires an exact deployment/account/path grant, fresh authorization facts and a durable minimal pending journal; normal AppSession supplies no grant. The coordinator also refuses unverified writers. Supplying a backend URL does not enable these writes. Normal data reads remain under the existing reviewed regional configuration/session gate, with no production defaults added.

## Exact source contracts

Audited source files are `app-audit/lib/data/api/club_api.dart`, `club_topic_ops_api.dart`, `lib/data/models/club.dart`, `club_topic_ops.dart`, and `lib/feature/club/club_create_page.dart`, `club_edit_page.dart`, `club_ops_access.dart`.

| Dormant write contract | JSON body |
|---|---|
| POST `/api/club/create` | name, logo, cover, description, clubType, activityPrefs comma string, city, address, keywords, style |
| POST `/api/club/update-mine` | same fields plus numeric id, operationConfigUpdated true, integer prioritySignupEnabled and memberReservedQuota; joinPolicy only if supported |
| POST `/api/club/open-settings/public-visible` | numeric id, publicVisible 0/1 |
| POST `/api/club/open-settings/member-post` | numeric id, memberPostAllowed 0/1 |
| POST `/api/club/open-settings/merchant-coop` | numeric id, merchantUndertakeOpen 0/1 |
| POST `/api/club/set-member-role` | numeric clubId, memberId, role 0/1 |

These request builders and acknowledgment decoders are contract/test code, not live write adapters. No network mutation was performed. No retired member discount field is sent, even as null. No leader-application, dissolution, role-v2, permission-assignment, ownership-transfer, finance, payment, settlement or notification endpoint is added.

Reads use existing `/api/userInfo`, `/api/club/my`, `/api/club/detail`, `/api/club/members` source routes with the source encodings. Creation requires a matching account ID, explicit owned array, unique valid IDs, explicit ownership and effectiveRole `club`. The two-club cap is documented in the Flutter create-page intent and is a conservative client preflight, not verified live backend enforcement.

## Deliberate safety differences and gaps

- Missing or unknown openness fields are unknown and have no toggle. The Flutter display model defaults missing values to on; that default is not enough evidence to authorize a native privacy/permission change
- Live member-role reads require explicit integer role and Boolean owner facts. Missing facts fail the snapshot rather than using legacy defaults for a permissions action
- New profile text uses the source create-form maximums: 30/20/200/60/30 characters for name/city/introduction/keywords/style. Unknown legacy type/preferences can be preserved unchanged
- Profile writes compare the reviewed baseline with a fresh profile to avoid overwriting an intervening edit. IDs, role, setting and member state are rechecked
- Open-setting acknowledgments require an explicit known 0/1 field. A mismatching acknowledged value is retained as the server value, never overwritten by the requested optimistic value
- Creation can receive an acknowledgment without a returned club ID, as the source permits. No ID is invented
- Unknown outcome remains locked through readback, screen re-entry and same-account reauthentication. A successful current-state read does not reconcile an uncertain request
- Locks are in memory. Durable pending intent, backend idempotency/reconciliation and account/deployment capability approval are mandatory gaps before enabling production writes
- Owner member-list failure currently makes the workspace load fail; separate profile/member loading is a later resilience improvement
- Media upload/cropping, leader application, v2 role permission/event scopes, governance, customer management, notifications, operating hours, settlement and dissolution are not completed in this slice
- No Swift compiler or Apple SDK exists in this Linux task. Compilation, real navigation, Dynamic Type/VoiceOver, visual screenshots, physical-device Reduce Motion and backend acceptance remain NOT_RUN

## Offline fixture entry

Launch DEBUG with `--uitesting-club-operations owner` (also admin, ordinary, limit, unknown, denied, delayed, changed, readbackUnavailable, missingSettings, unverified). AppSession construction is skipped. The fixture contains synthetic in-memory data and no transport, URL, credential or disk access. Create/manage forms are reachable from the fixture root, and a toolbar exposes write count and account interruption controls. It never changes a real role, visibility setting or club.

## Integration

Integrated additively into the existing session, ClubManagementContext (optional operations context), ClubHome and ClubDetail. All existing directory/detail routes automatically carry that retained context. Authentication transitions synchronize this coordinator next to the existing management coordinator. The Settings, Home/Account editor, Official/Growth, regional storage and CN account-session paths remain intact. Project generation and exhaustive three-shard inventory include the new tests.

The isolated overlay remains in `native-club-operations-new`. The integrated source of truth is `chengyin-ios`; do not reapply old shared-file versions from any isolated checkout.

Current dispatch/persistence update: [operation adapters](operation-adapters-module.md). No production write capability was enabled.
