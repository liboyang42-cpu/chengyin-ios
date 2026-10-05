# Native App Attest enrollment follow-on

Code and synthetic-test preparation only. No actual App Attest key, enrollment, revocation, permission, signing entitlement, service credential, production setting, deployment or reward is created or enabled by this packet. The original motion/reminder packet is unchanged; this follow-on applies against the frozen integration-56 native tree `1a02f549b654af1860886b2b1cea6e3b8227ec70`.

## Native behavior

The normal steps screen now links to account-bound device verification when the independently reviewed enrollment policy is provided. Existing `NativePlatformAcceptance` adds an optional nil-by-default enrollment policy. Status, key creation/enrollment and revocation have explicit independent off-by-default grants, require approved endpoint paths, and require a reviewed full App ID, production environment and signing/distribution policy. UI language never selects the app, server or credential namespace. Missing or mismatched configuration fails closed.

A user first reviews creation of persistent device verification, then chooses to create a key and prepare its attestation. Before SDK key creation, the app rechecks server availability and saves an operation journal. It persists Apple's opaque key handle before requesting the bound server challenge. The DeviceCheck adapter decodes the exact 32-byte `challengeBase64`, hashes those bytes once with SHA-256, and calls `attestKey` using that digest. It does not hash Base64 text, pass the raw nonce as the hash, or use a development/alternate-wire fallback.

Preparation does not submit the proof. A second review identifies the account/app and explains transmission of the opaque key identifier and prepared Apple attestation to the activity service. Only that confirmation sends the frozen proof. An ACTIVE status is shown only after a matching authenticated status readback. Raw key handles, attestation bytes, nonces and auth tokens are never displayed or logged. The UI shows only a short local fingerprint.

The Keychain journal is isolated by deployment namespace, account, full App ID and production environment; it is unlocked-only, ThisDeviceOnly and non-synchronizing. The SDK private key is never exported. Pending proof is persisted before enrollment, so relaunch/login to the same account can read status or retry the identical saved payload. Unknown outcomes never auto-generate another key. Definitive scoped server refusals preserve the rejected proof until the user explicitly reviews a replacement operation.

DeviceCheck has no cancellation API for these calls. A late generated handle or attestation is therefore saved under its original account scope even after background/logout; every subsequent network action is fenced. A late callback cannot overwrite a newer explicitly reviewed operation. A saved key known not to have entered attestation can explicitly request a fresh challenge and continue without generating another key. An uncertain challenge issuance is not labeled an idempotent retry. Uncertain SDK attestation operations require a status check and a new explicit key review rather than silently repeating attestation against a possibly single-use key.

Revocation has its own consequence review and explicit action. The app retains the journal and waits for matching REVOKED status readback. Unknown revocations support status lookup or explicit same-key retry. Logout, backgrounding and view dismissal do not revoke the key. Revoked keys are never reactivated or reassigned; a future new key requires another explicit enrollment. SDK key deletion is not claimed.

A server-confirmed ACTIVE stored handle can feed the existing step assertion provider. Step submission rechecks that the current handle still matches its original challenge. The shared assertion adapter/service now require canonical Base64 with decoded size 1..4096 bytes, matching the new strict backend verifier. All step samples remain audit-only with no reached/score/reward effects.

## Frozen transport

Backend document: `docs/native-platform/app-attest-enrollment.md` in the private backend follow-on, coordinated with its sole owner. Document SHA-256 at freeze: `54241c96c3a028bf8056f7c19f239d3d8d08a58b19b233ec578a2cac4d23278a`. Follow-on publication was not yet verified when this packet was prepared. It is not deployed. The earlier platform checkpoint is `2cd0d28327daf46e417d4673aca621a27a244ff7`, private branch `migration/native-ios-platform`, PR #1188; it does not by itself contain the later verifier/enrollment implementation.

- GET `api/native/device/status`, optional `deviceKeyId`
- POST `api/native/device/enrollment-challenge`, exactly `{provider,deviceKeyId}`
- POST `api/native/device/enroll`, exactly `{provider,deviceKeyId,challengeId,attestationObject}`
- POST `api/native/device/revoke`, exactly `{provider,deviceKeyId}`

No JSON body chooses `accountId`. Authenticated responses must match protocolVersion=1, provider=IOS_CMPEDOMETER_V1, account, selected key, approved full appId and environment=production; rewardEnabled and hardwareVerified must both remain false. Status reads recognize DISABLED/UNENROLLED/ACTIVE/REVOKED; challenge issuance requires CHALLENGE. Disabled responses may have null appId and cannot start a device operation.

Keys must be canonical standard Base64 for exactly 32 bytes. Challenges require a 64-character lowercase-hex ID, exactly 32 decoded nonce bytes, positive epoch-millisecond timestamps and TTL <=5 minutes. Attestation objects must be canonical Base64 decoded to 1..65536 bytes. Exact proof/challenge retries are idempotent; permanently revoked keys cannot be re-enrolled. Backend rate/active-key quotas and cryptographic verification remain server-owned.

The backend-owned synthetic transport fixture is copied verbatim as `native-app-attest-enrollment-v1.json`, SHA-256 `115aa88dfdfb973f47a4848a6144c1272c2ef39e09ed4b457a2ff618375e26cc`. It contains fictional identifiers and no attestation/key material. Nonce bytes 00..1f hash to `630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd`. Existing 18-line step proof canonicalization remains unchanged. No private backend implementation is copied.

## Apple and security boundaries

Primary SDK references: [generateKey](https://developer.apple.com/documentation/devicecheck/dcappattestservice/generatekey(completionhandler:)), [attestKey](https://developer.apple.com/documentation/devicecheck/dcappattestservice/attestkey(_:clientdatahash:completionhandler:)), [server validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server).

App Attest verifies app/key/request provenance, not physical walking, who carried the phone, or an independently attested iPhone hardware class. The native adapter limits its own use to iPhone, but makes no stronger cryptographic hardware claim. The strict backend production/environment/extension dialect still needs security review and genuine-device compatibility evidence. Native treats opaque Apple proofs as untrusted service inputs; it does not add CBOR/ASN.1 parsing or implement cryptography beyond standard SHA-256.

Preativation remains blocked on approved full App ID (which is not inferred from Team ID), signing/entitlement/distribution policy, trusted server root provisioning, backend/verifier deployment and security review, actual authorized physical-device enrollment, and passing Apple runtime tests. No genuine-device positive proof exists in this packet.

## Verification and integration

See `native-app-attest-enrollment-verification.json`. Core tests cover strict shape/binding/Base64/expiry, default-off/no-IO behavior, durable two-stage workflow, storage failure, backend disablement, unknown replay/readback, late generation/attestation callbacks after logout, explicit rejection recovery and revocation. App-unit tests call only dormant adapters and a pure SHA-256 helper. UI tests use an in-memory store, service and literal synthetic handles; they never access Keychain or Apple DeviceCheck.

Offline source/fixture checks, pinned Tree-sitter parsing and generated-project checks are supplementary only. Swift typechecking, Apple build, App-unit, UI and physical-device execution remain NOT_RUN in this Linux worker. The sole app integrator owns compilation and execution. Merge the new localization fragment into the current catalog and regenerate the project; do not copy an isolated full project/catalog over concurrent work.
