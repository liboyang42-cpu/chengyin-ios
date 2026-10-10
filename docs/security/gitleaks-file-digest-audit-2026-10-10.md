# Exact file-digest findings in native commit 65023b8

Gitleaks 8.24.3 reported three `generic-api-key` findings in
`tools/run138_editor_readiness_contract.json` at lines 174, 243 and 4028 of
commit `65023b84211895bf6c3f6d8ec64804edbfc45e4d`.
The findings were read from [the original secrets job](https://github.com/liboyang42-cpu/chengyin-ios/actions/runs/38048297360/job/114202160290)
and checked against the exact published source tree.

- Lines 174 and 243 are the `WeChatAppAuthFlowTests.swift` entries in
  `current_ui_sources` and `previous_ui_sources`. Both values exactly equal the
  SHA-256 recomputed from `Tests/AppUITests/WeChatAppAuthFlowTests.swift`.
- Line 4028 is the `Tests/ContractChecks/test_merchant_business_access_lifetime.py`
  entry in `feature_batch_support_sha256`. Its value exactly equals the SHA-256
  recomputed from that file's raw bytes.

The complete matched values are file-integrity digests, not credentials. This
classification is based on byte-for-byte recomputation, not on their appearance
or filenames. The configuration tests bind each original finding line's SHA-256,
its JSON section and key, and the exact source file whose digest it records.

Only these three exact commit/path/rule/line fingerprints are added to
`.gitleaksignore`. The 89 earlier reviewed fingerprints remain unchanged. No
contract bytes, hash pins, source transformations, default scanner rules, entropy
thresholds, workflow commands or history are changed. New commits, other paths,
other rules and neighboring lines remain scanned. The pinned action and mandatory
full-history scan remain fail-closed.

Local validation must separately report the original commit's three findings,
their removal by only these exact fingerprints, and detection controls for new
history and synthetic credential-shaped data. A local focused scan is not a
claim that the complete hosted branch history or Apple CI passed; those results
still require the next exact-SHA hosted run.
