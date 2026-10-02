# Approved-read binding and identity-state repair

## Before → after

- Before: approved-read wrappers authorize the latest account but forward a request containing a previously captured token. After: publishing passes its captured PublishingCredentials directly; WalletCommerceReader binds an immutable service copy to the captured WalletCommerceScope. Each approved wrapper compares exact account/epoch/namespace plus token to current credentials and checks the Authorization header on MainActor immediately before dispatch, then checks cancellation and identity again after completion. Unbound URLRequest entry points fail closed. Tokens are neither logged nor persisted.
- Before: unavailable/error/malformed identity-status reads become false and the UI claims “not registered.” After: identityRegistered is throwing and only returns a successfully decoded Boolean. UI renders distinct unconfigured, loading, failed, registered and authoritative not-registered states. Existing localized strings are reused. Identity submission/consent/legal gates are unchanged.
- Default grants remain nil; read-path whitelists, mutation permissions and dormant adapters are unchanged.

## Integration

Apply `approved-read-repair.patch` to current integration, reconciling only its hunks. Do not replace the full AppSession file: other workers may have added factories since this baseline. Exact baseline/result hashes are in patch-manifest.json. Nine changed files: three Core, two App, two XCTest and two source-contract suites. Shared main was not edited by this worker.

## Verification

- PASS: 19 source-contract tests, executed against an overlay resolving patched files before the main tree
- PASS: strict supplementary Tree-sitter parse, seven changed Swift files, zero recovery diagnostics
- NOT_RUN: Swift typecheck, XCTest execution, Apple SDK compilation and SwiftUI runtime; Swift is not installed in this executor
- Authored XCTest coverage: stale account/epoch/namespace/token, forged Authorization header, unbound dispatch, valid bound-reader dispatch, stale completion, unsupported identity region, transport/server/missing/malformed identity response, authoritative true and false
- No real HTTP traffic was dispatched

Two compatibility changes are intentional: approved-wrapper initializers now take credential-bearing closures, and identityRegistered is async throws. All current call sites in these integrations/tests are updated. Fake HTTPTransport services used independently retain their existing request behavior.
