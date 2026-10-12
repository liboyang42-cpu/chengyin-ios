# P055 owner funds → existing support → same-club return

## Actual missing normal-host flow
Master v10 P055 lines 1692–1695 names onStages/goWithdraw and cy-funds-stages. Mini ref f859cd6e2618f618a53f5cd33949259828e86313:
- pages/club/settlement/index.wxml mounts funds stages only when the current server summary has isOwner=true, including empty settlement rows.
- pages/club/settlement/index.js uses onStages unknown/zero/positive and opens withdrawal customer service only for positive. It explicitly retired requests to club/settlement/withdraw.
- components/cy/funds-stages/index.js POSTs api/wallet/stages with JSON {}, emits known/positive; view-model.js rejects missing/invalid amounts, preserves complaint dates and amountsKnown=false.

The previous club-settlement-detail package implements per-topic settlement row detail. P042/P045/P056 terminal/report, and rejected-topic drafts do not implement owner funds. This adds actual existing read-service integration, not a local substitute or a second financial product.

## User path
Existing club governance workspace → settlement → owner account funds. ClubOwnerFundsTarget requires the exact current club-only settlement scope, signed-in principal, active club:finance:read, a valid settlement response and server isOwner exactly true. A role label, ClubRecord owner flag or delegated finance permission alone cannot read the owner's wallet.

Normal AppSession composition injects its existing cached walletHistoryReader and WithdrawalSupportContactView using the existing withdrawalSupportReader. It does not instantiate an approval, transport, credential or financial writer. Context defaults nil/false.

Before wallet stages are requested, the workflow re-reads settlement and validates owner/finance access. After the wallet request it repeats the same proof, preventing ownership loss in flight from exposing funds. Reader account and namespace must match current club access; reader scope UUID, club identity/epoch, access instance, authorization generation, wallet history view identity and host source generation fence the result.

Pending settlement, complaint-period dates, disputed and withdrawable amounts come from existing WalletFundsStages. Currency is never inferred; missing currency remains unknown. Owner account funds are explicitly labelled as account-wide, not this club's settlement total. As in Mini, empty settlement rows still show owner funds but do not offer contact. Unknown/zero block the contact action. Positive balance enables an explicit contact action that performs another complete owner/finance/stages read before presenting the existing support page. Return reloads the same club's proof and funds. Background, source change, sign-out, lease/reader replacement and late result invalidate data and support routing.

There is no bank page link, amount form, payout, settlement mutation or new clipboard behavior. The reused support page retains its own reviewed-contact/current-session/copy fencing; no contact value is embedded here.

## Existing interfaces and remaining deployment dependencies
- ClubGovernanceAccess.read(.settlement, scope: clubID) preserves existing access/me and club:finance:read checks; exact endpoint api/club/settlement/summary.
- WalletCommerceReader.readClubOwnerFunds delegates only to existing reader.read → WalletCommerceService.stages, POST api/wallet/stages with JSON {}. Existing walletHistoryReadApproval route/lease remains authoritative and unchanged.
- WithdrawalSupportContactView consumes the existing WithdrawalSupportReader. Its Source/approval are deployment inputs that remain nil where originally nil. Missing contact configuration is honestly shown by the existing support view; no invented endpoint/contact or authorization.

Source closure is complete against f329ff5180551ef3956b2718cb9ef071e2635409/tree e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd. Production availability depends on those already-defined read/contact configurations. This batch does not configure them or claim a live backend run.

## Verification scope
12 product paths; four existing club/session hosts have narrow additions only, 3 Xcode references and 6 EN/ZH keys. AppSession is edited and syntax-parsed as a Git blob in memory, never copied to a new full file. Shared wallet/withdrawal core/views and their grants remain unchanged.

10 Core +14 App XCTest methods include actual existing service adapter request-shape assertions and fake owner→stages→fresh positive→support→return, missing owner/permission, unknown/zero, account/namespace/revision change, source disappearance and late response. XCTest/Apple compilation/runtime are NOT_RUN. Original Mini function execution, supplementary tree-sitter byte parsing, structural checks and Git forward/reverse tree verification are distinct evidence.
