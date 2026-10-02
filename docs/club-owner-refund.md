# Club owner refund review and reconciliation

This is a continuation of the club enrollment packet. It adds locally implementable review and readback behavior; it does not activate financial writes.

## Implemented boundary

- The normal club checkin detail mounts a bottom owner-refund panel. The roster still has no inline refund control.
- Preparing a review re-reads the existing club-scoped checkin endpoint, requires matching club/registration identity, explicit `canRefund`, an eligible source status, and fresh owner permission.
- The review shows the player, topic, ticket, order/registration identity and the source's paid-amount text. It does not quote a refund amount. It warns that a cancellation can affect linked tickets in the same order and can require manual review.
- Confirmation re-reads and compares the exact review evidence, namespace, account epoch and freshness. Cancel, sheet dismissal, back navigation, changed identity, expired review or changed facts prevent dispatch before a request starts.
- An exclusive metadata-only file lock is acquired before any offline dispatch. The existing registration lock keeps account, environment/service, club and registration scope. A second lock hashes the exact nonblank server parent-order number with account and environment/service scope; epoch is intentionally excluded. Both keys are checked and exclusively acquired before dispatch. Unknown and acknowledged attempts remain locked across relogin, screen recreation and process relaunch, including attempts through sibling registrations of the same parent order. No dispatched HTTP/business response releases either lock. Partial acquisition and corrupt/partial existing lock files remain locked; raw parent-order text is never persisted.
- HTTP 408/499, business 408, authentication replies, other non-success replies and malformed feedback are unconfirmed after dispatch. Bounded server messages are shown as messages, explicitly not proof of an unexecuted request. There is no blanket 4xx rejection/unlock rule.
- Structured outcomes separate cancellation, cash payout and points return. Manual review, pending dispatch, channel processing, partial points return and unconfirmed results are not mislabeled as completed refunds.
- Reconciliation only re-reads existing `api/club/crm/checkin/detail`. A `REFUNDED` record is shown as a recorded status, with cash/points evidence still separate. It never unlocks an uncertain attempt, calls an invented receipt endpoint, or automatically resubmits.

## Exact dormant request contract

The bounded adapter constructs POST `api/registration/cancel-by-owner`, with one form field `id` containing the registration ID. It uses the existing native multipart-form builder, matching the backend's form-parameter binding and supplied Flutter adapter. It adds no amount, currency, recipient, arbitrary path or fabricated idempotency field.

Shipping composition is `ClubOwnerRefundReadOnlyAccess`. That class has no token or transport and its `send` always throws disabled. The default `ClubOwnerRefundService` constructor has no transport; cancellation fails before request construction. Only the separate constructor accepting `ClubOwnerRefundOfflineTransport` can execute, and the supplied conformer returns canned data without a network implementation. A configured backend URL or an authenticated account does not enable sending.

## Source proof

Read-only inspection of separately supplied sources on 2026-10-02. No private implementation, secrets or backend data are copied into this packet.

- Mini `pages/club/enroll/index.wxml:73–80`: refund placement is checkin detail, never a roster-row action
- Mini `pages/club/checkin-detail/index.js:111–147`: server canRefund, confirmation, identity comparison, form `id`, rejection versus ambiguous response
- Mini `pages/club/checkin-detail/index.js:80–91,162–172`: existing checkin readback, unknown result lock, no resubmission until evidence is available
- Mini `pages/club/checkin-detail/index.wxml:77–90`: bottom action and frozen-purchase-policy disclosure
- Mini `utils/cancellation-feedback.js:3–9`: generic acknowledgment alone does not prove cash or points payout
- Backend `ApiRegistrationController.java:371–392`: form-bound owner cancellation; manual-review versus normal feedback
- Backend `ApiRegistrationController.java:835–847`: manual-review fields and read-only feedback service
- Backend `ClubCrmAppServiceImpl.java:305–368`: club/registration scoped record, owner-only canRefund, eligible statuses and separate fulfillment rail; `:362–364` specifically requires PENDING/CONTACTED plus current club owner
- Backend `ClubCrmMapper.xml:323–329`: checkin orderNo is exactly `r.parent_order_no`, establishing parent-order lock identity
- Backend `TeamGroupServiceImpl.java:210–266,1065–1071`: owner cancellation delegates to `refundResolvingOrder`; only a nonempty parent chooses the shared-order branch, otherwise exactly one registration is refunded
- Backend `StringUtils.java:111–124`: the nonempty predicate uses Java String.trim, not the broader Swift Unicode whitespace set
- Native `Core/ClubGovernanceContracts.swift:80–87`: OWNER requires active, matching club and explicit CLUB_OWNER role; delegated event permissions cannot satisfy OWNER
- Backend `RegistrationCancellationReadService.java:45–55,87–110,113–143`: unconfirmed fallback, parent-order scope, separate cancellation/cash/points statuses and supported cash outcomes
- Flutter `lib/data/api/club_api.dart:299–310`: existing multipart FormData adapter confirms backend-compatible encoding; it does not override current mini interaction placement

## Remaining activation and acceptance gaps

The review, exact offline contract, registration-plus-parent-order no-replay boundary, status presentation and readback behavior are implemented locally. Backend TeamGroupServiceImpl.refundResolvingOrder explicitly selects the single-registration refund path when parent_order_no is null or Java-trim-empty; it does not resolve an omitted parent through another ID. The checkin mapper projects this exact field. Accordingly, missing/empty values and strings containing only UTF-16 units U+0000 through U+0020 use the registration lock alone. Java StringUtils.trim semantics are matched exactly: other Unicode whitespace remains a real parent identity and is hashed without normalization. A regression covers non-breaking/em-space parents and control-only absent values. No parent grouping is guessed. Nonempty orderNo bytes are not normalized before hashing. Missing later evidence cannot erase a parent binding already established in the current session; a changed binding cannot replace an already locked parent. Financial transmission remains intentionally absent from shipping composition. Activation requires a separately authorized/audited production executor, deployment/auth verification, provider and frozen-policy acceptance, and end-to-end financial reconciliation acceptance. This packet does not imply those prerequisites exist or that enabling a URL/token is sufficient.

Swift/Xcode compilation, simulator/physical-device flows, VoiceOver/Dynamic Type inspection and live account/backend acceptance remain NOT_RUN in this environment. Python structural checks are not runtime proof. No backend requests, credentials, provider calls, financial changes or publication were performed.

## Integration

Apply this packet after the enrollment packet. Exact preimages are the frozen `club-work` state, not the original native base. Merge only new keys from `ClubOwnerRefundLocalizations.fragment.json`, then regenerate the project after all concurrent packets. Apply the recorded AppSession/ClubDetail/Governance view/context hunks precisely instead of replacing those shared files wholesale. The prior enrollment test assertion is updated to verify the new read-only refund composition.
