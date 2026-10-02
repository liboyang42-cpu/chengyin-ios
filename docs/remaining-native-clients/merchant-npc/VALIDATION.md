# Validation — 2026-10-02

- PASS: 178 static source/contract assertions against retained Flutter contracts and package files.
- PASS: Tree-sitter parse, eight Swift files, zero recovery files / diagnostics (tree-sitter 0.26.0, tree-sitter-swift 0.7.3).
- AUTHORED, NOT_RUN: 27 XCTest core tests using fake HTTP and existing MerchantOperationsFixtureReader. Cover exact merchant row JSON, no node/owner identity conversion, business 403 text, default off, same UUID retry limit/delay, late reply fencing, moderated reply audio rules, consent-first script, approved media host, voice ownership/explicit consent, order, accepted-vs-ready, unknown lock, revoke failure, avatar exact fields, unknown status and failed read preservation/signout, denied-refresh authority loss, pre-dispatch fresh access/status, durable recreation/new epoch, journal failure and namespace/account isolation, malformed chat same-ID retry and consent-change cancellation during revalidation.
- AUTHORED, NOT_RUN: 3 XCUI flow tests for synthetic text reply, disabled real recording and background clearing. Host launch route is documented; no screen capture or simulator execution claimed.
- Apple compilation/typechecking/XCTest/XCUI/VoiceOver/dynamic type/network/provider/legal review: NOT_RUN. Swift/Apple SDK unavailable in this environment. Tree-sitter is supplementary grammar validation only.
- No main app files changed, remote actions performed, real media created, upload attempted or provider invoked.

Run source assertions:
`python3 Tests/ContractChecks/check_merchant_npc.py`

Parser evidence is in parser-results.txt; source check evidence is in source-check-results.txt. Integrator must add documented files and fixture route, merge localization catalog, compile all affected targets, execute tests on Apple SDK and verify native accessibility before runtime acceptance.

Limitations deliberately retained: durable write-ahead locks are retained, with no automatic unknown-operation recovery without a source contract; no activation or legal terms inferred from fixture flags; no proof of remote deletion inferred from status; no media upload receipt invented. Default transport has no networking capability.
