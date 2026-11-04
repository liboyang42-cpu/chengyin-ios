# L11 integration map (MOD-0 / H5-0)

Status: **PARTIAL; NOT ACCEPTED**. Both TECHNICAL_READY and
PUBLIC_RELEASE_ALLOWED are false. See `l11-scope.md` for owner, exact whitelist,
source receipt and frozen commits. This map supersedes no server authority.

## Existing implementation and actual gaps

| Required object/flow | Existing public path | Evidence and next dependency |
| --- | --- | --- |
| Author local import | `App/QmodAuthorImportView.swift` → `Core/QmodArchiveInspection.swift` → `Core/QmodManifestContract.swift` | ZIP read, safety, CRC and digests already exist. This batch rejects ambiguous/malformed JSON before a local pass. The view has no caller outside its own definition on this base; it is not a normal production journey. |
| Content package/version | `Core/WorkshopModuleImportEntry.swift`, `WorkshopModuleImportGate.swift`, `WorkshopPackageVersionPublish.swift`, `WorkshopPackageFreezeEntry.swift` | Metadata-only local state. Not persisted author submission, content compilation, immutable server version or approval. Local `reviewed` arguments cannot substitute for server approval. |
| Shared installation/entitlement | `Core/WorkshopPaidInstallService.swift`, `WorkshopOriginalInstallConsumer.swift`, `WorkshopInstallRecoverEntry.swift` | Existing paid private-draft install identity and original-request receipt consumer. Do not create another registry or use it as a player completion receipt. |
| Purchased library | `Core/WorkshopPurchasedService.swift`; `App/WorkshopPurchasedComposition.swift`; `App/AppCompositionRoot.swift` | Existing proposed `api/workshop/purchased/*` reads and install operations require approval/context. The composition has nil-default approval dependencies. No matching backend workshop implementation at the frozen commit. |
| Installation UNKNOWN recovery | `WorkshopPaidInstallPendingStore.swift`, `WorkshopPaidInstallController.swift`, `WorkshopPaidInstallService.status` | Keep original command/request ID; query status; do not re-mint a command or infer success from the current projection. This batch preserves the separate original-install consumer on launch denial and tests its unknown→original receipt recovery. It does not prove HTTP/DB durability. |
| Existing publication writer | Backend `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/CmsTopicServiceImpl.java` | Original topic publication is retained; qmod compiled-plan/version binding to it is absent, not replaced by a client freeze. Shared writer remains with integration owner. |
| Existing runtime writer | Backend `.../service/impl/TopicRouteRuntimeServiceImpl.java`; `chengyinhub-admin/.../api/ApiThemeRuntimeController.java` | Original route runtime is retained; no compiled qmod plan or H5 result adapter found. `ApiPlayRunSessionController` (`/api/play/run-session`) is a run-session projection API, not evidence of a qmod engine. |
| Evidence/reward domains | Backend existing topic runtime and `TopicCompletionCouponRewardServiceImpl.java` | No new evidence, scores, wallet or reward writer added. Rewards remain off for L11. Full evidence/venue/entitlement/Run integration still required. |
| H5 launch | `Core/H5LaunchIssuer.swift`, `H5LaunchProducer.swift`, `H5ShellParentFlow.swift`, `H5ShellLoad.swift` | Legacy issuer minted a UUID and inferred Shell origin from the API origin. This batch removes that issuer behavior; it cannot launch without a future server contract. Other low-level shell/producer primitives are not certified as domain isolation or one-use tickets. |
| H5 policy and result | `Core/H5SessionCapabilityGate.swift`, `H5PlatformHost.swift`, `H5AnswerProtection.swift`, `WorkshopRunServerVerification.swift` | Existing local gates reject self-reports but are not server sessions, validators, receipts or outbox. Neither an installation receipt nor a local hash comparison proves H5 completion. |

Frozen backend inspected read-only: `hengyin` commit
`58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4`. A `git grep` over the
admin/system production Java trees for `/api/workshop`, `/api/h5`, `/api/mod/`,
`/api/content/uploads`, `questify.mod`, `questify.h5` returned no matches.
Class/path inventory likewise found no qmod/workshop/H5 session implementation.
This is repository evidence, not a live HTTP probe. Existing mini-program routes
were not changed. Private repositories and user machines were not accessed.

## Complete journeys still blocked

1. Normal author entry → quarantined upload → server scan/schema/duplicate keys/
   five-node capability negotiation/DAG compilation → real-engine preview →
   immutable version → independent review. Companion machine contracts/examples
   are not in this checkout; only the two complete specification texts were read.
2. Existing entitlement → installation draft/venue consent binding → original
   approved publication writer → original Run → server evaluation → immutable
   original command receipt/outbox. No server engine or durable qmod request store
   exists at the frozen baseline; no speculative endpoint was added.
3. Server-issued, audience-bound, one-use H5 ticket → separately approved
   registrable hosting domain → CSP/sandbox/MessageChannel isolation → card-order
   server verifier → original task completion → result receipt and restart
   reconciliation. The hosting configuration and session/result contract remain
   absent. No public port, credential or production upload was created.
4. Native close/report controls, malicious-page WebKit tests, CN/US policy gates,
   English/Chinese production journeys and mini-program integration regression.
   Pure Core tests cannot establish these.

No AppSession/Composition/PBX/Runtime change is useful until the above contracts
exist. Therefore this batch supplies no shared-file diff and enables no entry.
L1 must keep unverified L11 entries out of normal navigation at freeze, consistent
with launch-plan section 2. Do not interpret the local safety checks as acceptance
or a substitute for missing server flows.
