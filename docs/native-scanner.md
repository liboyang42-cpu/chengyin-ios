# Native QR scanner component

## Scope and contract

`App/NativeQRScanner.swift` is a reusable SwiftUI sheet backed by Apple's
`VisionKit.DataScannerViewController` through `UIViewControllerRepresentable`.
It targets the provisional iOS 17 baseline and recognizes QR codes only. This
slice does not add a scan-entry route, redemption/check-in logic, network requests,
automatic URL handling, scanned-content logging, persistence, or a third-party SDK.

The `onScan: (String) -> Void` callback runs on the main actor at most once per
presentation. The scanner stops, begins dismissing, and returns the first nonempty
string payload unchanged. Leading/trailing whitespace, Unicode and URL-like text
are preserved. Nil/empty recognition results do not complete the session. The host
must validate the payload against its own verified business contract and seek any
necessary confirmation before acting. A QR string is untrusted input.

Cancel, swipe dismissal, and teardown do not call `onScan`. A new presentation gets
a fresh delivery gate. `Core/ScanPayload.swift` contains only the pure one-shot
delivery gate; it does not parse business content.

## Integration checklist

1. Add the new `App` and `Core` Swift files to the app target by running the existing
   project generator from the integration branch. The Swift package already picks
   up the new Core source and its tests by directory. This slice does not edit the
   project, navigation, catalog, build configuration or CI.
2. Add a genuine, localized `NSCameraUsageDescription` to the app's built Info.plist.
   For example: English “Use the camera to scan QR codes you choose.” / Simplified
   Chinese “使用相机扫描你选择的二维码。” Localize the system privacy text through
   the app's InfoPlist localization resources; ordinary `Localizable.xcstrings`
   entries do not by themselves localize this system prompt. Confirm the final
   wording against the actual host feature when it is integrated.
3. Add the 21 scanner key pairs below to the shared String Catalog. Existing
   `action.cancel` and `action.retry` are reused. Do not ship raw keys.
4. Present `NativeQRScanner(onScan:)` in a sheet only from an explicit user action
   in a verified host feature. It owns a `NavigationStack`, a localized title and a
   Cancel toolbar button. Present it as a modal, rather than adding another
   navigation stack around it. The callback is data acquisition, not permission
   to submit, navigate to an external address or perform a business action.
5. The callback starts dismissal but is not a dismissal-completion callback. A host
   that needs another presentation should store the validated result and use its
   sheet's `onDismiss` before presenting subsequent UI.
6. If a future feature requires scanning on older hardware, implement and test a
   separately reviewed fallback. The current fallback is a native explanatory
   state plus Cancel; it does not invent a manual-code workflow or claim that the
   business feature is complete.

## Lifecycle and failure behavior

- Support is checked before camera authorization. Simulator builds intentionally
  show the unsupported state without requesting the camera; supported hardware is
  checked using `DataScannerViewController.isSupported`.
- A missing/blank camera usage string produces a configuration state, avoiding
  AVFoundation's exception. No authorization or capture call is made in that state.
- A native explanatory screen asks the person to choose Allow Camera before
  requesting `.video` authorization. Microphone and photo-library permissions are
  not requested. In-flight permission requests are coalesced.
- Denied authorization offers the app's fixed system Settings URL after a button
  tap. Restricted authorization has a separate explanation. Returning to the app
  rechecks permission, including after changing Settings.
- UIKit starts capture only when its controller is visible and the application is
  active. It stops capture on disappearance, impending inactivity, result delivery,
  failure and dismantling. SwiftUI removes the camera view while the scene is
  inactive. Teardown clears the delegate, callbacks and notification observers.
- The controller rechecks support, usage text, authorization and availability
  immediately before starting. Both a thrown `startScanning` error and the
  `becameUnavailableWithError` delegate lead to the retry state. Retry and returning
  to the active scene re-evaluate availability and create a fresh capture attempt.
  There is no automatic retry loop.
- Delegate callbacks are coalesced before capture is stopped. A second delivery
  gate in the presentation model rejects repeated results, callbacks from a stale
  attempt, callbacks after Cancel, and results while inactive. Deferred callbacks
  recheck visibility and teardown state. An interrupted delivery can resume on
  reappearance if an interactive dismissal was canceled.
- An OS permission prompt cannot be canceled by dismissing the host. Its late
  completion can refresh only a currently visible scanner presentation; it cannot
  reopen a dismissed sheet.

## Localizable copy

| Key | English | Simplified Chinese |
|---|---|---|
| `scanner.title` | Scan QR Code | 扫描二维码 |
| `scanner.checking` | Checking camera… | 正在检查相机… |
| `scanner.requestingPermission` | Waiting for camera permission… | 正在等待相机授权… |
| `scanner.permission.title` | Allow Camera Access | 允许访问相机 |
| `scanner.permission.hint` | Use your camera to scan a QR code. You can cancel at any time. | 使用相机扫描二维码。你可以随时取消。 |
| `scanner.allowCamera` | Allow Camera | 允许使用相机 |
| `scanner.denied.title` | Camera Access Is Off | 相机访问已关闭 |
| `scanner.denied.hint` | Allow camera access for this app in Settings, then return to scan. | 请在“设置”中允许此应用访问相机，然后返回扫描。 |
| `scanner.openSettings` | Open Settings | 打开设置 |
| `scanner.restricted.title` | Camera Access Is Restricted | 相机访问受限 |
| `scanner.restricted.hint` | A device restriction prevents this app from using the camera. | 设备限制导致此应用无法使用相机。 |
| `scanner.unsupported.title` | Scanning Isn't Supported | 不支持扫描 |
| `scanner.unsupported.hint` | QR scanning requires a supported iPhone or iPad and isn't available in Simulator. | 扫描二维码需要受支持的 iPhone 或 iPad，无法在模拟器中使用。 |
| `scanner.configuration.title` | Camera Not Configured | 相机尚未配置 |
| `scanner.configuration.hint` | Camera scanning isn't configured in this build. | 此版本尚未配置相机扫描功能。 |
| `scanner.unavailable.title` | Camera Is Unavailable | 相机暂不可用 |
| `scanner.unavailable.hint` | Scanning couldn't start or was interrupted. Try again when the camera is available. | 扫描无法启动或已中断。请在相机可用时重试。 |
| `scanner.paused.title` | Scanning Paused | 扫描已暂停 |
| `scanner.paused.hint` | Return to the app to continue scanning. | 返回应用以继续扫描。 |
| `scanner.finishing` | Closing scanner… | 正在关闭扫描器… |
| `scanner.instructions` | Point the camera at a QR code. Scanning stops after one code is read. | 将相机对准二维码。读取一个二维码后，扫描会自动停止。 |

## Verification and remaining acceptance gates

Authored six pure `ScanPayloadTests`: nil/empty recognition, byte-for-byte logical
string preservation, whitespace preservation for host validation, repeated/different
late callbacks, cancellation, and independent new presentations. The gate has no
platform dependencies. These tests do not exercise VisionKit or camera lifecycle.

In this Linux worker, neither Swift nor Xcode is installed. Swift compilation,
the new unit tests, simulator UI tests, real-device camera tests, screenshots and
accessibility checks have **not run**. Static source/localization consistency and
whitespace checks can be run here. The integration owner must regenerate the
project, add copy and camera configuration, then run compilation and package tests.
Existing scaffold checking intentionally cannot pass before those integration
changes because the new source files are not yet in the checked-in project.

Required acceptance matrix on appropriate hardware:

- Supported device: initial permission explanation, grant, valid QR callback once,
  camera stop, dismissal; repeat presentation with the same and a different code
- Unsupported hardware and Simulator: explanation, no permission prompt, Cancel
- Denied/restricted permission; Settings return with permission granted and revoked
- Cancel before grant/denial completes; background while permission is pending
- Background/foreground while scanning, lock/unlock, interruption, Retry and repeated
  Retry; no stale result or active camera after dismissing
- Swipe dismissal, canceled interactive dismissal, toolbar Cancel and host removal
- Missing usage description is safe; final system prompt is localized correctly
- Nil/empty scan recognition, raw whitespace/Unicode preservation, and rapid duplicate
  add/update/tap callbacks; no external URL or backend side effects
- English/Chinese, dark mode, large Dynamic Type, landscape/iPad safe areas, VoiceOver
  focus and labels, Reduce Motion and increased contrast

## Primary references

Implementation researched against Apple documentation on 2026-10-01:

- [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller): supported/available checks, camera usage string, QR configuration and scan lifecycle
- [DataScannerViewControllerDelegate](https://developer.apple.com/documentation/visionkit/datascannerviewcontrollerdelegate): add/update/tap events and unavailability callback
- [isSupported](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller/issupported): hardware support must be checked at runtime
- [Camera authorization](https://developer.apple.com/documentation/avfoundation/avcapturedevice/authorizationstatus(for:)): grant/denial/restriction are distinct, and Settings may change authorization
- [requestAccess](https://developer.apple.com/documentation/avfoundation/avcapturedevice/requestaccess(for:completionhandler:)): usage text is required and UI updates belong on the main actor
- [Recognized barcode payload](https://developer.apple.com/documentation/visionkit/recognizeditem/barcode/payloadstringvalue): optional string data supplied by VisionKit
