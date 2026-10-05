# Merchant template AI assist

## Implemented boundary

The merchant template list and existing/new template editor now expose an assist sheet. Opening the sheet sends nothing. A shop/template name and gameplay prompt are required. Only the explicit Generate action can call POST `api/ai/template/fill` through the existing auxiliary service.

The production provider feature is independently scoped as `publishingAITemplate`. Default configuration still has no routes; the existing publishing read/write, theme and club grants cannot enable template generation. The transport checks the exact origin, account/session epoch, POST path, JSON body whitelist, required `shopName` and `extraNote`, and supported optional validation method. US generation remains disabled. No real provider calls were made during this work.

The native merchant access reader is refreshed before Generate and before Apply. Session changes, sign-out, source reload, discard, successful save, closure and cancellation fence late results. A review is tied to the same loaded coordinator/draft identity, including a new unsaved template with no server ID.

## Explicit return to the draft

Review displays supported suggestions and every nonempty unsupported returned field. Template, node and root response shapes follow the retained Flutter reader, with template taking precedence. The source's six-field empty-result rule remains intact.

Apply returns a merged value to the existing `MerchantOperationsViewModel.edit(.template(...))`. It never saves, publishes, creates a replacement editor or bypasses ordinary draft validation. Existing values are kept. Field revision counters also protect edits followed by an intentional clear while generation or the permission read is pending. Title, description, question, answer, options and feedback map to the existing native draft; its save contract continues using `questionA`…`questionD`, distinct from AI's `optionA`…`optionD` response.

An unselected method can adopt a recognized AI method. A correct answer is applied only for a quiz with at least two populated options, a legal letter, a matching generated question and matching selected option. Existing manual choices are never replaced. The full story remains visible as unsupported; when description is absent, only its first 30 characters can fill the empty description. Badge, hints, reveal, rules, unknown methods and future fields remain visible without silently adding them to the save payload. Existing media, ID and coupon association are untouched.

## Outcomes

- Permission/sign-in rejection is non-retryable in the sheet and explains checking identity/access
- A definitive provider rejection, malformed or empty result permits a deliberate retry
- Unknown transmission outcome retains the auxiliary service's durable replay lock; no blind retry
- Cancel means stop waiting and discard the candidate. It does not claim an already sent provider request was stopped or quota restored
- Closing/swiping away/backgrounding never applies a candidate

## Verification

Authored: 23 pure Swift tests and 4 synthetic UI tests, covering input/route gates, response wrappers, supported/unsupported fields, non-overwrite and edit-clear merges, explicit apply, default-off, permission/provider/unknown outcomes, cancellation, repeated Generate, session/reload/discard fences and zero saves. Synthetic UI is reachable only through an explicit DEBUG fixture argument and has no HTTP transport.

Executed in the Linux workspace:

- 8 focused Python source/localization checks with the supplied Flutter checkout: PASS
- 81 tooling tests: PASS
- 737 standard Python contract tests: PASS, 44 skipped (optional source unavailable)
- 15 changed Swift files parsed by the pinned Tree-sitter pair: PASS
- Project generation and structural/bilingual/determinism checks: PASS

Swift typechecking/domain tests, Xcode builds and synthetic UI execution: NOT_RUN. Swift/Xcode are not installed in this workspace. Source parsing and Python checks are not substitutes for those gates.

Supplying the private Flutter snapshot to the entire optional-source suite produces one pre-existing `SUBMIT_COMPARE` expectation mismatch in `test_play_experience_contracts`. The same failure is reproduced against the untouched base; no unrelated gameplay edits are included.

The source contract was checked against Flutter `merchant/ai_node_assist.dart` and `node_template_edit_page.dart::_aiAssist`, plus backend `ApiAiController.templateFill` and its response DTO. No backend, production deployment, scope grants, World/Season or platform-upgrade changes are included.
