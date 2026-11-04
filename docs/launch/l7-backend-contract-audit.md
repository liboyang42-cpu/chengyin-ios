# L7 backend contract audit — 2026-11-04

Status: source-only checkpoint. No backend implementation, database migration, capability, permission, UI, or runtime behavior changed. This is not evidence that L7 or any launch journey is complete.

## Pinned inputs

- iOS baseline: `0a56746aca42158dda20c821a1d50f089f0d5ae8`.
- Preserved backend baseline: `58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`.
- Backend launch integration observed: `integrate/app-launch-20261204` at `c6eac3b8cebf7311e8f00f208d294c3c8212aaec`.
- [Launch lane #133](https://github.com/liboyang42-cpu/chengyin-ios/issues/133) and [tracker #140](https://github.com/liboyang42-cpu/chengyin-ios/issues/140) were read. The later tracker correction removes the Hide/Modify/Repair classification; it must not be treated as an owner requirement.
- All source inspected for this checkpoint is already public in `chengyin-ios` or `hengyin`. No private repository source or history was used.

The [backend comparison](https://github.com/liboyang42-cpu/hengyin/compare/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4...c6eac3b8cebf7311e8f00f208d294c3c8212aaec) reports 876 commits ahead and 0 behind. These are different baselines. Reading the launch integration does not adopt it as the preserved baseline.

The preserved [pom.xml](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/pom.xml) already specifies Java 21 and Spring Boot 4.1.1. A framework upgrade is not needed merely to reach the launch plan's stated toolchain.

## Join-request route equivalence: rejected

The two route families have different target identities, request fields, and results. Do not change only the path prefix.

| Contract | Existing club membership review | Channel/space admission review |
| --- | --- | --- |
| iOS client | `ClubManagementService` | `ChannelAdmissionGovernanceClient` |
| Routes | `api/club/join-request/approve`, `api/club/join-request/reject` | `api/join-request/approve`, `api/join-request/reject` |
| Target | numeric `clubId` + `memberId` | application `id` + original `request_id` |
| Approval note | no note sent by this client | optional `remark` |
| Rejection | optional `reviewReason`, at most 500 UTF-16 units | required `reject_reason_code`; optional `reject_note`, at most 200 Swift characters; reason 9 requires a note |
| Result consumed | successful AjaxResult code and message | object `data` with matching application `id` and status 1 or 2; rejection also requires `join_state=REJECTED` |
| Recovery | existing club flow's readback/unknown handling | `api/channel-platform/admission/requests/{requestID}`; original request identity retained, missing receipt remains UNKNOWN |

Evidence:

1. [ClubManagementContracts.swift lines 29–36](https://github.com/liboyang42-cpu/chengyin-ios/blob/0a56746aca42158dda20c821a1d50f089f0d5ae8/Core/ClubManagementContracts.swift#L29-L36) already uses the correct club routes. [ClubManagementService.swift lines 40–64](https://github.com/liboyang42-cpu/chengyin-ios/blob/0a56746aca42158dda20c821a1d50f089f0d5ae8/Core/ClubManagementService.swift#L40-L64) sends club/member identities and optional reviewReason.
2. [ApiClubController.java lines 954–994](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiClubController.java#L954-L994) declares the club routes, resolves the current member, and returns the ordinary success acknowledgment. The same route declarations and review call exist at the observed launch integration.
3. [ClubMemberServiceImpl.java lines 417–486](https://github.com/liboyang42-cpu/hengyin/blob/58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ClubMemberServiceImpl.java#L417-L486) locks the club, checks the existing membership-approval permission, and updates the pending club-member record. This is not a generic guild admission receipt service.
4. [ChannelAdmissionGovernanceClient.swift lines 7–17 and 54–80](https://github.com/liboyang42-cpu/chengyin-ios/blob/0a56746aca42158dda20c821a1d50f089f0d5ae8/Core/ChannelAdmissionGovernanceClient.swift#L7-L80) supplies the separate routes and application/request fields. [ChannelRulesAdmission.swift lines 101–127](https://github.com/liboyang42-cpu/chengyin-ios/blob/0a56746aca42158dda20c821a1d50f089f0d5ae8/Core/ChannelRulesAdmission.swift#L101-L127) checks the application receipt; [lines 183–193](https://github.com/liboyang42-cpu/chengyin-ios/blob/0a56746aca42158dda20c821a1d50f089f0d5ae8/Core/ChannelRulesAdmission.swift#L183-L193) preserves UNKNOWN recovery.

Disposition: no club route patch is needed. Keep the channel admission routes in L8's unmet backend contract work. Do not mark the two missing routes as closed by aliasing them to club routes, dropping request IDs, inventing a club/member target, or manufacturing a receipt.

## Port inventory at immutable source heads

Counts below are the source-side changed-file lists from GitHub compare against the preserved backend baseline. Ahead/behind counts describe divergent history, not a safe merge plan.

| Slice | Source head | Changed files | Ahead / behind preserved base | Dependency |
| --- | --- | ---: | ---: | --- |
| W13 public map | `02870381b988ada5fb5d6e54bd23f72dafeae50f` | 26 | 2 / 774 | `roam_poi.visibility_version` schema prerequisite; read visibility gates must remain intact |
| W05 merchant authoring | `329ffb04641121e63b690d45dc266a6a20e03192` | 17 | 1 / 739 | candidate migration, existing NPC/source owners, approval/publication separation |
| W17 non-cash pledge | `0052c106ec53a41515b0ba35ce61043a387357e6` | 13 | 1 / 739 | candidate migration, coupon receipt integration, money remains off |
| W19 private home | `8376769d04bf74ac358dc8a59b0e6d57d907290a` | 39 | 5 / 852 | privacy/logging boundary and trusted-proof authority must be reviewed; candidate migration |

- The exact W19 branch found is `cursor/w19-d-trusted-proof`, not a branch literally named `cursor/w19-d`.
- All 26 W13 changed paths are absent from the preserved backend tree. This is a source port, not merely enabling an existing route.
- The [W13 source contract](https://github.com/liboyang42-cpu/hengyin/blob/02870381b988ada5fb5d6e54bd23f72dafeae50f/docs/w13/map-public-layers.md) explicitly requires a real per-item visibility version for roam points. Missing schema/version fails that layer. Do not substitute a constant version or report a complete map port without that prerequisite.
- [PR #398](https://github.com/liboyang42-cpu/hengyin/pull/398) is open with head `0127e3dc12509114289ef164536f83a3a9617265`, base `417ff2146245765d63335a331f49e3ea3a8b9931`, 754 changed files, and an observed dirty/non-mergeable state. Its description lists 17 design-level conflicts, including funds and frozen runtime snapshots. This checkpoint did not reproduce a merge or validate those resolutions. Do not merge it whole.
- No lane assignee or comment was present on #133 at inspection. This alone does not establish that a file or subsystem has no active owner. Resolve ownership before a production-code port.

## Safe parallel work and blocked closure

Useful independent preparation groups are:

1. Map read port: exact source/dependency inventory and preservation of query visibility, pagination, failure and retry behavior.
2. Device/private-home port: source/API compatibility and privacy review; auth or trust changes wait for their required decision.
3. Coupon/time-window/workshop slices: split by owning service and coordinate workshop with L11; funds conflicts stay separate.
4. Merchant authoring: coordinate existing NPC and merchant owners, keep approval and publication separate.
5. Non-cash pledge: preserve original coupon/receipt ownership and keep all money behavior off.
6. Personal location share and blacklist: new backend work, coordinated respectively with L5 and L9; not an existing-route rename.

A practical initial allocation is 3–4 L7 implementation/review workers plus the shared integrator, opening further slices only after exclusive ownership and shared dependencies are clear. This is a concurrency recommendation, not a one-day completion estimate. More workers cannot remove baseline, permission, schema, or integration-test gates. The route-equivalence check above is already resolved and needs no duplicate implementer.

## Validation and delivery boundary

- Ran a local offline Python source-evidence checker: 23 checks passed. Checks covered pinned route/field distinctions, receipt/UNKNOWN requirements, baseline toolchain, compare inventories, and workflow trigger exclusions.
- These are source checks, not business tests and not substitutes for Java, database, or end-to-end verification.
- Not run: Swift compilation, Java builds/tests, MySQL, Redis, runtime API calls, GitHub Actions, production operations.
- No backend source, migration, permission, auth, credential, capability, shared composition, UI, or feature-ledger file changed.
- The documentation branch is based on the exact iOS baseline. Both workflow definitions at that baseline were inspected: `native-ios.yml` push branches do not match `codex/l7-backend-contract-audit-20261104`; `native-targeted.yml` is manual only. Neither has a `create` event. No workflow dispatch or pull request is part of this delivery.
