# Ordinary Square post: recovered local media model and App image host

## Subsequent integration note

The recovery-stage evidence below describes snapshot `c6a70943`, not every later change. The subsequent six-domain increment narrows the image upload/preview contract to JPEG/PNG and 10 MiB, adds two image-representation AppUnit cases (36 total authored Square AppUnit cases), and separately integrates the Topic image host with its default-disabled capability. See `PROGRESS.md`, `square-upload-backend-compatibility.md` and `project-topic-media-app.md` for that scope. No video/runtime acceptance is implied.

## Current integration and provenance

The recovered integration is based on published commit `6eb3af76d977537a455cc203197125db78b8c7e0` / tree `59352a513ea27343436711124664ba63cfb6c4b3`. It applies the original Square media App R2 cumulative patch from its preserved `a33987cb43d5a30391abd7fbddac0db35f9616e3` archive and the separate six-file ProjectTopicMedia Core patch. The resulting code snapshot is `c6a709432f82f89b6265501f73ec056551ddf1f6`. This document-only revision changes none of that code.

The earlier Core-only packet depended on `498fa452ced91f23465cb9b6c4803b61ecccabcf` and corrected the copied-stream-prefix issue in its separately retained `a701d4d13e0476e78dd14fe5542df9ed15e1935f` predecessor. Statements that the App picker and project registration were absent described that historical packet; they do not describe the current recovered integration.

## What exists now

Square has an App image path in `SquarePostLocalMediaPicker`, `SquarePostLocalMediaInspector`, `SquarePostLocalMediaPresentation` and `SquareWorkspaceView`. The selected-item provider read is consumed inside its temporary-URL callback, with bounded chunks, cancellation and late-callback fencing. ImageIO checks the actual image type and metadata and creates a bounded thumbnail. The App-owned registry retains immutable selected image bytes rather than retaining the provider's temporary URL. These implementations are present in source; Apple execution has not been established.

The App preview can contain a decoded image thumbnail alongside Core byte evidence. This does not turn the Core metadata flag into an App-decoding certificate, create a server media ID, authorize upload or publish, or bypass the existing upload/register/publish ownership and unknown-outcome rules. Existing Square services, grants, factories, local store and live/media/legal gates remain unchanged. Production enablement must continue to use those explicit gates.

The Core model distinguishes image and video, preserves stable selection IDs and ordered duplicates, and binds checks to session, draft ID, endpoint lane, owner, lease, source reference/version and attempt nonce. MainActor reference ownership prevents copying an earlier state from restoring an old attempt. Reorder preserves per-item checks; completing A does not invalidate B. Remove, replace, cancel, retry, policy changes and owner/scope retirement reject stale completions and previews.

A Core source reference is an opaque ID/version for the App-owned registry, never a URL or filesystem path. Core counts and hashes supplied Data chunks incrementally, keeps no whole video payload, and checks reference/version/kind and byte count before minting non-publicly-constructible byte evidence. Descriptions alone, empty data, wrong references, size mismatches and failed/over-limit streams cannot mint evidence. A reference/version is pinned to its observed bytes within one owner scope; changed bytes require a new version even after clear/reselect.

Core byte evidence remains weaker than decoded content: `appDecodingPerformed` is always false and its strongest aggregate state is `metadataWithinPolicyAwaitingAppDecode`. Synthetic bytes can pass a metadata-shaped example without being a playable video. Core supplies no upload/publication grant or production-decoder result.

All aliases of a stream-check wrapper share one locked lifecycle for hash, byte count, terminal failure and consumed finish. A copy saved after `ab` cannot finish that prefix once another alias attempts an over-limit `c`. Finishing consumes the check for every alias. Retrying requires a fresh attempt. The authored regression tests do not establish Swift runtime behavior here.

## Video remains pending and unavailable

The R2 picker/dispatcher gives a movie representation priority over a JPEG poster. A selected movie returns `videoUnavailable` before its bytes are read, rather than silently uploading its poster as the requested video. No video container/track inspector, video upload/registration contract, video player, inferred video MIME/size/duration rules, or new video grant is delivered by this integration. The original user requirement for a complete video workflow remains open; the image preview and local typed foundation do not satisfy it.

Existing image upload and `IMAGE` registration must not be widened into video behavior without the destination's verified contract. Backend ownership checks and moderation remain prerequisites. Readback must remain authenticated. Expired or revoked approvals and interrupted uploads require explicit recovery handling.

## Policy and lifecycle

Core MIME/count/mixing/byte/duration rules are injected, with no invented production numeric defaults. Missing policy or a required rule yields `policyUnavailable`; an explicit rejection is distinct. These are local formatting rules, not server, participation, moderation or publication authority. XCTest values are artificial fixtures, not business limits. Missing rules never mean unlimited, and integer/dimension/byte/duration checks reject invalid or overflowing values.

Over-limit local collections remain visible with rejection; they are not silently truncated or deduplicated. Local cancel/retry never clears or weakens an existing remote upload/registration/publication unknown lock. Reference release lists express only this selection's ownership and are unique only after the last duplicate is removed; they do not prove file/OSS deletion or retirement of another owner's reference.

Changing account, namespace, epoch, draft or lane requires a new lease and new checks. Fingerprints/policies are not imported across scopes. Equal-value replacements retire prior attempt tokens. Policy changes invalidate previews and attempts; existing byte-bound metadata still awaits the applicable App verification.

## Other media domains and project registration

Ordinary Square posting, ClubCommunity and professional-topic media remain separate domains. The restored ProjectTopicMedia increment contains only six Core/test/documentation files: there is no Topic App host, picker or production inspector in this snapshot, and no live Topic-media policy is invented. Restoring those Core files does not restore the lost later Topic App candidate.

The central integrator has deterministically regenerated the actual combined `Questify.xcodeproj/project.pbxproj`, registering the new App/Core and Square AppUnit sources. Its PBX-only patch is recorded separately from the two original owner patches. Two identical generations, structural checks and the nine existing AppUnit-target tooling tests passed. This is project-wiring evidence, not Apple build or XCTest execution.

All original UI source files, 736 complete UI methods, existing CI/profile files, AppSession/composition factories and the twenty protected Muse paths remain unchanged. No cancelled Next50 increment or unavailable CI131 repair package is included.

## Verification scope

Fresh checks on the recovered combined source passed: 28 focused Python source contracts across Square Core/App and Topic Core; 9 project-target tooling tests; deterministic project generation; scaffold checks for 1,411 Swift source files and 8,091 bilingual keys; and complete forward/reverse patch-tree replay. The eighteen owner source postimages matched their recovered original archives exactly before this explicitly identified documentation-only correction.

Square has 25 authored Core XCTest methods and 34 authored AppUnit methods. They have not been executed in the recovered environment. The owner archives retain their previous parser/scanner receipts, but those are historical records, not fresh checks on this combined tree. Swift/typechecking, fresh Tree-sitter parsing, a fresh secret scan, Apple Core/App/UI tests, real provider reads/decoding, upload/registration/publication and video playback are NOT_RUN here. The full App/79-shard matrix is deferred as instructed. No installation, push, CI trigger or remote publication was performed.
