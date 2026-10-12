# P046 staged profile choices

Normal ClubDetail → existing ClubOperationsWorkspaceView → existing profile form now opens an edit-only sheet for category and activity preferences. Both fields are actual Mini scene-club-edit fields. Choices are staged; Cancel/swipe/background leaves the real form untouched. Apply validates and replaces only that selected field in the same full parent draft. Reopening starts from the current form.

The type catalog is the existing six canonical values. Directions use the existing ten canonical values, selection order and maximum of three. Existing unknown legacy values remain unchanged unless replaced by a valid supported selection; they are never silently normalized. No new API or parallel save exists: the existing update-mine review, fresh profile validation, original writer gate and readback remain authoritative.

The controls require an existing-profile scope, matching club ID, signed-in account/epoch, access object, original owner/admin profile and source read revision. Apply additionally requires the same presentation ID and unchanged full parent draft. Current source availability closes stale sheets. Create-mode controls and all owner-only settings/media behavior remain unchanged. Missing production write approval stays closed.

Source: master P046 lists cy-scene-club-edit. Mini f859cd6e2618f618a53f5cd33949259828e86313 components/cy/scene-club-edit/index.js exposes openTypePicker/openPrefsPicker/pickDraftType/toggleDraftDir/closePicker/applyPicker and the existing update-mine save. This is distinct from the sealed P042 creation guide.

14 native tests cover staging, max-three, cancellation/reopen, scope/visibility/source changes, original owner/admin wire fields, and fake existing review→save→readback with an unverified-writer negative control. XCTest and Apple build/runtime are NOT_RUN without Swift/Xcode. Only necessary static, actual Mini fake-source and supplementary parser checks are run; they do not replace compilation.
