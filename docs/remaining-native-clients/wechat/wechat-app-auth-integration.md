# Retained WeChat App authentication: dormant client packet

## Scope and evidence

Retained Flutter `lib/feature/auth/login_page.dart:123` calls the App auth controller; `auth_controller.dart:185–235` registers the provider, requests `snsapi_userinfo`, and receives an authorization code. `lib/data/api/auth_api.dart:23–29` sends multipart `code` to POST `/api/login/wechat/app`, returning `{code, token, data}`. Native `AuthEndpoint.wechatApp` already exists. This packet adds the missing injected client and native host entry, not a new account-creation contract. It never uses `/api/login/code`, `/api/getwxbindphone`, a WeChat client secret, or international provider contracts.

## What is implemented

- Exact multipart App code exchange via injected HTTPTransport; no default endpoint or transport, no retries, no code logging/storage
- Existing `userInfo` verification before commit; result/account identity must agree
- Fresh two-UUID state nonce per attempt. This is OAuth state, not an invented OIDC nonce parameter
- Main-actor callback coordinator with attempt ID, state, duplicate callback claim, explicit cancellation, 120-second timeout, late-callback and late-exchange rejection
- CN-only scope, session epoch/account/busy and storage namespace comparison before authorization, exchange, account validation and synchronous host commit
- Five independent OFF-by-default gates: SDK, provider, legal, Apple alternative, live exchange approval
- Existing regional Keychain/account commit path reused; no second token store
- Native bilingual accessible disabled control in the CN login form, with cancellation/error states; existing password/phone/Apple routes remain intact

## SDK adapter gap: exact checked evidence (2026-10-02 01:47–01:48 UTC)

Read-only official documentation lookup attempted:

1. https://developers.weixin.qq.com/doc/oplatform/Mobile_App/WeChat_Login/Development_Guide.html
2. https://developers.weixin.qq.com/doc/oplatform/Mobile_App/Access_Guide/iOS.html
3. https://open.weixin.qq.com/cgi-bin/showdocument?action=dir_list&t=resource/res_list&verify=1&id=open1419319164&lang=zh_CN

Web retrieval returned non-retryable errors for all three. The cloud browser independently rendered “Site Unavailable” / “Unable to access this site” on (1). Search returned third-party mirrored headers with differing sendReq signatures, which were not accepted as official API evidence. A local retained-tree check found `app-audit/ios/Podfile.lock` pins `WechatOpenSDK-XCFramework (2.0.5)` (via fluwx/pay), but no Pods/.symlinks/framework directory, WXApi header, WX object header, or module.modulemap was present in the retained iOS tree. A lockfile version alone does not establish the imported API. The current Swift import/module interface and SDK-specific methods could not be verified from an official primary source. Therefore this packet does NOT claim a concrete SDK adapter. The reviewed adapter must implement `WeChatAppAuthorizing`, pass the actual response.state (never replace it with the requested state), deliver callback on MainActor, check installation, and route only matching auth responses. Its cancel method must detach callbacks even if WeChat itself cannot be dismissed. No SDK package, binary, app ID, URL scheme, universal-link association, entitlement, app-opening code or provider activation was installed or enabled.

## Safe additive integration

Manifest: `docs/wechat-app-auth-manifest.json`. Copy only listed `add` files. Do not copy this worktree wholesale: it contains a snapshot of other in-flight integration work.

`docs/wechat-app-auth-host.patch` contains only the two host-file deltas relative to the source snapshot. Apply hunks manually if main has changed; NEVER replace AppSession.swift wholesale.

1. Add the CN-only `WeChatAppAuthSection` to LoginView, passing the existing authChannelSnapshot. Cancel on view disappearance.
2. Add `weChatContext` using existing gate epoch, account, busy, operationalMarket and storageScope.service. Host `weChatAuth` stays initialized with no adapter, no service and default false gate.
3. Extract the existing auth-channel commit closure into `commitChannelLogin` WITHOUT dropping any session synchronizers added by other integration work. Both existing authChannels and the WeChat commit closure call it. WeChat first checks its complete context; helper checks existing session snapshot and Keychain write before publishing. Preserve all pre-existing phone, Apple, password and US policy behavior.
4. Add WeChat busy guard to password login, and cancel WeChat on cancelPendingLogin/logout. Do not relax other session guards. An external session change also makes pending callbacks/commits stale even before UI cancellation.
5. Keep all five gates false and adapter/service nil. Activation needs separately reviewed official SDK integration, registered app ID/universal link, server/provider approval, CN legal evidence and a verified available Apple alternative. No claim that this code alone meets Apple review policy.
6. New standalone `Resources/WeChatAppAuth.xcstrings` avoids rewriting the shared catalog. Regenerate the project with `python tools/generate_project.py` after all batch additions. Do not import this worktree's generated project because it may omit later batch files.

## Verification and limitations

PASS: six source-only Python contract checks; zero Tree-sitter recovery diagnostics in all six authored/modified Swift files; generated local project includes source and catalog.

AUTHORED, NOT_RUN: 14 core XCTest methods using fake HTTP / SDK / suspended exchange; one bilingual repeated-entry UI method. Coverage includes multipart path/body/no auth header, userInfo raw token, malformed response, HTTP/business failures, each OFF gate, region/account/storage denial, state mismatch, duplicate callbacks, fresh nonce, timeout, cancellation, late old exchange after new attempt, scope invalidation, provider errors, account mismatch, storage failure. These are NOT runtime pass claims.

NOT_RUN: Swift typecheck, XCTest execution, Apple SDK compilation, Xcode build, simulator/device UI/a11y, concrete WeChat SDK adapter typecheck, callback/universal-link integration, provider/backend acceptance, legal acceptance, live login. `swift` is absent in this Linux environment. Tree-sitter validates parse structure only.

No network authentication, real credentials, OAuth grants, SDK install, remote writes, app launches or activation occurred. Only read-only public documentation access was attempted.
