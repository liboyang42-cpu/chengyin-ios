# Merchant customer note drafts (P087)

Normal entry: Merchant → Business → Customers → selected customer → Add note or Correct note. Closing the local editor retains exact text and correction-cancel state on this page. The same entry changes to Continue draft. Each correction target and the new-note draft are separate; switching target never overwrites another draft.

Clear text requires confirmation and does not cancel a correction. Discard local note drafts requires confirmation and clears all current-customer drafts. Cancel correction remains the existing explicit action; its blank text/new-note mode is retained if the local editor closes.

Scope: current model identity, account/epoch/realm, authorization generation, complete customer snapshot and permission bytes. A stale editor cannot write, close, or retire a newer lease. Identity/authorization/source changes, backgrounding, page exit and confirmation handoff revoke the local workspace. No persistence, request ID, network, intent reservation, grant or automatic retry is added. Existing confirmation/approval/dispatch gates remain authoritative; no return from a dispatched or uncertain request. Entering existing review retires all drafts, including canceling review afterward.

Source: unique master P087; verified Mini customer/detail/index.js blob ba72ce2e8a1617803fa9ebfb31b7782a000d9e7e. Private source evidence remains outside this product patch. This does not restore the canceled club customer-note editor.

Native AppUnit fake-reader tests are authored but NOT_RUN: no Swift/Xcode toolchain in this environment. Targeted structural contracts and Swift syntax parsing are separate evidence, not native execution.
