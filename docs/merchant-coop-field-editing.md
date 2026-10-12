# Merchant cooperation field editing

Source: MASTER-v10 P081, C01/C02/C03/C05; Mini coop-setting editField/editInput/applyEditor/closeEditor/keepEditing/discardChanges. Exactly capacity, availableTime and demand are staged independently.

The existing cooperation page and three coopField calls mount the new entries through one helper-body replacement. Opening/typing does not change the owner draft. Apply consumes its field session, then invokes existing model.edit(.cooperation) for only the selected field. It never prepares/confirms/saves a server command. Charge choice, hidden suitActivityTypes/coopOpen, original loaded-capacity clear bookkeeping, full-draft review and write gates stay unchanged. Clearing capacity uses the original explicit clear-capacity contract.

Dirty Cancel offers discard of this field buffer or Keep editing. Keep editing preserves exact raw text. Dirty interactive dismissal is disabled; use Cancel for the choice. Closing an unchanged field needs no prompt. Scope/revision/draft identity, full exact draft and baseline values fence apply; source refresh, sibling changes, review, whole-draft discard, logout, background and leaving retire old buffers. Old route IDs cannot dismiss replacement sheets.

The source’s length limits are enforced conservatively at Apply using UTF-16 counts (capacity/time100; demand500), with no silent normalization or truncation. Changed capacity must be empty or an ASCII nonnegative integer within the existing Swift Int domain. Historical unchanged values are no-op applied or canceled, never migrated automatically; original whole-draft validation still decides review eligibility.

Nine new leaves plus one NOT_APPLIED exact hunk in MerchantOperationsEditor. Existing operations DEBUG fixture is reused via its ordinary cooperation entry, with no new production provider or fixture switch. Three runtime/three native-test registrations and nine bilingual keys. Native Swift/XCTest/Apple UI execution is NOT_RUN in the cloud; source checks and Tree-sitter are supplementary only.
