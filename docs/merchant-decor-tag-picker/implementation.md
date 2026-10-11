# Store decoration tag picker

## Behavior and scope

The decoration tag section displays every current tag literally in its original order, with position-based identity. Unknown, duplicate, long and over-limit historical tags remain visible. Rendering does not trim, sort, deduplicate, split, truncate or localize saved tag data. The previous semicolon-delimited text editor and its hint are removed; a semicolon inside a tag remains part of that one label.

The existing grouped picker is the sole tag mutation entry in this section. It offers three groups with eighteen preset values, explicit removal, custom labels, Cancel and Apply. Preset labels are localized for display while saved values retain their original strings. Opening preserves the original tag array. More than twelve historical tags remain visible but require explicit removal before Apply is available. New custom labels use a sixteen UTF-16-unit bound, ECMAScript-compatible trimming and literal code-unit equality. Adding an existing label does not append or reorder it.

Apply changes only `MerchantStoreDecor.tags` on a copy of the captured decoration draft. It verifies the current session scope, draft identity, editable state, original whole draft and exact original tags. Unchanged Apply closes without editing. A consumed or cancelled picker cannot write again. Reload, discard, scope changes, backgrounding or departure close the picker. Existing image flows, other decoration fields, review/save behavior and unknown-write locks stay with the coordinator. A failed existing save leaves applied tags available for reopening. This change adds no network read, save endpoint, entitlement or production grant. It does not establish complete decoration-page parity or authorize a production save.

## Integration

This follow-on changes only the tag section in `App/MerchantOperationsEditor.swift`; every other editor byte remains unchanged from the remote baseline. Picker and Core dependencies, the thirty-three bilingual localization entries and existing project registrations are already present and remain unchanged. No UI test method, timing budget or CI timeout is added or renamed. There is no decoding, service, coordinator or global historical-data normalization change.

The original legacy-editor source expectation is intentionally replaced by a literal read-only entry contract. Four other existing check methods and all original Swift test bytes are retained. Four authored Swift cases add coverage for semicolon labels, exact historical data, cancel, apply, reopen and invalid owners. Central registration updates bind the exact current files while preserving the original historical inverse and assertions.

## Verification and limitations

Seven focused Python tag contracts pass, including ten negative controls for a reintroduced raw setter, missing picker and lossy display. The original baseline passes its five checks; replacing only the UI makes the old legacy-editor expectation fail, and restoring the actual raw editor makes the new entry contract fail. Three changed Swift files parse without syntax errors.

Current source admission is checked on both the remote baseline and the candidate. The original historical editor bytes are reconstructed exactly and replayed forward; altered line endings, same-length edits and stale source bytes are rejected. Patch replay is verified in both directions. These source checks and syntax parses do not prove native rendering or runtime behavior. Swift compilation, XCTest execution, native UI/accessibility, full static checks and remote CI remain unrun for this local candidate.
