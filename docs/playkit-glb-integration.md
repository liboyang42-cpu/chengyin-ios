# Native GLB adapter: pinned source-only GLTFKit2

## Scope and runtime gates

The app imports and links the actual GLTFKit2 framework unconditionally. The framework is compiled from 32 vendored upstream files at version **0.5.15**, immutable commit **e69e354c4f31ea07b7816b8cbe2ddb28e897d073**. `Vendor/GLTFKit2/PROVENANCE.json` records every original Git blob SHA-1 and SHA-256; `python3 tools/check_gltf_source.py` verifies all files offline. No dependency installer, remote build script, floating branch, binary package, KTX/BasisU/Zstandard, or Draco plugin is incorporated.

AR modes, image origins, and model origins remain empty by default. The backend's existing `modelUrl` is consumed without new fields or backend changes. A completed server QR validation and operator-approved AR mode are still required. A marker additionally needs accepted physical width for its exact reference-image URL. Neither rendering nor tracking submits arrival, task completion, reward, or other evidence.

## Why source-only

The official release asset was verified independently against the immutable upstream Package.swift and GitHub release digest:

- Official artifact: https://github.com/warrenm/GLTFKit2/releases/download/0.5.15/GLTFKit2.xcframework.zip
- SHA-256: `9d0c338282acce4986494aa02a5f1495278f56c60d43f31453fefea6875b4928`
- Size: 36,733,405 bytes
- Tag object: `e8969ac969c6024323314968dbb4f517c57e3ac8` (unsigned), pointing at the pinned commit above

That artifact is **not shipped or linked**. It contains KTX/BasisU/Zstd symbols and a KTX `v4.3.0-beta1~25-dirty` version string while the source repository's libktx/VERSION says v4.2.1. It contains no complete third-party notice inventory. The KTX license overview references a separately restricted Ericsson `etcdec.cxx` file; absence of its symbols cannot prove absence from the binary. The source-only route avoids making unsupported composition/license claims.

Upstream explicitly makes KTX optional. The checked-in framework target has an empty Frameworks link phase, no package references, no shell-script build phases and no optional-codec binaries. `App/PlayKitGLBSourceGuard.m` makes accidentally visible KTX headers a build error. The bundled `GLTFKTX2Support.m` is upstream MIT adapter code: its codec implementation is behind `GLTF_BUILD_WITH_KTX2`, which is not enabled. No source file was patched from upstream.

## Notices included in application resources

`Resources/GLTFKit2Notices.txt` includes the exact MIT copyright/license texts for:

1. GLTFKit2: Warren Moore, upstream LICENSE plus umbrella-header copyright
2. cgltf: Johannes Kuhlmann, bundled deps/cgltf/LICENSE
3. JSMN: Serge A. Zaitsev, complete embedded notice in bundled cgltf.h

Apple system frameworks are SDK dependencies, not vendored components. Optional codec notices do not imply they are included: libktx, Basis Universal, Zstandard and Draco are excluded entirely. The Xcode app Resources phase copies the notice file.

## Accepted GLB profile and security

- glTF 2.0 binary, exactly JSON + BIN chunks, exact header/file/chunk lengths, <=20 MiB overall, <=1 MiB JSON
- Static triangle meshes only, <=512 nodes, <=128 meshes, <=512 primitives, <=1024 buffer views/accessors, <=250,000 values per accessor / 1,000,000 aggregate elements
- Bounds-checked buffers/accessors and vertex indices; finite bounded geometry/transforms; acyclic, single-parent node trees with depth <=32
- Embedded PNG/JPEG only, <=16 images, <=4096 pixels on each axis and <=16,777,216 aggregate decoded pixels; ImageIO metadata inspected before native loading
- Any `uri` anywhere is rejected, including file, relative, remote and data URIs. All extensions, including optional ones, are rejected. Draco, KTX2/BasisU, meshopt compression, animation, skins, morph targets, sparse accessors and cameras use the existing image fallback
- Canonical re-encoding removes duplicate-key/parser-differential ambiguity before GLTFKit2 sees bytes
- Exact HTTPS host allowlist and `.glb` path; no URL credentials or fragments. Separate ephemeral streaming download, no account headers/cookies/credential store/persistent cache, no redirects, 20-second request/resource limit, byte/deadline checks and cancellation
- Validated local bytes use the framework's NSData loader, then `GLTFSCNSceneSource` to SCNScene. No temporary files, directory access grant, external resource URL or decoder network access exists
- Native decode timeout/cancellation resolves once; late callbacks are ignored and ask the SDK to stop at its next callback. In-process native work is cooperatively stoppable, not force-killed

This deliberately limited profile does not claim full glTF conformance. Existing unsupported assets need a separate compatibility review or conversion; the regular returned-image/camera path remains available and the UI says the model is outside the approved profile.

## Source-compatible presentation

The recovered source `pages/play/components/playkit-scan/ar/index.js` defines `MODEL_SIZE={PLANE:0.4,MARKER:0.8}` separately from image-card dimensions. Native code fits the model's longest bounding-box side to 0.4 metres on planes, or 0.8 times the accepted physical marker width. It horizontally centers the model, rests its lower Y bound on the surface, remains world-upright, and faces the camera once on placement. There is no continuous model billboard. Plane raycast and one-time marker world lock remain required. Existing drop/grow presentation and Reduce Motion behavior apply to the fitted model's separate wrapper.

## Verification and limits

Run `python3 tools/check_gltf_source.py`, source contract tests, and the pure Core suite. The dedicated app-hosted `PlayKitGLBDecoderTests` includes a mandatory real-framework decode of a synthetic embedded triangle, checks SceneKit vertex/primitive counts, and separately covers provider gating, invalid data and cancellation with injected fakes. It is not a `canImport` or skipped stub test. No test opens camera, starts AR, enables a live provider, or downloads a model.

Linux authoring checks do not prove Apple compilation or linking. CI must run `python3 tools/check_gltf_linked.py --app <built Questify.app>` to inspect the real load command, decoder symbols, no optional-codec symbols, notices and privacy manifest; build the nested framework dependency, embed `GLTFKit2.framework` in Questify.app/Frameworks, retain it in Build/Products transfer, and run the app-hosted decode test on the simulator via test-without-building. Actual device camera, AR tracking, private asset, backend and visual acceptance remain OFF/NOT_RUN.

## Official source references

- https://github.com/warrenm/GLTFKit2/tree/e69e354c4f31ea07b7816b8cbe2ddb28e897d073
- https://github.com/warrenm/GLTFKit2/blob/e69e354c4f31ea07b7816b8cbe2ddb28e897d073/README.md
- https://github.com/warrenm/GLTFKit2/blob/e69e354c4f31ea07b7816b8cbe2ddb28e897d073/LICENSE
- https://github.com/warrenm/GLTFKit2/blob/e69e354c4f31ea07b7816b8cbe2ddb28e897d073/GLTFKit2/deps/cgltf/LICENSE
- https://github.com/warrenm/GLTFKit2/blob/e69e354c4f31ea07b7816b8cbe2ddb28e897d073/GLTFKit2/deps/cgltf/cgltf.h
