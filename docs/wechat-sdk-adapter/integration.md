# Dormant native WeChat OpenSDK adapter

## Result and limits

The previous unimplemented SDK seam now has a concrete native adapter, an exact-selector Objective-C bridge, SwiftUI URL/Universal Link entry hooks, and synthetic tests. The bridge compiles its no-SDK implementation by default. Every release gate is still OFF; AppID, registered Universal Link, exact callback route allowlists, HTTP exchange service and clipboard permission remain unconfigured. No provider registration, live authorization, credential/grant creation, SDK installation, binary execution or terms acceptance occurred during this work.

This is an implementation packet, not a claim of SDK-enabled compilation or successful WeChat login. Local Apple toolchain, Objective-C/Swift typechecking, XCTest execution, physical-device routing and real provider acceptance are NOT_RUN. A passed syntax parser or Python source contract is not a substitute for those checks.

## Primary source provenance

The vendor developer pages still returned `Site Unavailable` on 2026-10-02. The public CocoaPods package registry provided an independent official distribution route:

- Pinned spec: https://github.com/CocoaPods/Specs/blob/5c861788f2507084fd41f5a9a365b4b36305e7e1/Specs/9/7/f/WechatOpenSDK-XCFramework/2.0.5/WechatOpenSDK-XCFramework.podspec.json
- Vendor archive: https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK2.0.5.zip
- Download size: 4,415,542 bytes
- Locally measured SHA-256: `00e7c16d76de05cae3f96fd051b928147a17e2047169a5a6e10631a293f0dd14`

The digest identifies the inspected bytes; it is not claimed to be a separately published Tencent checksum. The archive's README identifies SDK 2.0.5; the module map identifies `WechatOpenSDK`. Framework bundle metadata uses its own 1.0/1.0.0 versions, so that metadata is not used as SDK semantic-version evidence. The archive and full vendor headers are not copied into the publication tree. `source-evidence.json` records individual inspected-file hashes.

The implementation uses these inspected declarations from `ios-arm64/WechatOpenSDK.framework/Headers/`:

- `WXApi.h`: `WXApiDelegate.onResp:` (43); clipboard authorization delegate (45–54); `registerApp:universalLink:` (83); `handleOpenURL:delegate:` (93); `handleOpenUniversalLink:delegate:` (103); installation/support checks (110, 118); `sendReq:completion:` (171)
- `WXApiObject.h`: error enum values (17–24); `SendAuthReq` scope/state and nonautomatic properties (278–298); nullable `SendAuthResp` code/state and state-whitelist warning (307–315)
- Module map: `framework module WechatOpenSDK`, with `WechatOpenSDK.h` umbrella header

The SDK changelog reports a cancel/deny state-return correction in 1.9.4. This adapter still rejects nil or mismatched response states for every outcome. It never fabricates response.state from the outgoing request.

## Architecture and boundaries

1. `WeChatSDKAuthAdapter` implements the existing `WeChatAppAuthorizing` protocol. It accepts an injected driver, configuration and live gate/context closures. It validates gates, CN login state, session epoch, storage namespace and account/busy scope before registration, sending, response delivery and callback routing. Actual code exchange and verified account/Keychain commit remain owned by the existing `WeChatAppAuthCoordinator`.
2. `QFWeChatSDKBridge.m` calls the exact Objective-C vendor selectors, avoiding assumptions about Swift importer renaming. Its vendor branch requires both `QUESTIFY_WECHAT_SDK_APPROVED == 1` and the official header to be available. Its default branch returns unavailable and performs no provider calls.
3. A request creates a fresh bridge generation. Launch-result callbacks are generation-bound. Domain response callbacks require the original attempt ID plus actual response state, including cancellation and denial. The bridge passes only copied primitives to main-thread closures. Non-auth response classes are ignored; request/share/payment callbacks are not handled.
4. Detach/cancel erases callbacks. It does not claim to dismiss WeChat. Existing coordinator timeout remains 120 seconds. Cold-start callbacks without an in-memory pending attempt are ignored; the user must initiate a fresh login.
5. URL and Universal Link handlers require an active, current attempt and exact configured host/path matches before calling the SDK. Credentials, ports, fragments, percent-encoded paths, dot segments and unexpected hosts/paths are rejected. Universal Link callback paths must also fall under the registered HTTPS base path. Opaque query parameters are left to the vendor SDK; this module does not parse a code out of a raw URL.
6. Callback routes are deployment facts missing from the available verified headers. There are no invented production defaults or broad `wx*` acceptance. Synthetic fixture routes are intentionally not Tencent shape claims. The final route allowlists require approved registration/device evidence.
7. The SDK clipboard delegate is implemented because the vendor documents that omitting it permits reads. Its independent permission defaults to false. It only completes a permission request when explicitly approved, on the main thread, for the exact routed callback URL and a pending generation. Otherwise the SDK receives no clipboard permission and the existing timeout remains authoritative. No clipboard data is read by this code.
8. `SendAuthReq.nonautomatic` is enabled in the dormant bridge so every actual future login asks for authorization. `snsapi_userinfo` is the retained scope. The no-installed-app web-auth alternative is intentionally not invoked.

## Integrate this packet safely

Use the external packet manifest and preimages. Add only its listed files; apply the four narrow modified-file patches. Do not copy the isolated tree wholesale. `AppSession.swift` and `QuestifyApp.swift` may have later unrelated integration changes.

The generator addition handles local `.m`/`.h` files, adds `.m` to Sources with per-file ARC, and sets the app target's local bridging header. Headers are references only, not source/resource build entries. No vendor framework, CocoaPods install, external dependency, URL scheme, Associated Domains entitlement, ATS change or approval flag is added. Regenerate the project after all integrated files; do not replace it from this snapshot.

The current host mounts an unavailable driver and adapter, keeps the configuration nil and all five grants false, and retains the existing nil exchange service. Add the gate closure to both coordinator and adapter together when activation is separately reviewed. Existing native deep-link handling remains after the SDK's exact routing filter.

## Proposed dependency/configuration steps: approval required, not performed

1. Confirm permission to install/link the reputable official `WechatOpenSDK-XCFramework` package exactly at `2.0.5`. The package declaration would be `pod 'WechatOpenSDK-XCFramework', '2.0.5'`; do not use a floating constraint. There is no committed Podfile or SDK binary in this packet. The registry spec names the vendor archive above, `WechatOpenSDK.xcframework`, iOS 12 minimum, Security/UIKit/CoreGraphics/WebKit frameworks and z/sqlite3.0/c++ libraries. CocoaPods is one possible approved integration route; it must not silently replace the app's generated project workflow.
2. Review Tencent licensing, provider terms and privacy behavior first. The registry license is Copyright, with `Copyright 2020 tencent.com. All rights reserved.` The inspected headers say `Copyright (c) 2012 Tencent. All rights reserved.` These are notices, not an MIT/Apache redistribution grant. No new license is assigned to the app and no agreement has been accepted. The archive includes a PrivacyInfo.xcprivacy declaration for UserDefaults reason CA92.1; verify inclusion and the final app privacy disclosure during release review.
3. On an approved Apple build environment, obtain the same official bytes or explicitly review a changed archive, then link the official module. Independently authorize any new terms or persistent provider access. The app does not need a client secret and none belongs in it.
4. Supply verified AppID/registered Universal Link and exact legacy/Universal Link callback routes. Review Bundle ID, URL registration, AASA/Associated Domains and permitted `LSApplicationQueriesSchemes` before changing them. This packet makes none of those changes. Do not copy the historical README's old ATS relaxation; it is not required or proposed here.
5. Set `QUESTIFY_WECHAT_SDK_APPROVED=1` only in the separately reviewed SDK-enabled build after installation/configuration approval. Independently enable the five existing SDK/provider/legal/Apple-alternative/live-exchange gates only with their evidence. The clipboard grant is an additional independent approval.
6. Run both default and approved SDK-enabled compilation; then approved physical-device tests covering custom URL and Universal Link return, cancel, deny, nil/wrong state, old callbacks after retry/logout/market change, duplicate returns, unavailable/unsupported WeChat, launch failure, timeout and clipboard refusal/approval. Finally validate the existing exact backend code exchange and Apple alternative. No synthetic pass establishes these external outcomes.

## Checks in this packet

- PASS: 7 new Python source/project contracts; 6 existing WeChat contracts; deterministic project/scaffold check
- PASS: pinned Tree-sitter 0.26.0 / Swift grammar 0.7.3, six changed/new Swift files, zero recovery diagnostics
- AUTHORED, NOT_RUN: 13 new core XCTest methods for configuration/routing, individual gates, unconfigured/unlinked/unavailable SDK, registration/launch failures, every error outcome, malformed code, state whitelist, cancellation/retry session/gate revocation and synthetic adapter-to-coordinator exchange/commit; one app-unit default-bridge method
- NOT_RUN locally: Objective-C compilation; Swift typechecking; XCTest runtime; default app build; SDK-enabled app build; WeChat/clipboard/device/provider/backend/legal acceptance

No catalog additions are needed: the adapter reuses the existing unavailable, launchFailed, cancelled and denied outcomes.
