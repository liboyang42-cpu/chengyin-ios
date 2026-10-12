# P055 Club settlement exact-row detail

## Scope and source

Base `49c68c6420270b0a0cc7ec8d18bc8561f329d796` plus the exact sealed14 roster and15 series-occurrence patches. Composite preimage tree: `c46c697d62de7b7f61a3e91ffeb63b191d8d9349`; shared `App/ClubGovernanceViews.swift` Git blob: `967e00ec62933010dd57a19290a7ae461ccde5d7`.

Only the `dataRows(value["topics"].array ?? [])` line inside the `.settlement` branch is replaced by the independent Club row/detail component. Existing settlement summary/header and every byte outside that line's replacement remain unchanged, including14's roster and15's series hunk. No cooperation, wallet, form, transport, permission, AppSession, PBX, aggregate catalog or CI file is modified. P043/map6 remains cancelled/paused.

Unique master `MASTER-v10-extracted-text.txt`: P055 lines1692–1695 (`goTopicSettlement`); adjacent destination P094 lines1848–1851 (`onNavBack`, `retryLoad`). This implementation is the Club-owned P055 entry and Club summary read path only, not a change to other cooperation/merchant settlement flows.

Mini revision `f859cd6e2618f618a53f5cd33949259828e86313`:
- `pages/club/settlement/index.js`, blob `d4d4f3d685feafb1a53bbe5cfde6f9ae43add3c6`: `normalizeSummary`, `loadSummary`, `goTopicSettlement` establish authoritative formatted fields and navigation carrying source=club, clubId, topicId and settlement row id.
- `pages/club/settlement/index.wxml`, blob `3b45abc9ddc29f7289ecf769fa8d85a0d4567c6f`: topic rows carry both topicId and row id and show pending/void/unverified/credited semantics.
- `pages/coop/settlement-detail/index.js`, blob `c9b3e1fad3b190f87a9baa01b7a211042035ba50`: source=club rereads `/api/club/settlement/summary`, chooses record key id when supplied, retries, reports missing record, retires late requests and returns to the scoped Club page.
- `pages/coop/components/settlement-detail/view-model.js`, blob `6c2423cb8ae233900a3a2a87932ff1a61fb83a24`: `clubStatus`, `clubAmountLabel`, `buildClubSettlementDetail` supply the field/status presentation. Older comments mention topic matching; the actual destination handler prioritizes the supplied row id. This packet follows the handler.

Before this increment, native Club settlement rendered generic row facts without a detail action; existing CoopFlow settlement sources were finance/mybiz only. The new Club flow does not misroute a Club beneficiary to either source.

## Complete ordinary flow

The ordinary Club settlement screen passes its actual accepted snapshot/context, current identity and existing authorized access directly to the row component. Each source-ordered row opens a details sheet with exact club scope, topicId and settlement row id. Two rows for one topic remain separate. Repeated taps cannot create multiple destinations.

The details screen uses the existing `.settlement` read contract: POST `api/club/settlement/summary`, clubId only, with unchanged `club:finance:read` permission. The unchanged full summary validator runs before projection. Fresh response selection is by settlement row id and also verifies the original topicId; it never uses the row id as a topicId and never falls back to the first same-topic record.

A successful read shows the source title, Club perspective, explicit amount label/status, original amount due, executed adjustment, net amount, arrival text, payout text and record/topic identifiers. All financial/timeline strings are displayed verbatim. There is no numeric conversion, arithmetic, amount default, invented payout date, wallet request, withdrawal/support action or financial command.

Pending rows label the amount as awaiting credit; void rows label it as the pre-void net amount. Settled/unverified rows show verification pending and preserve null amount; settled/verified rows show credited. A server-formatted zero remains a real displayed string, not an inference. Net amounts/adjustments are not treated as proof of money arriving.

Loading, read error/retry, permission denial and missing-record states are separate. Refresh clears old amounts before reading; a failure does not continue displaying stale money. Mini's destination can retain explicitly stale detail on failure, while this new native flow deliberately hides it. If the row disappears, a localized unavailable message replaces the detail rather than selecting a different row. A changed amount on the same row/topic is accepted after a fresh read.

Close/swipe return refreshes the original Club summary through the existing parent load function. The header and financial gate remain as before. There is no command creation or dispatch in this feature.

## Isolation

The source target binds the rendered record, club/topic/row IDs, accepted source context, parent read generation and namespace. Opening requires the parent snapshot still be current and no newer parent read be in progress. A namespace, account/epoch, authority, access object, source snapshot/generation or row change invalidates selection and retires the sheet.

The details model binds the target instance and read context to each visibility permit, checks the exact target's original identity/authority/access/namespace, and fences both sides of the awaited existing reader call. Old target instances cannot be activated under a replacement account/namespace. Latest-request tokens prevent a cancellation-ignoring old read from replacing a newer result. Closing retires permits and hides accepted content. Fresh finance permission is checked again when projecting each response.

The parent may carry viewer revisions from unrelated contextual readers; details use their own revision0 but target read matching retains the original account, authorization generation, access object and namespace. Full source-route matching still checks the complete parent context, including viewer revision.

## Registration and delivery

The registration fragment lists one new App source, one Core source, one Core test file, one AppUnit test file and21 bilingual keys. Apply the delta after exact14/15 dependencies on49. If central integration already has other non-overlapping Club changes, reconcile only the authorized settlement-line hunk; do not replace the whole shared file from `after`. The full before/after images exist for audit and exact reconstruction. All15 earlier packet hashes remain unchanged.

## Verification

Executed locally in the authorized dot workspace:
-39 focused structural assertions PASS, including the exact original single-line replacement, preserved series/roster/header bytes, ordinary reader wiring, target identity, fresh validation, unknown amount semantics, return refresh and unchanged protected files.
- Existing governance contract suite:12 checks PASS.
-4 exact source Git blobs verified. Actual Mini functions executed against local transport/navigation spies: Club-scoped URL/read; exact second row with same topic; server field passthrough; missing record without topic fallback; pending/void/unverified; retry, malformed/network states and unload retirement; scoped back and missing-club guard. No network request or financial operation was executed. Initial source-oracle setup lacked an inert theme hook; that harness-only stub was added before the successful rerun.
-5 Swift files parsed by Tree-sitter with zero diagnostics. This does not establish Swift typechecking, Apple API compatibility or runtime success.
- Patch apply/reconstruction/reverse check and15 sealed prior packet hashes verified.

Authored12 Core and10 AppUnit tests: **all22 NOT_RUN** because Swift and Xcode are absent. Native build/typecheck, simulator, UI/VoiceOver, screenshots and live-account reads are **NOT_RUN**. The existing production reader is connected in code; live service availability is not claimed.

Apple acceptance after central registration: ordinary Club settlement→a specific row among duplicate topicIds→fresh detail→refresh/retry/missing row→close and summary refresh; confirm all four status/amount labels and raw strings; rapid tap/close/return; permission loss, account/epoch/namespace/access replacement and out-of-order reads; large type/VoiceOver. Do not execute actual payments, transfers, withdrawals or notifications.
