# Native media destinations and balance help

## Implemented, with production grants closed

- POI merchant gallery reads the source gallery array or JSON string and opens an immutable, indexed full-screen gallery. Square feed, post details and comment images use the same viewer. Feed/profile gallery actions sit outside their post navigation links. The viewer has paging, explicit previous/next controls, bounded pinch/pan and double-tap zoom, cancellation and retry states.
- Media bytes use the existing anonymous, no-cookie, no-credential, no-redirect, bounded reader and native decode/redraw sanitizer. All origins and default network grants remain empty. Invalid object keys never acquire an invented host.
- Stamp camera is reachable from the normal Roam collection hub, album and POI. The screen uses an actual camera-only native picker behind an off-by-default camera gate, explicit purpose consent, permission/availability checks and stale-callback fencing. Its actual pixels are normalized, center-cropped to 4:5, resized to at most 1600×2000 and redrawn as JPEG before upload. Capture preview is separate from upload and server-confirmed creation.
- Stamp upload reuses the retained-image proof and durable metadata journal. Its exact multipart contract adds `bizType=stamp` to the existing `file` request. Before create, the exact uploaded URL and idempotency key are verified in account/deployment-scoped device-only secure storage. This small recovery record is separate from the metadata-only upload journal and contains no credentials, raw photo bytes or location. Unknown create outcomes can only be retried explicitly with the same URL/key. A new capture is blocked until resolved. A positive server ID is required for creation success, which does not imply moderation success.
- POI poster scan has source offline/completed/method/canInteract/redemption gates. Native QR capture is a full-screen subflow of a pushed preparation/review screen. The coordinator requires purpose consent, a fresh accurate GCJ02 device fix, a current node read before preparation and submission, scoped mutation approval and write-ahead metadata. No manual location or WGS84 relabeling is permitted. Unknown writes retain the lock; a fresh scan cannot bypass it. `needRedeem` is never displayed as completed.
- Balance help uses `/api/user/info` and the separate `/api/wallet/stages` read, renders loading/failure separately from known zero, retains withdrawal history, and presents only a deployment-reviewed support contact. No private source contact is embedded or automatically messaged. The user's separate App bank-withdrawal requirement will extend this landing; current mini-app retirement does not decide the App product scope.

## Source evidence

The source review used Flutter baseline `a63e9e9` and current mini/backend baseline `fad4d6`. Private implementations were reviewed for contracts, not copied into this repository.

- Mini `subpackageMember/components/cy/scene-roam-poi-detail/index.js:175–204`: gallery parsing and indexed image preview; `:310–432`: canInteract/method/status gates, camera-only QR, foreground GCJ02 location and completion fields
- Mini `subpackageP3/pages/stamp-camera/index/index.js:137–258`: camera, orientation-aware crop and redraw/compression; `:270–413`: account-scoped pending creation, idempotency, upload business type and create recovery
- Mini `utils/transport/upload-client.js:29–144`: uploadOSS multipart file, bizType and top-level URL
- Backend `ApiRoamStampController.java:100–143`: create fields, account-owned idempotency and positive ID receipt
- Backend `ApiCityNodeController.java:219–224`: needRedeem and alreadyClaimed remain distinct from completion
- Mini `pages/square/detail/index.js:928–934`, `pages/square/list/index.js:629–633`: current/list/index image preview
- Mini `subpackageMember/tixian/tixian.js:82–121`: current balance read and failed-read vs nullable-success semantics; `utils/withdraw-cs.js`: support-only mini landing
- Flutter `lib/feature/roam/roam_poi_detail_page.dart:329,942–979,1155–1210`, `lib/feature/roam/stamp_camera_page.dart`, `lib/feature/square/square_image_viewer.dart`, `lib/feature/withdrawal/withdrawal_page.dart:361–443`: presentation comparison and stages

## Apple UX decisions and remaining acceptance

Preparation and review are pushed destinations; only the image viewer and actual camera/QR capture are full-screen. Support contact uses a dismissible system sheet. Native 4:5 center-crop review is explicit; it does not claim exact visual parity with the mini-app's pre-capture custom framing. The existing caption-only stamp draft is preserved as a separate local-only view, not counted as capture coverage.

Linux structural checks and supplementary Tree-sitter parsing are available. Fifteen core tests and two app-hosted pixel tests are authored. Swift typechecking, Apple builds, XCTest, simulator interaction, VoiceOver, Dynamic Type, image-zoom gestures, permissions, physical camera, EXIF negative controls on real camera files, GCJ02 provider validation and full visual acceptance are **NOT_RUN locally**. No live service/provider/financial action is performed, and no visual pass is claimed.
