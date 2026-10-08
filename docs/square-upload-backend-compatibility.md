# Square image-upload compatibility

This narrow change aligns `SquareWorkspaceService` with backend commit
`ce61c0bbace743ff835cb297ef41c89b52181636`. It does not enable live upload or video.

## Request boundary

- One image file part may contain **10,485,760 bytes (10 MiB), inclusive**.
  An empty part or one additional byte is rejected before transport.
- The repository's complete multipart request limit is **20,971,520 bytes
  (20 MiB)**. The present single-file request, fixed filename and optional
  `COMMUNITY_POST` field have ample overhead allowance. Do not subtract that
  overhead from the separate 10 MiB file limit.
- Upload accepts exactly `image/jpeg` and `image/png`, using `.jpg` and `.png`
  filenames. WebP, video, audio, GIF and MIME strings with parameters are rejected.
  This intentionally does not add formats merely because another backend path
  recognizes them.
- `SquareWorkspaceView` passes the same service constant to its bounded local
  image read. The local inspector accepts only JPEG/PNG representations. A
  WebP-only selection is rejected before reading bytes and remains a failed,
  removable selection that blocks server save/publish. A provider offering a
  genuine JPEG/PNG representation may use it, subject to the existing actual
  content-type and decode checks. No client transcoding is added. Movie providers
  still take priority over any JPEG poster and remain unavailable.

## Preserved behavior and limits of this evidence

The endpoint remains `POST /api/common/uploadOSS`, with one `file` part and
`bizType=COMMUNITY_POST` only for the community receipt lane. Existing session
authorization, feature grants, receipt handling and mutation-result-unknown
semantics are unchanged. A disconnection, non-JSON response or cancellation
after dispatch is not evidence that a remote object was rolled back.

The backend checks image content separately, including dimensions, signatures
and applicable business policy. Client byte/MIME checks do not prove content
validity, successful server decoding, sanitization, storage or publication.
The authored Core tests use synthetic bytes only for request construction and
pre-transport guards. Python checks inspect source text; they do not compile or
execute Swift, Apple image APIs or backend code.

These are repository defaults, **not a verified deployment guarantee**.
Deployment settings can be stricter; the backend's configured-limit test uses
7 MiB per file and 13 MiB per request. Rejection may disconnect without a JSON
business error, so network/unknown handling must remain intact.

## Pinned backend evidence

- [application.yml, multipart defaults](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/resources/application.yml#L70-L74)
- [AppUploadService, extension allowlist and validation](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/AppUploadService.java#L41-L45)
- [FileUploadUtils, strict content/size checks](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-common/src/main/java/com/chengyinhub/common/utils/file/FileUploadUtils.java#L345-L367)
- [ApiCommonController, community receipt](https://github.com/liboyang42-cpu/chengyin/blob/ce61c0bbace743ff835cb297ef41c89b52181636/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiCommonController.java#L101-L149)

The accompanying backend evidence report identifies
`AudioUploadBoundaryContractTest.java` (10 MiB inclusive, +1 rejected, multipart
over 20 MiB rejected) and `AudioUploadConfiguredLimitContractTest.java` (runtime
overrides; blob `558e9da423da4b4941f78577556799cc2599ab3b`). Its SHA-256 is
`97114a199547e184d32b5fd140347193c9db51a8aea114a729c039b1199d8b4f`.
Those backend tests were inspected, not executed for this change.
