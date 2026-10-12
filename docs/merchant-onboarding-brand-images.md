# P065 onboarding brand images

Normal entry: Account → Merchant application → step 3 → Add brand image → system selected-item picker → local preview → explicit upload confirmation → returned image preview/remove → step 4 preview → the existing frozen registration confirmation.

Up to six images retain their order and duplicates. Native uses one selected image per add, repeated up to six, rather than introducing a second multi-upload queue. Local image data passes through the existing metadata-stripping adapter and never serializes. Upload reuses the existing coordinator's shared uploadOSS transport/identity/status gate; it does not assign the license or introduce a new service. The legacy multipart filename remains unchanged. No upload starts from selection alone; no automatic retry occurs after ambiguous upload failure.

The source field is derivatives, a comma-separated string. Untouched new drafts continue omitting this optional field, preserving existing payload defaults. A valid rejected-application image list is restored. Removing the last image explicitly sends an empty string. Unknown or oversized historical image lists cannot be edited here and remain omitted rather than silently cleared; unrelated old backfill behavior is unchanged.

Snapshot, account, generation and opaque photo-selection identity fence late loaders and upload callbacks. Pending selected photos block next/review until uploaded or discarded. Old removal callbacks cannot remove a newer list. Reset/reapply/submission retire local selections; parent lifecycle recognizes the new picker and upload confirmation.

No actual upload, production request, photo-library permission or device access was executed during development. Swift compilation, Xcode, XCTest and real-App photo/dialog regression were NOT RUN. Fake XCTest cases are authored; Python contracts, real-Mini record-only VM cases and Swift syntax parsing are supplementary checks only.
