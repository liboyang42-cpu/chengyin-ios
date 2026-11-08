# UG capability registry (rt-04): names the owner must ratify

STATIC. Read from `origin/claude/be-v2-fixes` (537e43c7). Every capability-name string literal matching `<dotted>@<n>` in `chengyinhub-*/src/main` is listed. Format of an id (enforced only by G37): `^[a-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)+@[1-9][0-9]{0,3}$` (`ContentCapabilityRegistryG37.java:131`). G38 uses a looser regex `^[A-Za-z][A-Za-z0-9.]{0,63}@[0-9]{1,4}$` (`PlayHelpViewG38.java:25`).

Status key: **KNOWN** = the code comment says the name appears as an example in the contract (appendix A/B); **INVENTED** = the code comment says the author invented it; **UNSTATED** = no comment. The status column is taken from code comments, not from the contract document, which was not available to me.

| # | Capability string | Constant (file:line) | Group | Status per code comment | Where used (reads/returns) | iOS use |
|---|---|---|---|---|---|---|
| 1 | `hint.ladder@1` | `ContentCapabilityRegistryG37.HINT_LADDER_1` `web/service/play/cap/ContentCapabilityRegistryG37.java:37` | G37 | KNOWN | only listed in `KNOWN` (`:39-40`); no reader | NONE |
| 2 | `hint.ladder@1` | `PlayHelpViewG38.CAPABILITY_HINT_LADDER` `business/support/PlayHelpViewG38.java:14` | G38 | "example string from contract appendix A" | required when ladder enabled; `compatibility()` (`PlayHelpViewG38.java:33`) on `GET /api/play/help` | NONE |
| 3 | `hint.ladder@1` | `PlayHelpPolicyG39.CAPABILITY` `business/service/g39/PlayHelpPolicyG39.java:8` | G39 | comment says "INVENTED NAME" (package only gives it as example) | `PlayHelpG39Service.compatibility :166-174` on `GET /api/play/help/quota` | NONE |
| 4 | `node.photoCheck@2` | `...G37.NODE_PHOTO_CHECK_2` `:33` | G37 | KNOWN | only in `KNOWN` list | NONE |
| 5 | `node.scan@1` | `...G37.NODE_SCAN_1` `:34` | G37 | KNOWN | only in `KNOWN` list | NONE |
| 6 | `node.compass@1` | `...G37.NODE_COMPASS_1` `:35` | G37 | KNOWN | only in `KNOWN` list | NONE |
| 7 | `engine.zodiac@1` | `...G37.ENGINE_ZODIAC_1` `:36` | G37 | KNOWN | only in `KNOWN` list | NONE |
| 8 | `node.voiceAnswer@1` | `...G37.NODE_VOICE_ANSWER_1` `:38` | G37 | KNOWN | only in `KNOWN` list | NONE |
| 9 | `help.skip@1` | `PlayHelpSkipG41Service.CAPABILITY_SKIP` `web/service/play/PlayHelpSkipG41Service.java:37` | G41 | INVENTED ("ratify with owner", `:35`) | `negotiate :87-95`; returned as `capability` in `POST /api/play/help/skip` body (and stored receipt) | NONE |
| 10 | `gameplay.hangman@1` | `HangmanLogicG42.CAPABILITY` `business/hangmang42/HangmanLogicG42.java:20` | G42 | UNSTATED in code | `compatibility :228-238` on `POST /api/play/hangman/state` and `/submit` | NONE |
| 11 | `qa.optionImage@1` | `QaOptionMediaG43.CAPABILITY_QA_OPTION_IMAGE` `business/service/support/QaOptionMediaG43.java:19` | G43 | UNSTATED | `negotiate :107-121`; NO production caller (never evaluated on any route) | NONE |
| 12 | `play.accusation@1` | `AccusationJudgeG44.CAP_ACCUSATION` `business/service/support/AccusationJudgeG44.java:18` | G44 | UNSTATED | `AccusationServiceG44.capability :45-56` on `GET /api/play/accusation`, `POST .../confirm` | NONE |
| 13 | `play.earlyClosure@1` | `AccusationJudgeG44.CAP_EARLY_CLOSURE` `:19` | G44 | UNSTATED | same; both are required together (client must declare both for `supported:true`) | NONE |
| 14 | `clue.transform@1` | `ClueTransformG46Support.CAPABILITY` `business/service/support/ClueTransformG46Support.java:27` | G46 | "Names I had to invent" (`:24`) | `compatibility :113-121`; NO production caller. `apply :97` runs on `GET /api/play/nodes` without negotiation | NONE |

Note: `hint.ladder@1` is defined three times with the same value (rows 1-3); there is no single source constant. The three evaluators disagree on the undeclared case (see route table, cross-route finding 1).

## Related non-capability names (also invented, same ratification call)

| Name | Where | Kind |
|---|---|---|
| Headers `X-Client-Platform`, `X-Client-Version`, `X-Supported-Capabilities` | `ContentCapabilityRegistryG37.java:103-105` | transport names, comment: "invented" |
| Query/body fields `clientPlatform`, `clientVersion`, `supportedCapabilities` | `ContentCapabilityRegistryG37.java:106-108` | request field names |
| Response fields `compatibility`, `supported`, `source`, `missingCapabilities` | `ContentCapabilityRegistryG37.java:111-114` | response keys (G43 adds `confirmed`; G42 and G44 may return `supported:null`) |
| `source` values `UNDECLARED`, `MALFORMED`, `DECLARED` | `...G37.java:116-118` | enum |
| Limits: 128 capabilities, 64-char fields (G37); 64 entries (G38); 2048-char CSV (G39); 64-char items (G42) | various | limits |
| Permission strings `business:ug:audit:list`, `business:ug:audit:review` | `UgAuditAdminG48Controller.java:23-24` | invented, G48 |
| Ledger key prefix `UGHELP:`, event type `14` | `PlayHelpPolicyG39.java:10,12` | points ledger |
| Rule version `ug07-v1` | `RunScoreDetailG40Service.java:19` | invented |
| Node config keys `hintLadder.skip.allowed` | `PlayHelpSkipG41Service.java:39-41` | invented |
| Config key `clueTransform.mode` ∈ STANDARD/MIRROR/REVERSE | `ClueTransformG46Support.java:25-31` | invented |
| Receipt states APPLIED/FAILED/PENDING/UNKNOWN, code 520 | `PlayActionReceiptG45Service.java:244-250` | "owner to ratify" (`:242`) |
| Check version `g47-fieldcheck-1`, issue kinds MISSING/INVALID/UNSUPPORTED/NOT_CONFIGURABLE/CONFLICT/OTHER | `AuthorConfigNamesG47.java` | "INVENTED" |
| Contract version `g52-publish-next-1`, step/action vocab | `PublishNextStepG52.java:21-48` | G52 |

## Observations (facts)

- iOS (`origin/wip/wave5-build`) contains none of the 14 strings and none of the three headers or `supportedCapabilities` (`git grep` over all files except `*.md`; only unrelated hits for the word "capabilities"). So every capability is currently "UNDECLARED" for real traffic, which the server treats as non-blocking everywhere.
- Capabilities that gate nothing at runtime: rows 1, 4-8 (registry only), 11 and 14 (no caller).
