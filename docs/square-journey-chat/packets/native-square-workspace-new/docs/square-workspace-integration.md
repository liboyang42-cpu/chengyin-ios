# Square workspace: additive integration

## Scope and source truth

- Visible Flutter composer: `app-audit/lib/feature/square/square_compose_page.dart:181–205, 482–589`; exact legacy multipart `square_api.dart:152–183` and `play_api.dart:439–455`.
- Separate dormant v1 lane: `square_api.dart:240–487`; community-proof upload is `play_api.dart:458–488` with `bizType=COMMUNITY_POST`, top-level `url`, `byteSize`, `mimeType`, `uploadReceipt`.
- Local drafts: `square_local_draft_store.dart`, secure owner-scoped store; draft model includes source workflow keys. Native adds deployment namespace and in-flight epoch isolation, with device-only Keychain storage.
- Known source divergence: visible legacy submit never sends audience/comment/disclosure fields. Native legacy validation refuses silently dropping non-default controls. Editing legacy media/location is explicitly retained by source; native does not pretend those changes were submitted. V1 remains an independently selected, undeployed/unverified contract, never fallback.
- Non-image retained media IDs survive v1 edits. Reference CLUB IDs remain separate from community IDs. No automatic membership or ID conversion.

## Files and host wiring

Copy only files listed in `square-workspace-changed-files.json` to corresponding `chengyin-ios` paths. Do not replace Package.swift, existing project, catalog, SquareBrowserView, SocialAction files or ClubCommunity files wholesale.

1. Add new `Core/SquareWorkspace*.swift` and `App/SquareWorkspace*.swift` files to the app target; Core SwiftPM auto-discovers its files. Add authored tests to their existing targets. Use the repository project generator when integrating, not an isolated replacement project.
2. Merge `docs/square-workspace-localizations.json` into the existing xcstrings catalog using `tools/merge_square_workspace_catalog.py <existing-catalog-path>`. It fails on conflicts and only adds namespaced keys.
3. In the existing Square browser host, add a separate entry for `SquareWorkspaceView(coordinator:)`. Supply account ID, deployment namespace and epoch from the current authorized session. Host the whole subtree with `.id(session)` and discard it on account/epoch/region changes. The coordinator also guards every transport completion and next pipeline stage.
4. Use `SquareWorkspaceSecureStorage(scope:)` with the reviewed `RegionalSessionStorageScope`. The service is device-only, unlocked-only, non-synchronizable Keychain. Do not use the synthetic memory store in production, UserDefaults, cloud sync, or migrate Flutter storage implicitly.
5. Keep `service: nil` and all three grants false by default. A configured read URL alone does not authorize mutation, media upload or guideline acceptance. If separately approved later, inject the existing no-redirect approved HTTP transport and a current-token closure. No transport, provider, credentials or grants are provisioned by this module.
6. Do not replace SocialAction reaction/comment/follow/chat/report flows. For compose and edit, route explicitly to the new workspace; existing simple editor can remain until host wiring is reviewed. New draft defaults to the visible legacy lane. Server draft resume uses the explicit v1 lane. The governance module may link here via its `openDrafts` callback.
7. Add DEBUG module dispatch `square-workspace -> SquareWorkspaceFixtureHost()` to the current fixture switch, keeping all existing cases. The fixture enables no network. UI tests are authored for this dispatch, not yet run or silently wired into a shared host.
8. For an edit entry hydrate `SquareWorkspacePost.editableDraft()` only after owner-scoped fresh detail. Do not default absent version/author/lifecycle into an editable state: native deliberately rejects incomplete detail projections. A missing server version therefore blocks edits, rather than inventing a concurrency guarantee.

## State and safety

- Opening view, selecting photo, selecting reference, editing or saving locally never posts or uploads. The Photos picker only reads a user-selected item; Upload is a separate explicit button. Coordinates/GPS/EXIF extraction/provider SDKs are absent.
- Review freezes draft, identity, guideline and original post. Confirm re-fetches guideline and original version/status and rejects any change. Policy acknowledgment requires distinct legal grant plus explicit checkbox.
- V1 pipeline: acknowledge current guideline → media register with exact `media-{index}-{workflow}` keys → create/PATCH with `post-{workflow}` → publish with `publish-{workflow}` only if returned lifecycle is DRAFT → fresh detail. Existing published edit may return review state without a second publish call.
- Legacy ack is not publication evidence and has no promised new-post ID. New-post acknowledgment stays explicitly unverified; no invented lookup or automatic retry.
- Pending markers are persisted before mutations. Timeout, ambiguous payload, cancellation, changed session, partial registration, readback failure and restart retain locks. Successful submission also retains a receipt lock; the host must not clear it merely to make Publish available. Read-only reconciliation or a new intentional revision is required. No automatic retry, resend, cleanup upload or orphan deletion.
- A completed server save resumes a fresh server projection under a new source-compatible workflow ID, retaining existing media IDs. Old completion receipts block replay so removing/reordering media cannot reuse an index key for a different upload. Incomplete media readback remains locked.
- Save-server never acknowledges a guideline or publishes. Published edit drafts are local-only until explicit publication review.
- Revision history preserves server entries as returned (no invented moderation interpretation). Location withdrawal uses exact DELETE, expected version, fresh owner check and readback; its marker stays locked pending explicit reconciliation. No share action is included.
- Account/private drafts remain inaccessible across account and deployment namespace changes; epoch changes invalidate in-flight operations without destroying intentionally restorable drafts for the same account/namespace.

## Verification and known limits

Python source checks and pinned Tree-sitter parsing were run. SwiftPM, Swift compiler/typechecking, Xcode build, simulator/device/UI runtime, Photos/Keychain runtime, actual HTTP, upload, location and publication are NOT_RUN. There is no Swift compiler or Apple SDK in this environment. Parser success is not compiler evidence.

Server draft/edit hydration requires complete private fields. Backend rollout proof, production grants, link from actual navigation and real status reconciliation remain explicit integration/enablement tasks. References and member choices depend on source-backed but unverified v1 endpoints; no guessed replacement API is called.
