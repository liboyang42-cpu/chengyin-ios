# P085 selected-customer contact

The CRM directory now offers Call and Copy beside a returned, authorized masked-contact row. Selecting a purpose opens a customer-bound sheet without a request. Review contact request uses the existing engagement proof and confirmation. Confirmation and device consumption retain their existing grants, fresh authorization, journal and single-use receipt. No number is rendered or persisted by this feature. Masked values never reach device actions.

Close, background, source snapshot replacement, account/authorization changes and permission revocation invalidate the selection. Retry requests a fresh proof; device failures require a new request rather than reuse of the old receipt. Missing production execution/device grants remain disabled. There are no new grants or backend paths.

Normal route: Account → Merchant → Business → Customers → Call/Copy → selected-customer sheet → existing review → existing gated execution → one-shot device action. Existing manually entered contact tooling is unchanged.

Only synthetic unit fixtures are authored. No production requests, actual calls or clipboard effects were executed during development. Swift compilation, Xcode builds, XCTest and real-App UI validation were not run. Python source contracts, a Mini VM oracle, and Swift syntax parsing are supplementary checks only. Existing behavior and all prior delivered feature packages remain unchanged.
