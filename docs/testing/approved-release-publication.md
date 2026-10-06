# Captured manifest confirmation and exact-request recovery

This increment consumes the separately captured approved-snapshot preparation. The author reviews that captured summary, including its audit version, full manifest hash and release-head revision. Confirm synchronously persists the complete request identity and summary before scheduling any HTTP work. Cancel and sheet disappearance capture the original confirmation; a delayed old action cannot claim or dismiss a newer review. Closing after the claim but before the queued task starts sends nothing and retains the unresolved intent.

The new `expectedManifestHash` field is mandatory on both `/publish` and `/status`. The server checks it before allocating a release and when returning an existing idempotent receipt. A saved request has one UUID and its original audit/task/head/hash values. Status and explicit exact retry use that record, never a fresh preparation or a newly generated UUID. Unknown results and local write/readback failures retain the original record. A known immutable-release receipt does not establish public listing, player eligibility or successful play.

Local records use the existing secure-storage interface, compare expected stored bytes, validate before write, and verify exact readback. Unresolved records cannot be removed or replaced. A later explicit publication can append after a resolved receipt only with a changed server review and advanced captured head; historical records remain present. The local envelope is bounded to 32 records and the same bounded JSON parser. Capacity or persistence failures stop dispatch and require a recoverable storage path; there is no deletion or retention promise.

## Normal composition and lifecycle

The ordinary editor's release preparation, publication and status permissions are three distinct, default-empty feature routes. The outer composition transport independently admits only their exact method, URL and JSON shapes under the corresponding current feature. Transport clones preserve the selector. Other creator and player paths are not opened by this change. Existing grants are re-read for revocation, and the normal factories capture the existing monotonic viewer revision so role A→B→A cannot revive an old client. The endpoint wrappers additionally check credentials before and after transport.

The presentation-scoped flow owns its actual read/write task. Duplicate taps do not replace that task. Original-record status/retry callbacks reject newer local entries. A current account change, role change, cancellation, old dismissal or stale receipt cannot mutate a replacement presentation or another owner's record. Same-owner reauthentication can read the retained record with fresh authority.

## Verification and limits

The isolated Java kernel/preparation/HTTP suite currently reports 126 actual successes, including real prepare→publish→status→exact retry, manifest mismatch zero-allocation and status mismatch rejection. This is real Spring/MyBatis/H2/MockMvc execution on JDK 21 with source/target 8; it is not production MySQL, a full Boot deployment or live publication.

Authored Swift coverage adds 11 journal methods, 14 actual-client/flow methods, six shared View-model lifecycle methods, five normal AppSession/outer-transport methods and two real-button UI methods. The UI uses DEBUG synthetic server state through the real clients. Swift typechecking and Apple execution remain pending. Complete new-method estimates are unmeasured: 900 seconds for the confirmation class and 1,200 seconds for the separate recovery class; the unchanged 300-second reserve fits each below 1,800. Existing UI methods and observations are retained separately.

## Activation blockers

The server's first source adapter is still held for the platform input/principal combination and the full source-rights closure. `cms_topic.member_id` establishes the publisher, not the canonical content owner; the exact `product_role` active CONTENT slot must be captured in the reviewed snapshot and rechecked with its immutable row identity. That source extension is not represented as implemented by these native controls. Owned cover/version/byte-digest/security evidence is also a separate unfinished adapter. Existing cover requirements remain intact. These routes must not be enabled by treating a URL hash, a submission receipt, an old `published=true` flag, or a local record as approval.
