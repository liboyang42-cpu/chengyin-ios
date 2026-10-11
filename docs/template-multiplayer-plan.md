# Roles and turn order (P036)

Unique source: master P036 `addMultiplayerRole`, `updateMultiplayerRole`, `removeMultiplayerRole`, `onTurnOrderChange`; real Mini JS 689–708 and WXML 944–967. Current native generic roles/per-string order controls have no bulk delimiter entry or same-page role/reference workflow. This new destination replaces only the supported multiplayer roles/turnOrder fields at the top level; all other fields and malformed generic fallbacks remain.

Authors add roles, edit role IDs/labels/minimum/maximum, reorder or remove rows, then paste/type the turn order using ASCII commas, Chinese commas and ECMAScript whitespace. The order keeps repeated IDs and exact sequence. The readback shows each stored turn and its role label, or flags missing/ambiguous IDs. Renaming/deleting a role deliberately leaves the order untouched, matching Mini, so the author can explicitly resolve references. Role reordering retains existing native behavior and never reorders the turn sequence.

New roles use Mini's `min:0,max:1,label:""` with a collision-safe opaque `role_` UUID identifier rather than the Mini's timestamp suffix. Existing default player min1/max4 stays unchanged. Finite numeric input is stored as a number; unfinished/empty numeric input remains editable and invalid under the existing native validator rather than being silently converted to zero. Raw numeric spelling and trailing order separators remain local editing state. Reopening/restoring reconstructs it from the stored numbers and `[String]` order. Nothing is normalized merely by opening, and unknown fields survive explicit edits.

Existing validation owns role count, ID validity/uniqueness, capacities, references, 1–100 order entries and automatic-assignment coverage. This editor displays those errors without inventing a team assignment or running a server session. Local save/restore uses the existing draft contract. The turn preview reads the edited draft; it is not a claim that the draft has already been saved to disk or server.

Session, draft, media, pending-state and lifecycle guards reject retained controls after changes. Structural actions invalidate retained inputs. Review-only parent `changed()` refreshes do not interrupt continuous editing; actual external draft emissions require reload. Exact encoded fingerprints distinguish Unicode byte changes. No schema/storage/rehearsal/permission/network additions.

Register the new App/Core source and App XCTest using `docs/registration/template-multiplayer-plan.json`; merge 15 keys in `docs/localization/template-multiplayer-plan.json`. Apply shared-view edits additively, retaining all earlier entries. No earlier feature package dependency.

Core/App XCTest are authored but NOT_RUN without Apple tools. Source contracts and original Mini event checks are supporting evidence only. No native UI, real multiplayer allocation, formal gameplay, rewards or backend writes are claimed as executed.
