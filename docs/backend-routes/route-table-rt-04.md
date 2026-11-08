# Route table rt-04 (groups G37-G48 + G52 publish status): UG gameplay

STATIC CONTRACT. Derived by reading code on `origin/claude/be-v2-fixes` (commit 537e43c7). Not run against a live server. Nothing here was invented; unknowns are marked UNKNOWN.
iOS repo checked: `origin/wip/wave5-build` (commit 3f4f6053), `git grep` over all `*.swift`.

## Conventions that apply to every row (verified)

- Envelope: `AjaxResult` = JSON object `{ "code": int, "msg": string, "data": any }` (`AjaxResult.java`, `HttpStatus.SUCCESS=200`, `HttpStatus.ERROR=500`). Success default msg `操作成功`. HTTP transport status for business errors: UNKNOWN (controllers return `AjaxResult` with the code in the body; whether a filter maps the body code to the HTTP status was not traced).
- `ServiceException(msg, code)` thrown from a service is turned into `{code, msg}` by `GlobalExceptionHandler.handleServiceException` (GlobalExceptionHandler.java:130-141); message passes through `userSafeMessage`, so the wire `msg` can differ from the Java string (not traced).
- Auth: `SecurityConfig` ends with `.anyRequest().authenticated()` (SecurityConfig.java:166). None of the routes below is in the permit-all list (checked lines 117-165), so a token is REQUIRED on every route. **Guest: not allowed on any route.** Where the controller reads the member it uses `BaseController.getAppUserId()` (BaseController.java:222); the token is the only source of member id.
- Idempotency key where present is always `requestId` in the body/form. No route reads an `Idempotency-Key` header.
- Header requirements: none mandatory. Only G37 reads optional capability headers `X-Client-Platform`, `X-Client-Version`, `X-Supported-Capabilities`.
- iOS caller: for **every** route in this table `git grep` finds no Swift reference (patterns: the path, `supportedCapabilities`, `X-Supported-Capabilities`, `X-Client-Platform`, every capability string). So iOS caller = NONE for all rows, except the G37 advice row, which decorates `GET api/play/nodes` that iOS does call (see row G37-3).
- Rate limit shown where `@RateLimiter(time=10s, count=N, MEMBER)` is present. Rate-limit rejection response shape: UNKNOWN.
- "Examples" are SYNTHETIC, derived from the code; ids and text are made up.

## Summary

| # | Group | Method | Path | Auth | Encoding | iOS caller |
|---|---|---|---|---|---|---|
| G37-1 | G37 | GET | /api/play/compatibility | token | query/headers | NONE |
| G37-2 | G37 | POST | /api/play/compatibility | token | JSON body + query ids | NONE |
| G37-3 | G37 | (advice on) GET | /api/play/nodes | token | query/headers | Core/PlayService.swift:29 (route only, no capability sent) |
| G38-1 | G38 | GET | /api/play/help | token | query | NONE |
| G39-1 | G39 | GET | /api/play/help/quota | token | query | NONE |
| G39-2 | G39 | POST | /api/play/help/use | token | JSON | NONE |
| G40-1 | G40 | GET | /api/play/run-score-detail | token | query | NONE |
| G41-1 | G41 | POST | /api/play/help/skip | token | JSON | NONE |
| G41-2 | G41 | GET | /api/play/help/skip/receipt | token | query | NONE |
| G42-1 | G42 | POST | /api/play/hangman/state | token | JSON | NONE |
| G42-2 | G42 | POST | /api/play/hangman/submit | token | JSON | NONE |
| G43 | G43 | none | no controller (helper `QaOptionMediaG43`) | - | - | NONE |
| G44-1 | G44 | GET | /api/play/accusation | token | query | NONE |
| G44-2 | G44 | POST | /api/play/accusation/confirm | token | form/query (no @RequestBody) | NONE |
| G44-3 | G44 | GET | /api/play/accusation/receipt | token | query | NONE |
| G45-1 | G45 | GET | /api/play/action-receipt/state | token | query | NONE |
| G46 | G46 | none | no controller (`ClueTransformG46Support.apply` inside `/api/play/nodes`) | - | - | see G46 note |
| G47-1 | G47 | GET | /api/topic/publish-check/fields-g47 | token + owner | query | NONE |
| G47-2 | G47 | GET | /api/topic/author-config/hints-g47 | token + owner | query | NONE |
| G47-3 | G47 | POST | /api/topic/author-config/hints/validate-g47 | token | JSON | NONE |
| G47-4 | G47 | GET | /api/topic/publish-status-g47 | token + owner | query | NONE |
| G52-1 | G52 | GET | /api/topic/publish-result-g52 | token + owner | query | NONE |
| G52-2 | G52 | GET | /api/topic/my-projects-status-g52 | token + owner | query | NONE |
| G48-1 | G48 | GET | /business/ug-audit/topic/{topicId}/config | admin token + perm | path | NONE (admin web, not iOS) |
| G48-2 | G48 | GET | /business/ug-audit/run/{runId}/quota | admin token + perm | path | NONE |
| G48-3 | G48 | GET | /business/ug-audit/run/{runId}/detail | admin token + perm | path | NONE |

Out of scope, noted only: `ApiTopicTemplateAdoptionG49Controller` (G49) exists; no controller exists for G50 (`LocationTodoLogicG50` is logic only).

Shared capability-compat object (all routes that return `compatibility`): `{ "supported": bool|null, "source": "UNDECLARED"|"DECLARED"|"MALFORMED", "missingCapabilities": [string] }`. Differences per route are listed in each row (G38/G42/G44 can return `supported:null`; G37/G39/G41/G46 return a boolean; G43 uses a different shape `{supported, confirmed, missingCapabilities}`).

---

## G37 capability negotiation

### G37-1 GET /api/play/compatibility
- Controller: `chengyinhub-admin/.../web/controller/api/ApiPlayCompatibilityG37Controller.java:18` (class mapping), `:23-28` (GET)
- Auth: token; no member → `AjaxResult.error("请先登录")` (code 500, msg 请先登录) (`:25`).
- Params (query or headers): `activityId` Long optional; `topicId` Long optional; client declaration read by `PlayCompatibilityAdviceG37.fromRequest` (`PlayCompatibilityAdviceG37.java:113-119`): header `X-Client-Platform` else query `clientPlatform`; header `X-Client-Version` else query `clientVersion`; header `X-Supported-Capabilities` else query `supportedCapabilities` (comma list, split on `,`).
- Success `data` (`CapabilityCompatibilityServiceG37.evaluate`, `web/service/play/cap/CapabilityCompatibilityServiceG37.java:19-33`): `{ supported: bool, source: string, missingCapabilities: [string] }`. `supported=false` only when source=DECLARED and a required capability is absent. Required set comes from `ContentCapabilityRequirementsProviderG37`; the only implementation (`DefaultContentCapabilityRequirementsProviderG37`) returns an empty set, so today `supported` is always true.
- Parsing (`ClientCapabilityDeclarationG37.parse`, `:65-82`): all three absent → UNDECLARED; missing platform/version/caps while any other present, >64-char field, >128 caps, or a cap not matching `^[a-z][A-Za-z0-9]*(\.[A-Za-z][A-Za-z0-9]*)+@[1-9][0-9]{0,3}$` → MALFORMED; else DECLARED.
- Errors: code 500 "请先登录" (above). No other error path.
- Idempotency: read-only. Headers: optional three above.
- Capability strings: reads the client list; returns `missingCapabilities` (none required at present). Registry constants in `ContentCapabilityRegistryG37.java:33-40`.
- iOS caller: NONE.
- Example request: `GET /api/play/compatibility?activityId=21&topicId=71` with headers `X-Client-Platform: ios`, `X-Client-Version: 1.0.0`, `X-Supported-Capabilities: hint.ladder@1,node.scan@1`
- Example response: `{"code":200,"msg":"操作成功","data":{"supported":true,"source":"DECLARED","missingCapabilities":[]}}`

### G37-2 POST /api/play/compatibility
- Controller: same file `:30-35`; `fromBody` `:37-45`.
- Auth: token (`:32`), error as above.
- Encoding: JSON body `@RequestBody(required=false) Map`; `activityId`, `topicId` are plain method params (query/form, NOT body).
- Body fields: `clientPlatform` string, `clientVersion` string, `supportedCapabilities` array of strings. Wrong JSON types → MALFORMED; null body → UNDECLARED.
- Success / errors / idempotency / capability: as G37-1.
- iOS caller: NONE.
- Example: `POST /api/play/compatibility?topicId=71` body `{"clientPlatform":"ios","clientVersion":"1.0.0","supportedCapabilities":["hint.ladder@1"]}` → `{"code":200,"msg":"操作成功","data":{"supported":true,"source":"DECLARED","missingCapabilities":[]}}`

### G37-3 compatibility appended to GET /api/play/nodes (not its own route)
- Advice: `web/controller/api/PlayCompatibilityAdviceG37.java:28` (`@RestControllerAdvice(assignableTypes = ApiPlayProgressController.class)`), `supports` `:33` matches method name `nodes`; the route itself is `ApiPlayProgressController.java:39-42` (`@GetMapping("/nodes")`, params `activityId`, `topicId`, owned by another group).
- Effect: puts `compatibility{supported,source,missingCapabilities}` on the AjaxResult top level AND into `data` if `data` is a mutable Map (`:48-53`); any RuntimeException is swallowed.
- Client declaration read from the same headers/query as G37-1.
- iOS caller: the route is called at `Core/PlayService.swift:29`, `Core/PlayExperienceService.swift:52`, route enum `Core/PlayReadRoute.swift:10`. iOS sends NO capability header or query (no match for any of the names), so `source` will be UNDECLARED. iOS does not read `compatibility` (no Swift match for the key in play code; not exhaustively checked inside decoders: UNKNOWN).
- Example response fragment: `{"code":200,"msg":"操作成功","compatibility":{"supported":true,"source":"UNDECLARED","missingCapabilities":[]},"data":{"nodes":[],"compatibility":{"supported":true,"source":"UNDECLARED","missingCapabilities":[]}}}`

---

## G38 help ladder read

### G38-1 GET /api/play/help
- Controller: `ApiPlayHelpG38Controller.java:12-14`, `@GetMapping("/help")` `:19`, handler `:20-23`. RateLimiter 120/10s `:18`.
- Auth: token; `getAppUserId()` called directly (`:22`); unauthenticated behaviour beyond the security filter: UNKNOWN.
- Params (query): `runId` String required (`@RequestParam`), `nodeId` Long required, `supportedCapabilities` String optional (comma list, format `^[A-Za-z][A-Za-z0-9.]{0,63}@[0-9]{1,4}$`, max 64 entries).
- Success `data` (`PlayHelpViewG38.view`, `support/PlayHelpViewG38.java:68`; compatibility at `:33`, built by `PlayHelpG38ServiceImpl.help` `:23`):
  `{ runId:string, nodeId:long, enabled:bool, compatibility:{supported:bool|null,source,missingCapabilities:[string]}, legacyFallback:bool, hintFreeUsesPerRun:int|null, remainingFreeUses:int|null, layers:[{level:int,type:string,usable:bool,unlocked:bool,free:bool,costPoints:int,pricePoints:int,reason:string|null}] }`. When `enabled=false` (no layer rows for the node): `legacyFallback:true`, the two counters null, `layers:[]`. `type` ∈ TEXT/IMAGE/LETTER/DIGIT/ANSWER or `UNKNOWN`. `reason` ∈ `HELP_TYPE_UNSUPPORTED`, `PREVIOUS_LAYER_REQUIRED`, `POINTS_INSUFFICIENT`, null. No hint content is returned.
- Errors (ServiceException): `{code:401,msg:"PLAY_HELP_BAD_REQUEST"}` memberId<=0; `{code:400,msg:"PLAY_HELP_BAD_REQUEST"}` blank/>64-char runId or bad nodeId; `{code:404,msg:"PLAY_HELP_RUN_NOT_FOUND"}` non-numeric runId, unknown run or not the caller's run. (`PlayHelpG38ServiceImpl.java:24-32`)
- Idempotency: read-only. Headers: none.
- Capability: reads `hint.ladder@1` (required only when `enabled`); returns it in `missingCapabilities` (`PlayHelpViewG38.java:14`).
- Data source: tables `play_help_run_g39`, `play_help_layer_g39`, `play_help_unlock_g39`, `ums_member.point` (`PlayHelpG38Mapper.java`), i.e. same schema as G39. `topicId`/`contentRevision` are constant 0 in the run row.
- Note: iOS contract doc field names `sessionId`/`idempotencyKey` differ from `runId`/`requestId` (fix report fx-01 #14, unchanged).
- iOS caller: NONE.
- Example: `GET /api/play/help?runId=9001&nodeId=55&supportedCapabilities=hint.ladder@1` →
  `{"code":200,"msg":"操作成功","data":{"runId":"9001","nodeId":55,"enabled":true,"compatibility":{"supported":true,"source":"DECLARED","missingCapabilities":[]},"legacyFallback":false,"hintFreeUsesPerRun":2,"remainingFreeUses":1,"layers":[{"level":1,"type":"TEXT","usable":true,"unlocked":true,"free":true,"costPoints":0,"pricePoints":10,"reason":null},{"level":2,"type":"IMAGE","usable":true,"unlocked":false,"free":true,"costPoints":0,"pricePoints":20,"reason":null}]}}`

## G39 help quota + use

### G39-1 GET /api/play/help/quota
- Controller: `ApiPlayHelpG39Controller.java:18-19` (class), `@GetMapping("/quota")` `:31`, handler `:32-38`. RateLimiter 120/10s `:29`. Route was moved off `/help` to avoid a duplicate mapping with G38 (comment `:30`).
- Auth: token; `currentMemberId()` null → `{code:401,msg:"未登录"}` (`:35`).
- Params (query): `runId` Long required, `nodeId` Long required, `supportedCapabilities` String optional (comma list, truncated to 2048 chars). Missing runId/nodeId → `{code:400,msg:"参数错误"}` (`:33`).
- Success `data` (`PlayHelpG39Service.view`, `service/g39/PlayHelpG39Service.java:35-67`): `{ runId:long, nodeId:long, compatibility:{supported:bool,source:"UNDECLARED"|"DECLARED",missingCapabilities:[string]}, enabled:bool, layers:[{level:int,type:string,unlocked:bool,usable:bool,free:bool,costPoints:int,reason:string|null}], freeUsesPerRun:int, remainingFreeUses:int }`. When no frozen ladder: `enabled:false, layers:[], remainingFreeUses:0` and `freeUsesPerRun` is ABSENT. Differences from G38: here `supported` is never null (undeclared → true), no `legacyFallback`, no `pricePoints`, `runId`/`nodeId` are numbers.
- Errors: 400 参数错误, 401 未登录 (above). No other.
- Idempotency: read-only. Headers none.
- Capability: `hint.ladder@1` (`PlayHelpPolicyG39.java:8`), used by `PlayHelpG39Service.compatibility` `:166-174`.
- iOS caller: NONE.
- Example: `GET /api/play/help/quota?runId=9001&nodeId=55` → `{"code":200,"msg":"操作成功","data":{"runId":9001,"nodeId":55,"compatibility":{"supported":true,"source":"UNDECLARED","missingCapabilities":[]},"enabled":true,"layers":[{"level":1,"type":"TEXT","unlocked":false,"usable":true,"free":true,"costPoints":10,"reason":null}],"freeUsesPerRun":2,"remainingFreeUses":2}}`

### G39-2 POST /api/play/help/use
- Controller: `ApiPlayHelpG39Controller.java:40-52` (`@PostMapping("/use")` `:41`). RateLimiter 60/10s.
- Auth: token; null member → `{code:401,msg:"未登录"}`.
- Encoding: JSON `@RequestBody Map`. Fields: `runId` number required, `nodeId` number required, `level` number (int ≥1) required, `action` string required and must equal `"HELP"`, `requestId` string required, regex `[A-Za-z0-9_-]{8,64}` (`PlayHelpPolicyG39.validRequestId`). Numbers sent as JSON strings are ignored by `num()` and become null → 400.
- Success `data` (`PlayHelpG39Service.result` `:146-153`): `{ runId:long, nodeId:long, level:int, type:string, content:string, applied:bool, alreadyUnlocked:bool, chargedPoints:int, balanceAfter:long|null }`. Content is returned only here.
- Errors, shape `{code:<c>, msg:<text>, data:{reasonCode:<r>}}` (`:49-50`; `Rejected` at `PlayHelpG39Service.java:21`): 400 HELP_BAD_REQUEST 参数错误; 404 HELP_NOT_ENABLED (no run row); 409 RUN_NOT_ACTIVE; 409 REQUEST_CONFLICT (same requestId, different fingerprint); 404 HELP_LAYER_NOT_FOUND; 422 HELP_TYPE_UNSUPPORTED; 409 PREVIOUS_LAYER_REQUIRED; 409 POINTS_INSUFFICIENT; 409 FREE_QUOTA_EXHAUSTED; 500 HELP_LEDGER_FAILED. All inside one transaction that rolls back.
- Idempotency: `requestId` unique per (member, requestId); same request + same (run,node,level,action) returns the stored result with `alreadyUnlocked:true, applied:false`. Header none.
- Money: spends `ums_member.point` via `members.deductPoints` and writes a points-ledger row (event type 14, key `UGHELP:{run}:{node}:{level}`). Code only reported, not changed.
- Capability: none read on this route.
- iOS caller: NONE.
- Example: `POST /api/play/help/use` `{"runId":9001,"nodeId":55,"level":1,"action":"HELP","requestId":"req-0001-abcdef"}` → `{"code":200,"msg":"操作成功","data":{"runId":9001,"nodeId":55,"level":1,"type":"TEXT","content":"看门牌号","applied":true,"alreadyUnlocked":false,"chargedPoints":0,"balanceAfter":null}}`; insufficient points → `{"code":409,"msg":"积分不足，本层未解锁","data":{"reasonCode":"POINTS_INSUFFICIENT"}}`

## G40 score detail

### G40-1 GET /api/play/run-score-detail
- Controller: `ApiRunScoreDetailG40Controller.java:13-14`, `@GetMapping("/run-score-detail")` `:17`, handler `:18-24`. No RateLimiter.
- Auth: token; `getAppUserId()` called unguarded (`:19`).
- Params (query): `run_id` String required (snake_case!), non-blank, ≤64 chars.
- Success `data` (`RunScoreDetailG40Service.summarize` `service/scoreug40/RunScoreDetailG40Service.java:83-129`): `{ detailAvailable:bool, baseScore:long|null, awardedBonus:long|null, helpDeduction:long|null, skipDeduction:long|null, netScore:long|null, reconciled:bool, assistedCompletion:bool, ruleVersion:string|null, remainingFreeUses:null, events:[{type:"BASE"|"BONUS"|"HINT"|"SKIP",nodeId:long|null,delta:long,completionMode:"SOLVED"|"REVEALED"|"SKIPPED"|null,at:string|null}], nodes:[{nodeId:long,nodeScore:long,completionMode:string|null}] }`. Unknown/foreign run → 200 with `detailAvailable:false` and null totals. `remainingFreeUses` is always null.
- Errors: `{code:400, msg:"run_id required", errorCode:"MISSING_PARAM"}` (`RunScoreDetailG40Service.java:75`; controller `:20-23`; `Refusal` `:24` carries code + `errorCode` at top level).
- Idempotency: read only (the ledger write `record(...)` is server-side, not a route). Headers none.
- Capability: none.
- iOS caller: NONE.
- Example: `GET /api/play/run-score-detail?run_id=9001` → `{"code":200,"msg":"操作成功","data":{"detailAvailable":true,"baseScore":100,"awardedBonus":10,"helpDeduction":5,"skipDeduction":0,"netScore":105,"reconciled":true,"assistedCompletion":true,"ruleVersion":"ug07-v1","remainingFreeUses":null,"events":[{"type":"BASE","nodeId":55,"delta":100,"completionMode":"SOLVED","at":"2026-11-08 10:00:00"}],"nodes":[{"nodeId":55,"nodeScore":100,"completionMode":"SOLVED"}]}}`

## G41 skip

### G41-1 POST /api/play/help/skip
- Controller: `ApiPlayHelpSkipG41Controller.java:21-22`, `@PostMapping("/skip")` `:28`, handler `:29-38`. RateLimiter 60/10s.
- Auth: token; service 401 UNAUTHENTICATED if member null/<=0.
- Encoding: JSON. Fields: `runId` number, `nodeId` number, `requestId` string (36-char canonical UUID, `validRequestId` `PlayHelpSkipG41Service.java:69-72`; comparison is case-insensitive), `supportedCapabilities` array of strings (non-strings dropped; non-list → treated as null = undeclared).
- Success `data` (`PlayHelpSkipG41Service.skip` `:104-153`): `{ runId, nodeId, requestId, completionMode:"SKIPPED", assisted:true, nodeScore:0, skipDeduction:0, solved:false, arrived:false, rewardGranted:false, applied:bool, alreadySkipped:bool, capability:{supported:bool,missingCapabilities:[string],source:"UNDECLARED"|"DECLARED"} }`. Replay: `applied:false, alreadySkipped:true`. Different requestId on an already-skipped node returns the original fact with the caller's requestId.
- Errors (shape `{code, msg, data:{reasonCode}}`): 401 UNAUTHENTICATED; 400 BAD_REQUEST; 403 RUN_FORBIDDEN; 409 RUN_NOT_RUNNING; 404 NODE_NOT_IN_RUN; 409 SKIP_NOT_ENABLED (node's frozen `hintLadder.skip.allowed` not true); 403 NODE_NOT_OPEN; 409 NODE_ALREADY_COMPLETED; 409 REQUEST_ID_REUSED; 500 SERIALIZE / LEDGER_MISSING / RECEIPT_UNREADABLE.
- Idempotency: `requestId` in body, payload hash `SKIP:{run}:{node}`. Header none.
- Capability: reads/returns `help.skip@1` (`PlayHelpSkipG41Service.java:37`, `negotiate :87-95`). Note: unlike others, `supported` here is false (not null) when undeclared, `source:"UNDECLARED"`.
- iOS caller: NONE.
- Example: `POST /api/play/help/skip` `{"runId":9001,"nodeId":55,"requestId":"3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e","supportedCapabilities":["help.skip@1"]}` → `{"code":200,"msg":"操作成功","data":{"runId":9001,"nodeId":55,"requestId":"3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e","completionMode":"SKIPPED","assisted":true,"nodeScore":0,"skipDeduction":0,"solved":false,"arrived":false,"rewardGranted":false,"applied":true,"alreadySkipped":false,"capability":{"supported":true,"missingCapabilities":[],"source":"DECLARED"}}}`

### G41-2 GET /api/play/help/skip/receipt
- Controller: same file `:41-50` (`@GetMapping("/skip/receipt")` `:42`). RateLimiter 120/10s.
- Params (query): `runId` Long, `nodeId` Long, `requestId` String (UUID). Bad → 400 BAD_REQUEST via `data.reasonCode`.
- Success `data` (`receipt :156-170`): if recorded → the stored skip body (as G41-1 with `alreadySkipped:true, applied:false`); else `{ outcome:"PENDING", runId, nodeId, requestId }`.
- Errors: 401 UNAUTHENTICATED, 400 BAD_REQUEST, 409 REQUEST_ID_REUSED (hash mismatch), 500 RECEIPT_UNREADABLE. Read-only.
- Capability: none (stored body carries the original `capability`).
- iOS caller: NONE.
- Example: `GET /api/play/help/skip/receipt?runId=9001&nodeId=55&requestId=3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e` → `{"code":200,"msg":"操作成功","data":{"outcome":"PENDING","runId":9001,"nodeId":55,"requestId":"3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e"}}`

## G42 hangman

### G42-1 POST /api/play/hangman/state
- Controller: `ApiHangmanG42Controller.java:26-27`, `@PostMapping("/state")` `:31`, handler `:32-38`. RateLimiter 120/10s.
- Auth: token; `member()` returns 0 on failure and the service rejects with 401 UNAUTHENTICATED.
- Encoding: JSON `@RequestBody(required=false)`; null body → `{code:500,msg:"参数有误"}` (`error()`).
- Fields: `topicId` required `^[A-Za-z0-9_.:\-]{1,64}$`; `nodeId` required same; `activityId` optional (empty = none) same pattern; `supportedCapabilities` array of strings ≤64 chars each (non-list or bad element → MALFORMED). Values are read via `String.valueOf(...).trim()`, so numbers or strings both work.
- Success: body `{ code:200, msg, data:{ action:"SUBMIT_HANGMAN", hangman:{ length:int, blankCount:int, caseSensitive:bool, solved:bool, exhausted:bool, wrongCount:int, maxWrong:int(only if configured), slots:[{i:int,kind:"SEP"|"BLANK"|"FILLED"|"GIVEN",ch:string|null}], display:string, answerText:string(only when solved) }, compatibility:{supported:bool|null,source,missingCapabilities:[string]} } }` (`HangmanG42Service.state :68-81`, `HangmanLogicG42.publicProjection :134`, `compatibility :228`). `data` is set via `ok.put("data", …)`.
- Errors: `{code:<http>, msg:<text>, errorCode:<string>[, slot:int]}` (`fail :228-233`): 400 MISSING_PARAM; 401 UNAUTHENTICATED; 403 NODE_NOT_OPEN; 404 HANGMAN_NOT_AVAILABLE; 500 HANGMAN_CONFIG_CORRUPT / HANGMAN_STATE_CORRUPT; 503 HANGMAN_NODE_GATE_UNWIRED.
- Idempotency: read-only. Headers none.
- Capability: `gameplay.hangman@1` (`HangmanLogicG42.java:20`).
- iOS caller: NONE.
- Example: `POST /api/play/hangman/state` `{"activityId":"21","topicId":"71","nodeId":"55","supportedCapabilities":["gameplay.hangman@1"]}` → `{"code":200,"msg":"操作成功","data":{"action":"SUBMIT_HANGMAN","hangman":{"length":4,"blankCount":2,"caseSensitive":false,"solved":false,"exhausted":false,"wrongCount":0,"maxWrong":10,"slots":[{"i":0,"kind":"GIVEN","ch":null},{"i":1,"kind":"BLANK","ch":null}],"display":"____"},"compatibility":{"supported":true,"source":"DECLARED","missingCapabilities":[]}}}`
  (note: for GIVEN slots `ch` is null unless filled; derived from `ch = shown ? filled : null`.)

### G42-2 POST /api/play/hangman/submit
- Controller: same file `:40-48`. RateLimiter 120/10s.
- Fields: as state plus `requestId` required `^[A-Za-z0-9_.:\-]{8,64}$`, and `payload` object: either `{ "slots": { "<index>": "<one char>" } }` (keys parse to int) or `{ "input": "<string>" }`; both or neither → error. Bad payload type → `{code:400,msg:"载荷无效",errorCode:"HANGMAN_PAYLOAD_INVALID"}` (`:44`).
- Success `data`: `{ action:"SUBMIT_HANGMAN", requestId, verdict:"CORRECT"|"WRONG", hangman:{…as above…}, compatibility:{…} }` (`HangmanG42Service.submit :84-128`). `compatibility` is added after the receipt is stored, so a replay returns the ORIGINAL stored body (without a fresh `compatibility` key).
- Errors: as state, plus 400 REQUEST_ID_INVALID; 409 REQUEST_ID_REUSED (same requestId, different payload hash); 409 HANGMAN_EXHAUSTED; 400 HANGMAN_PAYLOAD_AMBIGUOUS / HANGMAN_PAYLOAD_REQUIRED / HANGMAN_SLOT_OUT_OF_RANGE / HANGMAN_SLOT_LOCKED / HANGMAN_SLOT_VALUE_INVALID / HANGMAN_SLOT_MISSING (with `slot`); 500 RECEIPT_CORRUPT.
- Idempotency: `requestId` in body; receipt table keyed (member, requestId). Header none.
- Capability: `gameplay.hangman@1`.
- iOS caller: NONE.
- Example: `POST /api/play/hangman/submit` `{"activityId":"21","topicId":"71","nodeId":"55","requestId":"hm-req-0001","payload":{"slots":{"1":"a","3":"e"}}}` → `{"code":200,"msg":"操作成功","data":{"action":"SUBMIT_HANGMAN","requestId":"hm-req-0001","verdict":"CORRECT","hangman":{"length":4,"blankCount":2,"caseSensitive":false,"solved":true,"exhausted":false,"wrongCount":0,"maxWrong":10,"slots":[],"display":"cafe","answerText":"cafe"},"compatibility":{"supported":null,"source":"UNDECLARED","missingCapabilities":[]}}}` (`slots` shortened for the example).

## G43 image options
- No HTTP route and no controller. Logic only: `QaOptionMediaG43` (`service/support/QaOptionMediaG43.java`): options may carry `img`, `alt`, flag `imgMissing`; `validateOptionMedia` is called from `AdvancedGameConfigValidator.java:1259`; `copyOptionMedia` is called from `AdvancedGamePublicProjection.java:362`, i.e. the image fields appear inside the existing node payload `advancedConfigJson` served by the play routes owned by other groups. `negotiate(declared, contentHasOptionImages)` (`:107`) returns `{missingCapabilities:[string], supported:bool, confirmed:bool}` but has NO production caller (grep shows only its own file). So `qa.optionImage@1` is defined and never evaluated on any route today.
- iOS caller: NONE.

## G44 accusation

### G44-1 GET /api/play/accusation
- Controller: `ApiAccusationG44Controller.java:12-13`, `@GetMapping` `:19`, handler `:20-23`. RateLimiter 120/10s.
- Auth: token; `currentMemberId()` returns 0 on failure → service 401 `{code:401,msg:"请先登录"}`.
- Params (query): `activityId` Long optional (null → 0), `topicId` Long required, `nodeId` Long required, `supportedCapabilities` String optional (comma list, split on `\s*,\s*`).
- Success `data` (`AccusationServiceG44.view :59-74`): `{ compatibility:{supported:bool|null,source:"UNDECLARED"|"DECLARED",missingCapabilities:[string]}, accusation:{ enabled:bool, [if configured:] corkboardImage?, introScreens?, earlyAccuseAllowed:bool, attemptLimit:int, suspects:[{id:string,name:string,avatar?,identity?,testimony:[{key,text}]}] }, attemptsUsed:int, closure:string|null, closureScreen?:{screen?:…} }`. Testimony is limited to clues the member has obtained. Answer is never returned. `closure` ∈ NORMAL_CLOSURE / EARLY_CLOSURE / ACCUSATION_FAILED / null.
- Errors: 400 `参数无效` (topic/node null); 401 请先登录.
- Idempotency: read-only (free, any number of times). Headers none.
- Capability: reads `play.accusation@1` and `play.earlyClosure@1` (`AccusationJudgeG44.java:18-19`, used in `AccusationServiceG44.capability :45-56`); undeclared → `supported:null`.
- iOS caller: NONE.
- Example: `GET /api/play/accusation?activityId=21&topicId=71&nodeId=55&supportedCapabilities=play.accusation@1,play.earlyClosure@1` → `{"code":200,"msg":"操作成功","data":{"compatibility":{"supported":true,"source":"DECLARED","missingCapabilities":[]},"accusation":{"enabled":true,"earlyAccuseAllowed":false,"attemptLimit":3,"suspects":[{"id":"s1","name":"甲","testimony":[{"key":"t1","text":"我在门口"}]}]},"attemptsUsed":0,"closure":null}}`

### G44-2 POST /api/play/accusation/confirm
- Controller: same file `:26-30`, RateLimiter 30/10s. Comment `:25`: "Form encoded".
- Encoding: NO `@RequestBody`, so Spring binds query string or `application/x-www-form-urlencoded`; a JSON body would NOT bind (all params would be null → 400).
- Params: `activityId` Long optional, `topicId` Long required, `nodeId` Long required, `suspectId` String required (≤64), `requestId` String required lower-case UUID (`OriginalRequestLedgerG30Service.isLowerUuid`), `supportedCapabilities` String optional (comma list).
- Success `data` (`AccusationServiceG44.body :119-133`): `{ requestId, compatibility, outcome:string, chanceCharged:bool, attemptsUsed:int, attemptsRemaining:int, closed:bool, refuseReason?:string, rewardEligible:bool, closureScreen?:{screen?:…} }`. `outcome` ∈ NORMAL_CLOSURE / EARLY_CLOSURE / ACCUSATION_FAILED / WRONG_CAN_RETRY / REFUSED. `refuseReason` ∈ ACCUSATION_NOT_CONFIGURED / UNKNOWN_SUSPECT / EARLY_ACCUSATION_NOT_ALLOWED / ALREADY_CLOSED / NO_CHANCE_LEFT. Replay adds `replayed:true`; in-flight twin returns `{requestId,outcome:"PENDING",replayed:true}`. Correct suspect / recordAs never returned.
- Errors: 400 `requestId无效`; 400 `参数无效`; 401 请先登录; 409 `请求号对应的内容不一致` (same requestId, different content). Business refusals are 200 with `outcome:"REFUSED"`.
- Idempotency: `requestId` (form field), payload hash over activity/topic/node/suspect. Header none.
- Money: takes at most one "chance" (game state, not currency); no points/reward payout, only `rewardEligible`.
- Capability: as G44-1 (echoed in `compatibility`).
- iOS caller: NONE.
- Example: `POST /api/play/accusation/confirm` `Content-Type: application/x-www-form-urlencoded` body `activityId=21&topicId=71&nodeId=55&suspectId=s1&requestId=3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e` → `{"code":200,"msg":"操作成功","data":{"requestId":"3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e","compatibility":{"supported":null,"source":"UNDECLARED","missingCapabilities":[]},"outcome":"WRONG_CAN_RETRY","chanceCharged":true,"attemptsUsed":1,"attemptsRemaining":2,"closed":false,"rewardEligible":false}}`

### G44-3 GET /api/play/accusation/receipt
- Controller: same file `:32-36`, RateLimiter 120/10s.
- Params (query): `requestId` String required lower-case UUID.
- Success `data` (`receipt :156-162`): stored confirm body plus `replayed:true`; `{requestId,outcome:"PENDING",replayed:true}` if not DONE; `{requestId,outcome:"NOT_FOUND"}` if absent.
- Errors: 400 `requestId无效`; 401 请先登录. Read-only.
- Capability: none new. iOS caller: NONE.
- Example: `GET /api/play/accusation/receipt?requestId=3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e` → `{"code":200,"msg":"操作成功","data":{"requestId":"3f2b8c1e-4d5a-4b6c-8d7e-9f0a1b2c3d4e","outcome":"NOT_FOUND"}}`

## G45 action receipt state

### G45-1 GET /api/play/action-receipt/state
- Controller: `ApiPlayReceiptG45Controller.java:16-17`, `@GetMapping("/action-receipt/state")` `:22`, handler `:23-27`. RateLimiter 120/10s.
- Auth: token; id lookup failure → null → body error `请先登录`.
- Params (query): `activityId` String required (parsed as Long), `nodeId` String (required when `routeActionId` used; optional for `requestId`), exactly ONE of `routeActionId` / `requestId` (both or neither → error). Id pattern `[A-Za-z0-9:_-]{1,80}`.
- Response is NOT under `data`: fields are top-level on the AjaxResult (`PlayActionReceiptG45Service.query :41-…`, `terminal :79`, `unsettled :68`).
  - Terminal (code 200): `{ code:200, msg:"操作成功", receiptState:"APPLIED"|"FAILED", intentTerminal:true, newActionIdRequired:bool(true iff FAILED), refreshRequired:false, retryable:false, queryAgain:false, action:string, reasonCode?:string, original?:object }`.
  - Unsettled (code **520**, msg `原命令结果待确认，请稍后查询`): `{ receiptState:"PENDING"|"UNKNOWN", intentTerminal:false, newActionIdRequired:false, refreshRequired:false, retryable:false, queryAgain:true }`.
  - Errors (code 500, plain msg): `请先登录`; `必须且只能提供 routeActionId 或 requestId 之一`; `必须提供 nodeId`; `动作标识无效`; `活动标识无效`; `节点标识无效`.
- Idempotency: read-only; "requestId" here is the raw id used by help/hangman/accuse/skip commands. Receipt must belong to the caller's PLAYER row and (if given) the node. `routeActionId` only matches `PLAY_BASIC_*` actions.
- Capability: none. iOS caller: NONE (iOS uses other receipt routes, e.g. `api/play/city-orientation/receipt`, not this one).
- Example: `GET /api/play/action-receipt/state?activityId=21&nodeId=55&requestId=hm-req-0001` → `{"code":520,"msg":"原命令结果待确认，请稍后查询","receiptState":"UNKNOWN","intentTerminal":false,"newActionIdRequired":false,"refreshRequired":false,"retryable":false,"queryAgain":true}`

## G46 clue transform
- No HTTP route and no controller. `ClueTransformG46Support.apply(view, advancedConfigJson)` (`service/support/ClueTransformG46Support.java:97`) is called at `chengyinhub-admin/.../web/service/play/PlayNodeQueryApplication.java:391` inside the node projection, so it affects `GET /api/play/nodes` (owned elsewhere). Effect for mode MIRROR or REVERSE: the served `question` is replaced by `transformQuestion(question, mode)` (only REVERSE changes the text; MIRROR leaves the text untouched: it is a client-side flip, `transformQuestion` `ClueTransformG46Support.java:89-91`) and a key `clueTransform:{mode}` is added to the node view; STANDARD/absent changes nothing.
- Capability `clue.transform@1` (`:27`); `compatibility(declared)` (`:113`) exists, returns `{supported,missingCapabilities}` (no `source`), and has NO production caller. So the capability is never negotiated at runtime today: an old client would see a transformed question without being told.
- iOS caller: NONE for the key `clueTransform`; the host route `api/play/nodes` is called (see G37-3).

## G47 author config panel and publish check

Common gate (`ApiAuthorConfigG47Controller.ownedTopic :91`): `topicId` null/<=0 → `{code:500,msg:"参数不合规"}`; no login → `请先登录`; `scope=merchant` (via `MerchantOperationScope.isMerchant`) resolves to merchant owner with permission `PROJECT_MANAGE`, `ServiceException` message returned as error msg; topic missing or `delFlag==2` → `主题不存在`; not owner → `无权操作该主题`. All errors are code 500 (`AjaxResult.error(String)`).

### G47-1 GET /api/topic/publish-check/fields-g47
- Controller: `ApiAuthorConfigG47Controller.java:36-37`, `@GetMapping` `:43`, handler `:44-49`. Auth: token + topic owner.
- Params (query): `topicId` Long required, `scope` String optional.
- Success `data` (`AuthorConfigCheckG47Service.check :30-55`): `{ topicId, checkVersion:"g47-fieldcheck-1", configVersion, passed:bool, blockingCount:int, advisoryCount:int, issues:[{level,code,nodeId,message,blockKey,fieldPath,kind,status}] }`. `kind` ∈ MISSING/INVALID/UNSUPPORTED/NOT_CONFIGURABLE/CONFLICT/OTHER; `status` "BLOCKING" counts as blocking. Types of `level`,`status` strings: values beyond `BLOCKING` UNKNOWN.
- Read-only; no idempotency key. Capability: none. iOS caller: NONE.
- Example: `GET /api/topic/publish-check/fields-g47?topicId=71` → `{"code":200,"msg":"操作成功","data":{"topicId":71,"checkVersion":"g47-fieldcheck-1","configVersion":3,"passed":false,"blockingCount":1,"advisoryCount":0,"issues":[{"level":"ERROR","code":"HINT_LADDER_CONFIG_G47","nodeId":55,"message":"…","blockKey":"node:55","fieldPath":"advancedConfigJson.hintLadder.layers[0].costPoints","kind":"INVALID","status":"BLOCKING"}]}}`

### G47-2 GET /api/topic/author-config/hints-g47
- Controller: same file `:52-62`. Auth: token + owner. Params: `topicId`, `scope` as above.
- Success `data`: `{ topicId, configVersion, nodes:[ { blockKey, nodeId, <panelView…> } ] }` where panelView (`HintLadderConfigCheckerG47.panelView :116-180`) = `{ allowedTypes:["TEXT","IMAGE","LETTER","DIGIT","ANSWER"], costCurrencies:{POINTS:"CONFIGURABLE",GEMS/COINS/RANK_PENALTY_TIME:"NOT_CONFIGURABLE"}, saved:bool, hintsEnabled:bool, freeUsesPerRun:long|null, layers:[{layer:int,type,text,imageUrl,costPoints:long|null,source:"LADDER"|"LEGACY",legacyKey?}], legacy:{hint1,hint2,answerReveal} }`. (when nothing saved: `saved:false, hintsEnabled:false, layers:[]`.) Exact key presence for unsaved case beyond those: UNKNOWN.
- Read-only. Capability none. iOS caller: NONE.
- Example: `GET /api/topic/author-config/hints-g47?topicId=71` → `{"code":200,"msg":"操作成功","data":{"topicId":71,"configVersion":3,"nodes":[{"blockKey":"node:55","nodeId":55,"allowedTypes":["TEXT","IMAGE","LETTER","DIGIT","ANSWER"],"costCurrencies":{"POINTS":"CONFIGURABLE","GEMS":"NOT_CONFIGURABLE","COINS":"NOT_CONFIGURABLE","RANK_PENALTY_TIME":"NOT_CONFIGURABLE"},"saved":false,"hintsEnabled":false,"layers":[]}]}}` (blockKey = `"node:" + nodeId` per `AuthorConfigNamesG47.nodeBlockKey` line 56; topic-level `BLOCK_TOPIC` value UNKNOWN).

### G47-3 POST /api/topic/author-config/hints/validate-g47
- Controller: same file `:65-76`. Auth: token (not owner-gated; no topic). 
- Encoding: JSON `@RequestBody Map` — field `advancedConfigJson` string required, ≤200000 chars; else `{code:500,msg:"参数不合规"}`. No login → `请先登录`. Stateless, saves nothing.
- Success `data`: `{ passed:bool, issues:[…as G47-1…], preview:{…panelView…} }`.
- Idempotent by nature; no key. Capability none. iOS caller: NONE.
- Example: `POST /api/topic/author-config/hints/validate-g47` `{"advancedConfigJson":"{\"hintLadder\":{\"enabled\":true,\"layers\":[{\"type\":\"TEXT\",\"text\":\"x\",\"costPoints\":5}]}}"}` → `{"code":200,"msg":"操作成功","data":{"passed":true,"issues":[],"preview":{"allowedTypes":["TEXT","IMAGE","LETTER","DIGIT","ANSWER"],"saved":true,"hintsEnabled":true,"layers":[{"layer":1,"type":"TEXT","text":"x","imageUrl":null,"costPoints":5,"source":"LADDER"}]}}}` (preview abbreviated)

### G47-4 GET /api/topic/publish-status-g47
- Controller: same file `:81-86`. Auth: token + owner. Params `topicId`, `scope`.
- Success `data` (`PublishStatusProjectorG47.project :22-34`): `{ topicId, configVersion, publishedConfigVersion, draft:{state,hasUnpublishedChanges:bool|null}, review:{state,reason:string|null,commercial:"PENDING"|"NONE"|"UNKNOWN"}, visibility:{state}, sale:{state,reason}, playable:{state:"PLAYABLE"|"NOT_PLAYABLE"|"UNKNOWN",blockedBy:[string]} }`. State vocab (javadoc in `PublishStatusProjectorG47.java`): draft ∈ DRAFT/SUBMITTED/DELETED/UNKNOWN; review.state ∈ NOT_SUBMITTED/PENDING/APPROVED/REJECTED/UNKNOWN; visibility ∈ PRIVATE/PUBLIC/REMOVED/UNKNOWN; sale ∈ NOT_FOR_SALE/COMMERCIAL_REVIEW_PENDING/PRICING_PENDING/ON_SALE/SALE_ENDED/CLOSED/UNKNOWN; playable ∈ PLAYABLE/NOT_PLAYABLE/UNKNOWN.
- Read-only. Capability none. iOS caller: NONE.
- Example: `GET /api/topic/publish-status-g47?topicId=71` → `{"code":200,"msg":"操作成功","data":{"topicId":71,"configVersion":3,"publishedConfigVersion":2,"draft":{"state":"SUBMITTED","hasUnpublishedChanges":true},"review":{"state":"APPROVED","reason":null,"commercial":"NONE"},"visibility":{"state":"PUBLIC"},"sale":{"state":"ON_SALE","reason":null},"playable":{"state":"PLAYABLE","blockedBy":[]}}}`

## G52 publish result (publish status)

### G52-1 GET /api/topic/publish-result-g52
- Controller: `ApiPublishStatusG52Controller.java:34-35`, `@GetMapping` `:40`, handler `:41-49`. Auth: token + owner (merchant scope supported). Params: `topicId` Long required, `scope` optional.
- Errors (code 500): `参数不合规`, `请先登录`, `主题不存在` (also returned for not-owner).
- Success `data` (`PublishNextStepG52.project :51-…`): the G47 five-segment map plus `{ contractVersion:"g52-publish-next-1", nextSteps:[{code,segment}], hasUnknownSegment:bool, allowedActions:[…], soldEdit:{restricted:bool, editable:[string]|null, locked:[string]|null} }`. `code` ∈ REFRESH_STATUS / SUBMIT_FOR_REVIEW / WAIT_CONTENT_REVIEW / FIX_AND_RESUBMIT / WAIT_COMMERCIAL_REVIEW / COMPLETE_PRICING / MAKE_PUBLIC / SALE_ENDED / CLOSED / PLAYABLE; allowed action vocabulary EDIT / EDIT_SOLD_LIMITED / SUBMIT / VIEW_STATUS / UNPUBLISH / STOP_SALE / DELETE; sold editable = description, images, typos, hints_text; locked = price, route, node_order, answers, refund_terms. `allowedActions` is `List<String>` (`PublishNextStepG52.java:101`).
- Read-only, safe to re-call. Capability none. iOS caller: NONE.
- Example: `GET /api/topic/publish-result-g52?topicId=71` → `{"code":200,"msg":"操作成功","data":{"topicId":71,"contractVersion":"g52-publish-next-1","nextSteps":[{"code":"SUBMIT_FOR_REVIEW","segment":"review"}],"hasUnknownSegment":false,"allowedActions":["EDIT","SUBMIT","VIEW_STATUS"],"soldEdit":{"restricted":false,"editable":null,"locked":null}}}` (five-segment fields elided)

### G52-2 GET /api/topic/my-projects-status-g52
- Controller: same file `:51-62`. Auth: token (owner via scope). Param `topicIds` String comma list of positive longs, ≤1000 chars, 1..50 ids (`PublishNextStepG52.MAX_BATCH=50`), `scope` optional. Bad → code 500 `参数不合规`; not logged in → `请先登录`.
- Success `data` (`batch :138-…`): `{ contractVersion, items:[ <G52-1 body> | {topicId, found:false, …} ], unknownCount:int }`. Other keys of `notFound` beyond `topicId`,`found`: UNKNOWN.
- Read-only. Capability none. iOS caller: NONE.
- Example: `GET /api/topic/my-projects-status-g52?topicIds=71,72` → `{"code":200,"msg":"操作成功","data":{"contractVersion":"g52-publish-next-1","items":[{"topicId":72,"found":false}],"unknownCount":0}}` (item 71 elided)

## G48 admin read-only audit

Auth for all three: admin (sys-user) token plus `@PreAuthorize("@ss.hasPermi('business:ug:audit:list')")`. Permission `business:ug:audit:review` additionally un-redacts secret-keyed values (`secretsVisible:true`). Both permission strings are invented (`UgAuditAdminG48Controller.java:23-24`). Guest: no. Controller: `web/controller/business/UgAuditAdminG48Controller.java:19-20` (`/business/ug-audit`). NO write route and NO export route (comment `:13`).
Data feed: `UgAuditServiceG48` aggregates all `UgAuditSourceG48` beans; **no class implements `UgAuditSourceG48` on this branch** (grep `implements UgAuditSourceG48` → none). So every response currently has empty `slices`/`lines`/`sources`.
Encoding: path variables. Invalid id (<1) → `{code:500,msg:"参数不合规"}`. iOS caller: NONE (admin web console).

### G48-1 GET /business/ug-audit/topic/{topicId}/config — controller `:32-40`
- Success `data` (`UgAuditServiceG48.config :39-47`, `envelope :88-96`): `{ slices:{ "<sliceName>": {…redacted summary…} }, sources:[string], secretsVisible:bool, readOnly:true }`.
- Example: `GET /business/ug-audit/topic/71/config` → `{"code":200,"msg":"操作成功","data":{"slices":{},"sources":[],"secretsVisible":false,"readOnly":true}}`

### G48-2 GET /business/ug-audit/run/{runId}/quota — controller `:43-51`
- Success `data`: same envelope; a slice appears only if its source returns non-null.
- Example: `GET /business/ug-audit/run/9001/quota` → `{"code":200,"msg":"操作成功","data":{"slices":{},"sources":[],"secretsVisible":false,"readOnly":true}}`

### G48-3 GET /business/ug-audit/run/{runId}/detail — controller `:54-62`
- Success `data` (`detail :63-86`): `{ lines:[{…redacted line…, slice:string}], sources:[string], secretsVisible:bool, readOnly:true }`.
- Example: `GET /business/ug-audit/run/9001/detail` → `{"code":200,"msg":"操作成功","data":{"lines":[],"sources":[],"secretsVisible":false,"readOnly":true}}`

---

## Cross-route findings worth the owner's attention (facts, no code changed)

1. `compatibility.supported` semantics differ per route: G38/G42/G44 return `null` when undeclared or malformed; G37/G39/G46 return `true` when undeclared; G41 returns `false` when undeclared. The G43 object has a different shape (`confirmed`).
2. G44 `confirm` is form/query only; the other POST gameplay routes (G39, G41, G42, G47-3) are JSON. G40 uses `run_id` (snake_case) while all others use `runId`.
3. Run id type differs: G38 `runId` string (parsed to long), G39/G41 Long, G40 string, G42 uses topic/node ids as strings, no run id.
4. `requestId` formats differ: G39 `[A-Za-z0-9_-]{8,64}`; G41/G44 canonical UUID (G44 lower-case); G42 `[A-Za-z0-9_.:\-]{8,64}`; G45 lookup accepts `[A-Za-z0-9:_-]{1,80}`.
5. G45 returns its fields at the top level of the response (not in `data`) and uses code 520 for unsettled.
6. `GET /api/play/help` (G38) and `GET /api/play/help/quota` (G39) both return the hint ladder with different JSON shapes.
7. G43 and G46 capabilities are defined but not evaluated on any route (no production caller of `QaOptionMediaG43.negotiate` or `ClueTransformG46Support.compatibility`).
8. iOS has zero callers for all of these routes and sends no capability declaration on `api/play/nodes`.
