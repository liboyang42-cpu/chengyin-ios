# Native self-profile editing

## Scope and verified source
- `app-audit/lib/data/api/registration_api.dart:114–130`: self profile is POST `/api/user/info` with an empty multipart form, no member_id. Read response is `code:200, data:{...}`.
- Same file, `updateProfile` (around 256): POST `/api/user/update`, JSON, `code:200` acknowledgment.
- `app-audit/lib/data/models/profile_edit.dart`: required trimmed name, optional trimmed introduction; update fields are name/avatar/introduction/wechat/casePics/tagIds. casePics is semicolon-delimited and tagIds comma-delimited. The update overwrites these fields.
- `profile_detail.dart`: read name is nickname; tag categories may be supplied in sysCategoryList. wechat holds the contact QR image URL in the editor, not an email/phone binding.

This bounded native Form edits nickname/introduction only. Image uploads, photo removal, contact QR changes, preference editing, password, phone and email bindings are not implemented. There are no fabricated US identity fields, HTTP requests in fixtures, uploads, or automatic retries.

## Preservation and safety
Raw untouched replacement strings are preserved, including whitespace and order. Explicit null means the source's empty value; missing replacement fields fail closed. tagIds is used verbatim when present; otherwise a present valid sysCategoryList is required. The service never serializes arbitrary read-only user properties into an update.

Review loads the latest self profile and compares editable values against the loaded original. Confirm performs another self read, compares the entire preservation snapshot, and refuses a changed snapshot rather than overwriting concurrent edits. The confirmed payload is immutable. This is client-side conflict detection, not an atomic server compare-and-swap; a final race remains because the observed source has no version/ETag update contract.

The retained coordinator guards account ID, session epoch, and actual token before and after asynchronous boundaries. Wrong-account reads fail. Stale responses cannot replace current state or expire replacement credentials. Unknown acknowledgment/transport outcomes lock the account against another POST. Only a known successful acknowledgment plus an exact server readback releases the lock. A matching read after an unknown outcome is explicitly reported as current matching state, not proof that the original request finished; it never unlocks or claims a verified save. An acknowledged write with failed readback can be reconciled by a later matching read. Divergent or failed reads keep the lock. Locks survive navigation and same-account reauthentication during this process, but are intentionally not persisted with profile data across app termination. After relaunch the first edit still requires fresh read/review; durable cross-launch operation IDs require a server contract.

## Application integration
1. Create optional ProfileEditService with existing approved configuration and no-redirect transport.
2. Retain ProfileEditCoordinator on AppSession; currentSession must use live account/epoch/token. Call synchronizeSession on session transitions. onUnauthorized must recheck captured session; onSaved can invalidate other profile projections without inventing an Account nickname update contract.
3. Add an account navigation destination `ProfileEditView(coordinator: ..., sessionRevision: ...)` and register new App/Core files in the Xcode target if needed.
4. Merge `profile-edit-localizations.json` into the catalog. UI keys use native Text lookup and environment locale.
5. DEBUG launch flag `--uitesting-profile-edit-fixture <success|rejected|unknown|missing>` routes directly to ProfileEditFixtureHost before creating AppSession. Add AppUITests file to test target.

## Verification
Added pure domain/service tests for exact contracts, preservation, fail-closed fields, required nickname, immutable confirmation, no replay, token replacement, preflight conflict, readback, rejection, and unknown-result navigation/epoch lock. Added synthetic native UI flows for success, unknown lock and incomplete data. No Swift compiler or iOS simulator is available in this Linux authoring environment, so these tests are supplied but not claimed executed. `git diff --check` and JSON parse checked locally. No live APIs were called.
