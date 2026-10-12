# Photo-check framing outline (P036)

Source: master P036 `clearPhotoFrame`/`onAdvancedField`, real Mini frame image and0–100/step5 slider in WXML773–797, plus the matching JS handlers. Native49's generic frame URL/opacity fields and delegated viewfinder placeholder do not provide actual-frame preview and slider composition. No prior package covers it.

The existing frameUrl entry opens one workflow: edit an already available address, explicitly load/retry its preview, adjust opacity with the source slider range/step, clear the frame, and use existing local save/restore. Generic malformed configurations remain editable through the previous controls. No new upload, photo selection, camera or vision capability. This closes the existing-address configuration flow; it does not claim Mini upload parity.

Only user-triggered preview creates an AsyncImage request for a validated absolute HTTPS URL without userinfo, fragments, backslashes or control/space bytes and at most512 UTF8 bytes. Relative site paths remain editable/persisted, but no server base or authentication is invented to resolve them. The two-tone background is a native transparency aid, not a photograph, result or part of the stored frame. Image opacity follows the existing percentage field. Nothing fetches on opening or restoration.

A changed address, explicit clear, external draft emission, owner/media/lock change, leaving or backgrounding invalidates the request identity and hides the old preview. Late callbacks cannot update the current state. Retained slider input cannot apply to a replacement address. Own opacity edits and the parent's review-only changed() refresh retain the loaded request, enabling continuous adjustment. On resume the user reloads settings and explicitly loads again. View removal retires display/callback state; no claim is made that a transport has completed cancellation without native verification.

Clear writes the source empty string and retains current opacity in the local draft. Existing serialization normalization removes optional frameUrl/frameOpacity when no frame remains. Other photo-check fields, unknown supported values and other families remain unchanged. Range/media validation, storage and serialization code are untouched.

Registration fragment lists App/Core sources and App XCTest. Merge14 localization keys, then apply the shared-view patch additively. No prior-package dependency and no permission/central configuration changes.

Core/App tests are authored but NOT_RUN without Swift/Xcode. Request callbacks in App tests are simulated unit events, not successful image loads. Source checks and original Mini event checks are supporting evidence only. Actual image fetching, rendering, opacity interaction, native lifecycle, local-save gestures and formal photo review have not been run here.
