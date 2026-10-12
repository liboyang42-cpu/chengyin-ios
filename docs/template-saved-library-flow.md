# P036 verified draft result and library navigation

Base f329ff5180551ef3956b2718cb9ef071e2635409, tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd.

## Source and scope

The sole master P036 lists onResultSheetClose/onCreationSuccessAction. Mini pages/publish/temp/index.js at95e499471eaa39c28f77d16125f0cc17b8c37123,blob76e39df5c326aaf029bda8da21562072fb352553 declares RESULT_SHEET_MS=2000 atline7. Lines2843–2923 require a positive createdId before successful draft/publish result;2916–2923 set resultSheet,2947–2950 close it then reLaunch the own template library. The fabu/node branch2894 and2952–2964 instead preserves separate return/continue actions.

Native before this change has ordinary editor and library entries, owner-checked savedDraft receipts and separate project-node receipt return. It lacks the ordinary saved-result-to-library transition. Existing samples, presetsoverrides and35unsavedBack do not implement this navigation. No private Mini module is copied.

## Complete ordinary draft workflow

The ordinary TemplateAuthoringLaunchView editor destination now uses TemplateAuthoringSaveFlow. The existing editor emits a read-only preference observation through one additive modifier; all constructor arguments and other callers stay unchanged. The node binding branch onSavedDraft!=nil emits no observation. Other roots have no consumer.

A current editable owner/identity visit must be observed before a new save can display success. The coordinator must subsequently expose its exact acknowledged savedDraft: positive member-template ID, matching owner/session/identity/operation and request hash, persisted with the terminal pending record. Existing reopened terminal journals do not auto-present as new saves. Synthetic,unknown,missingID,failedreceipt,changedowner/identity and publish-only acknowledgements do not produce a success panel.

The result shows the verified receipt ID and submitted title. A controllable2-second timer or explicit Open template library button replaces this pushed destination's editor with the existing TemplateAuthoringMineView. The existing shelf coordinator, owner configuration/detail/consent closures and shelf identity are retained exactly. Back returns to the ordinary launch. The central NavigationStack is unchanged. No fake library screen, guessed title search, resubmit, draft deletion or beginNewDraft occurs.

Background suspends the timer and retires callbacks; foreground uses a fresh2-second timer if the same verified visit remains current. Disappearance fully retires admission, so reentry cannot reuse an old success event. Close/tick/binding callbacks capture presentation IDs and generations. Live model metadata,media,revision,full draft bytes,busy/review and receipt checks guard them even before preference propagation. Completion is one-shot. Draft/storage/journal stay untouched.

## Exact remaining interface boundary

TemplateAuthoringSavedDraft.init/responseID intentionally accepts only /api/template/draft. TemplateAuthoringAdapter.submitWithReceipt therefore has no typed positive-ID receipt for /api/template/publish; legacy acknowledged status alone is insufficient to implement Mini's positive-ID success branch. That publication result/navigation is NOT_IMPLEMENTED_DEPENDENCY and not counted complete here. This batch changes no transport,service,coordinator,API or grant. Project-node return/continue remains in its existing flow.

## Registration and tests

Three new production files,one App test andCreatorSavedResult.xcstrings enter actual Xcode phases. One Core test uses unchanged directory discovery. Five EN/ZH keys all explicitly use tableName CreatorSavedResult. Source tests,real pinned Mini callback execution,byte-exact host changes,PBX checks and fulltreepatch roundtrip are recorded separately.

Native compile,Core12/App16 XCTest methods,automatic sheet dismissal/navigation,voiceover/dynamic type and actual device UI remain NOT_RUN without Swift/Xcode. Supplementary Swift grammar is not typechecking. Real network,content publication,upload and permission prompts are not exercised.
