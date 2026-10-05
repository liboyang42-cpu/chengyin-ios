# Withdrawal support contact binding (source parity only)

## Evidence and activation gap

The current mini source `chengyinhub-xcx/utils/withdraw-cs.js` at private commit
`4f124660` supplies the contact from a private source literal. Its flow is contact
presentation → explicit local copy → manual WeChat contact, with cancel/return.
It does not open a WeChat deep link. The private identifier is not reproduced.

`ApiConfigController.java` at that commit exposes `POST /api/config/features`,
backed by `ISysConfigService` and explicit boolean projections. It does not return
withdrawal contact information. This is an existing configuration infrastructure
that could host an independently reviewed public business-contact projection;
its present flags response is NOT a contact endpoint. No new URL, backend field,
production grant, credential, or private contact is invented here.

Activation needs the owner to identify/approve a public business contact and its
market, plus a reviewed server read contract and deployment-bound adapter. The
adapter must map only that public withdrawal-purpose projection into
`WithdrawalSupportConfiguration` (namespace, market, authoritative revision,
expiry, validated WeChat identifier). Missing/disabled/revoked records return nil;
errors must throw, never return a cached successful contact. The approval closure
must revoke its opaque review ID when approval/deployment changes. Server adapter
and actual source verification remain unimplemented, not implicitly approved by
the typed interface. Normal composition deliberately supplies no source/approval.

## Binding and behavior

SessionRootView injects the same session-bound reader for ordinary wallet support
and cooperation-finance support. Wallet balance permissions are independent:
reading a public support configuration grants no wallet read or payout command.
Opening support reads configuration; explicit copy re-reads and checks account
and epoch, deployment namespace, market, approval ID, revision, identifier and
expiry. New revision/contact requires refresh and a new explicit copy. Returning,
dismissing, backgrounding, cancellation or account changes fence delayed results.
Copy writes only the approved identifier to a local-only expiring clipboard.
There is no balance/token/account export, external app launch or payout request.
The existing unavailable explanation remains visible when configuration fails.
Synthetic identifiers are confined to tests. No demo is mounted in release.

## Verification limits

Python source/tooling checks and Swift grammar parsing are supplementary checks.
New XCTest coverage is authored for unavailable approval, revocation, expiry,
market/namespace/revision mismatch, account ABA, in-flight changes, cancellation,
and successful copy-value revalidation. Swift/Xcode compilation and XCTest/UI
runtime have not run in this Linux workspace. TC07's actual configured contact
flow remains open. Still needed: Apple build and tests, copy/cancel/reopen,
background/foreground and session-switch races, accessibility announcements,
clipboard behavior, actual server outage/revocation, and approved-contact owner
acceptance. No financial transaction has been performed.
