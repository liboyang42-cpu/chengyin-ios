# Conditional native WeChat payment adapter

The locally authored Objective-C bridge implements official Tencent OpenSDK 2.0.5 selectors from the pinned evidence. No vendor header or binary is distributed. The existing authorization bridge is unchanged.

## What is implemented

- Transient backend-signed APP fields are validated against separately approved AppID and merchant IDs. Timestamp must fit the actual UInt32 SDK property. PayReq maps packageValue to package; it does not invent an appId or state property.
- The provider carries a known registration ID and captured runtime context. One local attempt is pending at a time. Duplicate local callbacks, cancellation, revoked gates, session changes, launch failure and timeout all terminate without a paid verdict.
- PayResp has no OAuth state or order ID. Its error code only ends a provider wait. No response field is invented as correlation proof. A late external callback can therefore trigger a conservative readback, but cannot settle or unlock another order: the caller always queries the exact retained order and validates its topic ownership. Unknown provider outcomes retain the durable no-repeat marker.
- Exact approved callback scheme/host/path and Universal Link routes are admitted only while an order is pending. Clipboard-read permission remains independently false by default. Off-main responses and unapproved pasteboard requests fail closed.
- Normal AppSession has a concrete driver/adapter fallback, with separate optional injection for tests. Logout/login cancellation detaches the provider wait. The root URL and Universal Link handlers route payment separately from auth.

## Gates remaining external to the code

1. Apple compilation and synthetic tests on the exact final commit; linked-SDK build has not run
2. A reviewed SDK installation/linking decision and the independent `QUESTIFY_WECHAT_PAYMENT_SDK_APPROVED=1` build setting. The current repository sets neither; BUILD_WITHOUT_PAY variants cannot activate it
3. Verified AppID, merchant IDs, callback routes, Universal Link association, URL schemes and capability registration. If auth and payment are both configured, their AppID and Universal Link registration must agree
4. Current signup notice/version and legal review for the exact deployment; explicitly accepted API/runtime grants
5. Storefront and product-classification approval for external checkout. Digital-only features must continue to obey Apple payment requirements. `selfPlayExternalCheckoutApproved` and `selfPlayPayment` remain false
6. Provider merchant/backend configuration, signed production payment parameters, official callback delivery, physical-device return and authoritative settlement acceptance

No real credentials, provider calls, payment, SDK install, new legal acceptance or deployment occurred. Packet 04's conservative terminal-order rebuild gate is unchanged. Local source/scaffold/parser checks are not provider or UI acceptance.
