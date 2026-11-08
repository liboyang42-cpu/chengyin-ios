# Route table rt-05 — groups G49–G58 (wave 2)

Static contract. Source: backend `origin/claude/be-v2-fixes` (branched here as `cloud/rt-05`); iOS `origin/wip/wave5-build` @ `3f4f6053`.
Nothing here was run against a live server. Every shape below was read from the controller / service / VO code. `UNKNOWN` = not determinable from code. Examples are SYNTHETIC (values invented, keys and types taken from the code).

Groups: G49 template adoption conditions · G50 location to-dos · G51 source versions/credits/preview · G52 publish results · G53 node closure (arrival failure/recovery read side) · G54 offline reading + position · G55 seats/invites · G56 team handover · G57 order/after-sales read facts · G58 post-game projections.
Controllers owned (10 G-suffixed files, **26 routes**), all under `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`.

## 0. Findings up front

1. **`settlementSummary` returned by any route: NO.** `grep -rI settlementSummary` over the whole backend checkout matches only `docs/release/be-g58-report.md:19` and `:41` (prose saying the name does not exist). No Java, XML or SQL file puts that key in a response. iOS only has a *local variable* `settlementSummary` at `App/ClubGovernanceViews.swift:1354-1364` (a `ClubOpsSettlementSummary` built from the club-ops settlement operation, which reads `unverifiedSettledCount`, `topics`, `settledAmountStatus`, `settledAmountText`, `isOwner`, `Core/ClubOpsSettlementPresentation.swift:11-16`); it is not one of the 26 routes below.
2. **iOS callers: NONE for all 26 routes.** Searched the whole iOS checkout (`App/ Core/ Tests/`) for every path tail and the `-g5x` suffixes. No match. The only near hits are other routes (`api/registration/quote|create|info`, `api/team/my|info|create|join|quit|kick|disband|join-mode`, `api/club/leaderboard`, `api/growth/leaderboard`), none in this table. `Core/CreatorContentContracts.swift:33` mentions `/api/template/topic-template/list` in a comment only.
3. **No route here is guest-readable.** All 26 are `anyRequest().authenticated()`; none is in the permit list and none carries `@Anonymous`. This includes G51 `/preview` and non-owner `/credits`, which are "public data" but still need a token.
4. Possible defect, G53 `/api/play/node-closure` (`ApiPlayClosureG53Controller.java:24-27`): checks only that the topic exists. It does not check that the node belongs to the topic, nor that the caller is a player or owner of it. Any logged-in member can read any topic's closure contact/follow-up text. Not changed (read-only task).
5. G49 `adoption-info` is **POST** with a form/query `id`, not GET (`ApiTopicTemplateAdoptionG49Controller.java:21`).
6. G51 `adoption/record` reads the request key `sourceTemplateId` (`ApiTemplateSourceG51Controller.java:32`), but its response key is `sourceTopicId`. Different names for the same id.
7. Group "arrival failure/recovery": the reason codes (`ARRIVE_*`, `reasonCode`, `retryable`, `refreshRequired`) are in `ArriveFailureG53.java` and decorate `/api/play/arrive`. That controller is not G-suffixed, so it is not in this table. The only G53 controller route is `node-closure`.

## 1. Common contract (applies to every row unless the row says otherwise)

| Item | Fact | Source |
|---|---|---|
| Auth header | `Authorization: Bearer <app token>` (header name from `token.header`, prefix `Bearer `) | `chengyinhub-admin/src/main/resources/application.yml:115`; `Constants.java:106`; `AppTokenService.java:299-305` |
| Token required | Yes. All paths start `/api/` → app-token branch. Not in any permitAll list. | `JwtAuthenticationTokenFilter.java:60-67`; `SecurityConfig.java:139-163` (permit list), `:166` (`anyRequest().authenticated()`) |
| Guest allowed | No. No-token / bad-token → HTTP 401, body `{"code":401,"msg":"登录状态已失效，请重新登录"}`. | `AuthenticationEntryPointImpl.java` (`commence`) |
| Other required headers | None found in any of the 10 controllers. | controllers |
| Envelope | `AjaxResult` = `HashMap`: `{"code":int,"msg":string,"data"?:any}`. Success `code=200,msg="操作成功"`. `AjaxResult.error(msg)` = `code 500`. `data` key is omitted when null. | `AjaxResult.java:30-104,157-172`; `HttpStatus.java:13,88` |
| Business-error HTTP status | Controllers return the `AjaxResult` as the body, so HTTP 200 with `code != 200` (static inference; not run live). | controllers |
| Error `msg` | Non-200 messages are passed through `UserSafeMessage.of`; messages containing class names/SQL/paths or longer than 120 chars become `系统繁忙，请稍后重试`. | `AjaxResult.java:204-207`; `UserSafeMessage.java` |
| Uncaught exceptions | `ServiceException` → `{code: e.code or 500, msg}`, `data` carried if set. Other `RuntimeException`/`Exception` → `{code:500,msg}`. | `GlobalExceptionHandler.java:130-146,178-199` |
| `@RateLimiter` | Redis counter per member per method (`time` seconds, `count` calls). Over limit → `ServiceException("访问过于频繁，请稍候再试")`. Redis failure → `RuntimeException("服务器限流异常，请稍候再试")`. | `RateLimiterAspect.java:54-75` |
| Scope param | Where a route takes `scope`: `MERCHANT` (case-insensitive) resolves to the owning member via `PROJECT_MANAGE` permission; `CLUB` or empty = personal; any other value → `ServiceException("业务作用域参数不合法", 400)`. | `MerchantOperationScope.java:14-20` |
| Date values (`java.util.Date`) | Jackson time zone `Asia/Shanghai`; no `spring.jackson.*` format override found in `application.yml`. Exact string format: UNKNOWN until run live (Spring Boot default would be ISO-8601 with offset). Epoch-millis fields below are `long`. | `ApplicationConfig.java` (timezone customizer) |
| Null fields in `data` | Map-built payloads `put(k, null)` explicitly. No `default-property-inclusion` override found, so they appear as JSON `null` (static inference). | `application.yml` (no jackson block) |
| Malformed JSON / type mismatch | Only `MethodArgumentTypeMismatchException` has a dedicated handler (`GlobalExceptionHandler.java:159`). A missing required param or unreadable body falls to the generic `Exception` handler → `code 500`. Exact msg UNKNOWN. | `GlobalExceptionHandler.java` |

Notation: "form" = non-`@RequestBody` parameters, bound from query string or `application/x-www-form-urlencoded`. "JSON" = `@RequestBody`, `Content-Type: application/json`.
iOS caller for every row: **NONE** (see §0.2).

---

## G49 — template adoption conditions

### G49-1 `POST /api/template/topic-template/adoption-info`
- Controller: `ApiTopicTemplateAdoptionG49Controller.java:21-28` (class mapping `:15`). Service `TemplateAdoptionG49Service.adoptionInfo` (`:142-169`).
- Auth: token required; guest no. Encoding: **form** (`Long id`), no body.
- Params: `id` Long, required (null or <1 → error).
- Success `data` (LinkedHashMap, `:151-168`):
  `templateTopicId` long · `cityCode` string|null · `nodeCount` int · `placeSlotCount` int · `configVersion` string|null (from `cms_topic_template_meta.version`, key is named `configVersion`) · `templateStatus`/`evidenceLevel`/`isOfficial` (present only when a meta row exists; types are the column types, UNKNOWN) · `playerCount`,`supportedClients`,`language`,`licenseSummary`,`hostDependency` always `null` · `missing` string[] (always those 5 names) · `bindingIntents` string[] (`TemplateAdoptionPolicyG49.INTENT_KEEP`, `INTENT_SWITCH`; literal strings UNKNOWN here, defined in `TemplateAdoptionPolicyG49.java`).
- Errors: `id` null/<1 → `{code:500,msg:"缺少模板ID"}` (`:23`). Not a public template → `{code:404,msg:"模板不存在",data:{reasonCode:"TEMPLATE_NOT_FOUND"}}` (`:25-27`, `Service:145,148`).
- Idempotency: read-only, none. Headers: none beyond auth.
- Note: the sibling `/api/template/topic-template/use` (carries `requestId`, `Rejected` codes 400/409/500 and `reasonCode`s) is **not** a G49-suffixed controller; out of scope.
- Example (SYNTHETIC):
  - req: `POST /api/template/topic-template/adoption-info` · `Content-Type: application/x-www-form-urlencoded` · `id=1024`
  - res: `{"code":200,"msg":"操作成功","data":{"templateTopicId":1024,"cityCode":"310100","nodeCount":8,"placeSlotCount":6,"configVersion":"3","templateStatus":"PUBLISHED","evidenceLevel":"L2","isOfficial":0,"playerCount":null,"supportedClients":null,"language":null,"licenseSummary":null,"hostDependency":null,"missing":["playerCount","supportedClients","language","licenseSummary","hostDependency"],"bindingIntents":["KEEP","SWITCH"]}}`

---

## G50 — location to-dos / on-site question reconfirm

Both routes: author-only. Owner gate in `ownedTopic` (`ApiLocationTodoG50Controller.java:82-95`): `topicId` null/≤0 → `error("参数不合规")`; not logged in → `error("请先登录")`; topic missing or `delFlag==2` → `error("主题不存在")`; not owner → `error("无权操作该主题")`; all `code 500`. `scope=MERCHANT` resolves owner via `merchantAccessService.require(...)` and surfaces `ServiceException` text as `error(msg)` code 500. Invalid scope value → code 400 via `ServiceException` (thrown outside the try).

### G50-1 `GET /api/template/topic-template/location-todos-g50`
- Controller: `ApiLocationTodoG50Controller.java:40-46`. Service `LocationTodoG50Service.todos` (`:47-51`), projection `LocationTodoLogicG50.project` (`:52-79`).
- Auth: token, owner of the topic. Encoding: **form/query**.
- Params: `topicId` Long required · `cityCode` String required, regex `^[A-Za-z0-9_\-]{2,32}$` (`LocationTodoLogicG50.java:28`), trimmed · `scope` String optional.
- Success `data`: `topicId` long · `cityCode` string · `items[]` · `openCount` int · `ready` bool (`openCount==0 && items non-empty`) · `draftSaveAllowed` bool (always true).
  `items[]` element (`:83-90`): `nodeId` long · `name` string · `kind` `"PLACE"|"ON_SITE_QUESTION"` · `status` `"CONFIRMED"|"NEEDS_RECONFIRM"|"PLACE_MISSING"|"BLOCKED_BY_PLACE"` · `reason` string (from `reason(status)`; text UNKNOWN here, `:92+`). Only enabled nodes (`status=1`).
- Errors: owner gate above (code 500); bad city → `{code:400,msg:"城市编码无效",errorCode:"CITY_CODE_INVALID"}` (`fail()` `:70-74`, `Service:118-122`).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC):
  - req: `GET /api/template/topic-template/location-todos-g50?topicId=2001&cityCode=310100`
  - res: `{"code":200,"msg":"操作成功","data":{"topicId":2001,"cityCode":"310100","items":[{"nodeId":9001,"name":"外滩源","kind":"PLACE","status":"CONFIRMED","reason":"…"},{"nodeId":9001,"name":"外滩源","kind":"ON_SITE_QUESTION","status":"NEEDS_RECONFIRM","reason":"…"}],"openCount":1,"ready":false,"draftSaveAllowed":true}}`

### G50-2 `POST /api/template/topic-template/location-reconfirm-g50`
- Controller: `ApiLocationTodoG50Controller.java:49-68`. Service `reconfirm` (`:53-101`).
- Auth: token, owner. Encoding: **JSON body** + `scope` as a **query/form** param (it is a plain `String scope` beside `@RequestBody`, `:50`).
- Body (`Map<String,Object>`): `topicId` number|numeric string, required · `cityCode` string, required (same regex) · `requestId` string, required, regex `^[A-Za-z0-9_.:\-]{8,64}$` (`LocationTodoLogicG50.java:29`) · `items` array, 1..200, each `{nodeId: number|numeric string, kind: "PLACE"|"ON_SITE_QUESTION"}`. A non-object item → `error("参数不合规")` (`:58`); a non-array `items` is treated as empty → `ITEMS_INVALID`.
- Success `data`: same shape as G50-1 (`project(...)` after the writes). A replay returns the **stored** response JSON of the first call (`Service:124-127`).
- Errors (`fail()` → `{code, msg, errorCode}`): `REQUEST_ID_INVALID` 400 · `ITEMS_INVALID` 400 · `CITY_CODE_INVALID` 400 · `KIND_INVALID` 400 · `NODE_NOT_IN_TOPIC` 404 · `PLACE_NOT_SET` 409 · `NO_ON_SITE_QUESTION` 409 · `CONFIRM_PLACE_FIRST` 409 · `REQUEST_ID_REUSED` 409 (same requestId, different payload hash). Owner-gate errors as above (500).
- **Idempotency key: `requestId`** (receipt keyed by member id + requestId, payload hash compared). `PLACE` items are processed before `ON_SITE_QUESTION` in one batch. Server computes the place fingerprint; the client never sends it. Headers: none.
- Example (SYNTHETIC):
  - req: `POST /api/template/topic-template/location-reconfirm-g50` · `{"topicId":2001,"cityCode":"310100","requestId":"rc-20261108-0001","items":[{"nodeId":9001,"kind":"PLACE"},{"nodeId":9001,"kind":"ON_SITE_QUESTION"}]}`
  - res: `{"code":200,"msg":"操作成功","data":{"topicId":2001,"cityCode":"310100","items":[{"nodeId":9001,"name":"外滩源","kind":"PLACE","status":"CONFIRMED","reason":"…"}],"openCount":0,"ready":true,"draftSaveAllowed":true}}`
  - 409: `{"code":409,"msg":"请先确认该节点地点","errorCode":"CONFIRM_PLACE_FIRST"}`

---

## G51 — source version, credits, language, preview

Base: `@RequestMapping("/api/template/topic-template/source-g51")` (`ApiTemplateSourceG51Controller.java:21`). Member id from token only (`member()` `:26-28`). All errors from the service are `AjaxResult.error(msg)` = **code 500**, no `errorCode`. Not-owner and not-found share the message `对象不存在或无权访问` (`Service:36`). Contract tag in responses: `"contract":"g51-template-source-1"`.

### G51-1 `POST /api/template/topic-template/source-g51/adoption/record`
- Controller: `:30-34`. Service `recordAdoption` (`:40-64`).
- Auth: token. Encoding: **JSON**.
- Body: `adoptedTopicId` number, required · `sourceTemplateId` number, required (must differ from adopted) · `requestId` string required, regex `[A-Za-z0-9:_-]{1,80}` (`TemplateSourceNamesG51.java:57`).
- Success `data`: `lineageState:"RECORDED"` · `sourceTopicId` long · `sourceTemplateVersion` string|null · `sourceConfigVersion` long|null · `adoptedAt` string (`String.valueOf` of the DB timestamp; exact format UNKNOWN).
- Errors (all code 500): `请先登录` · `主题标识无效` · `requestId 无效` · `对象不存在或无权访问` (adopted topic not yours) · `来源不是可用模板` · `来源记录暂不可确认，请稍后用原 requestId 重试` · `该草稿已记录其他来源`.
- Idempotency: effectively **keyed by adopted topic** (`insertLineageIgnore`; one lineage row per `adopted_topic_id`). `requestId` is validated and stored but a replay is recognised by the adopted topic, not by the id. Headers: none.
- Example (SYNTHETIC): req `{"adoptedTopicId":3001,"sourceTemplateId":1024,"requestId":"adopt-3001-a"}` → res `{"code":200,"msg":"操作成功","data":{"lineageState":"RECORDED","sourceTopicId":1024,"sourceTemplateVersion":"3","sourceConfigVersion":17,"adoptedAt":"2026-11-08 10:00:00.0"}}`

### G51-2 `GET /api/template/topic-template/source-g51/adoption`
- Controller: `:36-39`. Service `adoptionSource` (`:66-98`).
- Auth: token, owner of the adopted draft. Encoding: **form/query** (`String topicId`, parsed to Long).
- Params: `topicId` required.
- Success `data`:
  - No lineage row (legacy): `contract` · `topicId` · `lineageState:"HISTORY_SOURCE_UNVERIFIED"` · `sourceTopicId:null` · `updateState:"UNKNOWN"` · `actions:[{action:"CONTINUE_CURRENT",supported:true}]`.
  - With lineage: `contract` · `topicId` · (`lineageState`,`sourceTopicId`,`sourceTemplateVersion`,`sourceConfigVersion`,`adoptedAt` as in G51-1) · `currentSourceVersion` string|null · `updateState` `"CURRENT"|"NEWER_SOURCE_AVAILABLE"|"SOURCE_UNAVAILABLE"|"UNKNOWN"` · `actions[]` of `{action:"CONTINUE_CURRENT"|"VIEW_NEW_DIFF"|"SAVE_AS_NEW_DRAFT", supported:bool, reason?:"DIFF_NOT_AVAILABLE"}` (`TemplateAdoptionUpdateG51.java`). `VIEW_NEW_DIFF` is always `supported:false` when offered.
- Errors (500): `请先登录` · `主题标识无效` · `对象不存在或无权访问`.
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET …/source-g51/adoption?topicId=3001` → `{"code":200,"msg":"操作成功","data":{"contract":"g51-template-source-1","topicId":3001,"lineageState":"RECORDED","sourceTopicId":1024,"sourceTemplateVersion":"3","sourceConfigVersion":17,"adoptedAt":"2026-11-08 10:00:00.0","currentSourceVersion":"4","updateState":"NEWER_SOURCE_AVAILABLE","actions":[{"action":"CONTINUE_CURRENT","supported":true},{"action":"VIEW_NEW_DIFF","supported":false,"reason":"DIFF_NOT_AVAILABLE"},{"action":"SAVE_AS_NEW_DRAFT","supported":true}]}}`

### G51-3 `POST /api/template/topic-template/source-g51/credits/save`
- Controller: `:41-44`. Service `saveCredits` (`:112-165`).
- Auth: token, owner. Encoding: **JSON**.
- Body: `topicId` number required · `credits` array ≤200 of `{assetRef (required, ≤200 chars, unique in the list), sourceType ("ORIGINAL"|"LICENSED"|"PUBLIC_DOMAIN"|"USER_UPLOAD"|"UNKNOWN", default UNKNOWN), licenseCode?, attribution?, sourceUrl?}` (each text ≤200) · `sourceLocale` string? (regex `[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}`) · `locales` array ≤20 of `{locale, status:"AVAILABLE"|"PARTIAL"}`.
- Semantics: replaces credits and locales **as a whole** (delete + insert).
- Success `data` (`ownerCredits` `:202-212`): `contract` · `topicId` · `credits[]` `{assetRef,sourceType,licenseCode,attribution,sourceUrl}` · `issues[]` `{assetRef, code:"ASSET_SOURCE_UNKNOWN"|"ASSET_LICENSE_MISSING"|"ASSET_ATTRIBUTION_MISSING", fieldPath:"licenseCode"|"attribution"}`. No `language` key on save.
- Errors (500): `请先登录` · `主题标识无效` · `对象不存在或无权访问` · validation texts from `IllegalArgumentException`: `credits 必须是数组`, `credits 项无效`, `assetRef 重复`, `credits 过多`, `locales 必须是数组`, `locales 项无效`, `locale status 无效`, `locale 重复`, `locales 过多`, `<field> 必填`, `<field> 过长`, `<field> 无效`, `sourceType 无效`.
- Idempotency: no `requestId`; whole-set replace is naturally retry-safe. Headers: none.
- Example (SYNTHETIC): req `{"topicId":3001,"credits":[{"assetRef":"img-1","sourceType":"LICENSED","licenseCode":"CC-BY-4.0"}],"sourceLocale":"zh-CN","locales":[{"locale":"en","status":"PARTIAL"}]}` → res `{"code":200,"msg":"操作成功","data":{"contract":"g51-template-source-1","topicId":3001,"credits":[{"assetRef":"img-1","sourceType":"LICENSED","licenseCode":"CC-BY-4.0","attribution":null,"sourceUrl":null}],"issues":[{"assetRef":"img-1","code":"ASSET_ATTRIBUTION_MISSING","fieldPath":"attribution"}]}}`

### G51-4 `GET /api/template/topic-template/source-g51/credits`
- Controller: `:46-49`. Service `credits` (`:167-184`).
- Auth: token (not anonymous). Encoding: **form/query**. Params: `topicId` required · `lang` optional locale string (invalid → treated as absent).
- Success `data`:
  - Caller is owner: same as G51-3 plus `language`.
  - Otherwise (topic must be a template): `contract` · `topicId` · `credits[]` `{sourceType,licenseCode,attribution}` (no `assetRef`, no url) · `language`.
  - `language` (`TemplateCreditsG51.resolveLanguage`): `requestedLanguage` string|null · `availableLanguages` string[] · `actualLanguage` string|null · `state` `"UNDECLARED"|"AVAILABLE"|"PARTIAL"|"FALLBACK"` · `missingTranslation` bool · `issueCode:"TRANSLATION_MISSING"` (only when a lang was requested and absent).
- Errors (500): `主题标识无效` · `对象不存在或无权访问` (topic missing, or non-owner and not a template).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET …/source-g51/credits?topicId=1024&lang=en` → `{"code":200,"msg":"操作成功","data":{"contract":"g51-template-source-1","topicId":1024,"credits":[{"sourceType":"LICENSED","licenseCode":"CC-BY-4.0","attribution":"Photo by A"}],"language":{"requestedLanguage":"en","availableLanguages":["zh-CN"],"actualLanguage":"zh-CN","state":"FALLBACK","missingTranslation":true,"issueCode":"TRANSLATION_MISSING"}}}`

### G51-5 `GET /api/template/topic-template/source-g51/preview`
- Controller: `:51-54`. Service `preview` (`:186-200`), whitelist `TemplatePreviewG51.project`.
- Auth: token (the code never reads the member; still behind the auth filter). Encoding: **form/query**. Params: `topicId` required · `lang` optional.
- Success `data`: `topicId` · `name` · `subtitle` · `description` · `imgUrl` · `locationCount` · `totalTime` (types are those of `TopicTemplateDetailVO`, UNKNOWN here) · `chapters[]` `{id,name,description,nodeCount}` · `credits[]` `{sourceType,licenseCode,attribution}` · `language` (as above).
- Errors (500): `主题标识无效` · `对象不存在或无权访问` (not a template, or detail null).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET …/source-g51/preview?topicId=1024` → `{"code":200,"msg":"操作成功","data":{"topicId":1024,"name":"外滩夜行","subtitle":"…","description":"…","imgUrl":"https://…/c.jpg","locationCount":6,"totalTime":90,"chapters":[{"id":11,"name":"序章","description":"…","nodeCount":3}],"credits":[],"language":{"requestedLanguage":null,"availableLanguages":[],"actualLanguage":null,"state":"UNDECLARED","missingTranslation":false}}}`

---

## G52 — publish result and project status

Both routes: owner-only; `scope=MERCHANT` resolves owner. Foreign topic and missing topic are indistinguishable. Never publishes; safe to re-call.

### G52-1 `GET /api/topic/publish-result-g52`
- Controller: `ApiPublishStatusG52Controller.java:40-48`. Projection `PublishNextStepG52.project` (`:51-77`) over `PublishStatusProjectorG47.project` (`:22-35`).
- Auth: token, owner. Encoding: **form/query**. Params: `topicId` Long required · `scope` optional.
- Success `data`: `topicId` · `configVersion` long|null · `publishedConfigVersion` long|null ·
  `draft` `{state:"DRAFT"|"SUBMITTED"|"DELETED"|"UNKNOWN", hasUnpublishedChanges: bool|null}` ·
  `review` `{state:"NOT_SUBMITTED"|"PENDING"|"APPROVED"|"REJECTED"|"UNKNOWN", reason: string|null (only when REJECTED), commercial:"NONE"|"PENDING"|"UNKNOWN"}` ·
  `visibility` `{state:"PRIVATE"|"PUBLIC"|"REMOVED"|"UNKNOWN"}` ·
  `sale` `{state:"NOT_FOR_SALE"|"COMMERCIAL_REVIEW_PENDING"|"PRICING_PENDING"|"ON_SALE"|"SALE_ENDED"|"CLOSED"|"UNKNOWN", reason: string|null}` ·
  `playable` `{state:"PLAYABLE"|"NOT_PLAYABLE"|"UNKNOWN", blockedBy: string[] of "review"|"visibility"|"sale"}` ·
  `contractVersion:"g52-publish-next-1"` · `nextSteps[]` `{code, segment}` (codes: `REFRESH_STATUS, SUBMIT_FOR_REVIEW, WAIT_CONTENT_REVIEW, FIX_AND_RESUBMIT, WAIT_COMMERCIAL_REVIEW, COMPLETE_PRICING, MAKE_PUBLIC, SALE_ENDED, CLOSED, PLAYABLE`) · `hasUnknownSegment` bool · `allowedActions` string[] (`VIEW_STATUS, EDIT, EDIT_SOLD_LIMITED, SUBMIT, UNPUBLISH, STOP_SALE, DELETE`) · `soldEdit` `{restricted:bool, editable: string[]|null, locked: string[]|null}` (when restricted: editable `description,images,typos,hints_text`; locked `price,route,node_order,answers,refund_terms`).
- Errors (all 500): `参数不合规` (topicId null/≤0) · `请先登录` (also returned when merchant permission is denied, `ownerId()` returns null) · `主题不存在` (missing or not owner).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/topic/publish-result-g52?topicId=3001` → `{"code":200,"msg":"操作成功","data":{"topicId":3001,"configVersion":5,"publishedConfigVersion":4,"draft":{"state":"SUBMITTED","hasUnpublishedChanges":true},"review":{"state":"PENDING","reason":null,"commercial":"NONE"},"visibility":{"state":"PRIVATE"},"sale":{"state":"NOT_FOR_SALE","reason":"RECRUITING"},"playable":{"state":"NOT_PLAYABLE","blockedBy":["review","visibility","sale"]},"contractVersion":"g52-publish-next-1","nextSteps":[{"code":"WAIT_CONTENT_REVIEW","segment":"review"}],"hasUnknownSegment":false,"allowedActions":["VIEW_STATUS","EDIT","DELETE"],"soldEdit":{"restricted":false,"editable":null,"locked":null}}}`

### G52-2 `GET /api/topic/my-projects-status-g52`
- Controller: `ApiPublishStatusG52Controller.java:51-65`; `parseIds` `:67-78`; `PublishNextStepG52.batch/notFound`.
- Auth: token, owner. Encoding: **form/query**. Params: `topicIds` String required, comma-separated positive longs, 1..50 distinct, string ≤1000 chars (duplicates dropped, order kept) · `scope` optional.
- Success `data`: `contractVersion` · `unknownCount` long · `items[]` — one per requested id in order; each is the G52-1 object, or `{topicId, found:false}` for a missing/foreign topic (that element has no other keys, including no `hasUnknownSegment`).
- Errors (500): `请先登录` · `参数不合规` (blank, non-numeric, ≤0, empty or >50 ids).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/topic/my-projects-status-g52?topicIds=3001,9999` → `{"code":200,"msg":"操作成功","data":{"contractVersion":"g52-publish-next-1","items":[{"topicId":3001,"…":"(G52-1 object)"},{"topicId":9999,"found":false}],"unknownCount":0}}`

---

## G53 — node closure (read side of arrival failure/recovery)

### G53-1 `GET /api/play/node-closure`
- Controller: `ApiPlayClosureG53Controller.java:22-28`. Service `PlayNodeClosureG53Service.view` (`chengyinhub-admin/.../service/play/PlayNodeClosureG53Service.java`).
- Auth: token required; **no ownership or player-entitlement check** (see §0.4). `@RateLimiter` 60 / 10 s / member. Encoding: **form/query**.
- Params: `topicId` Long **required** (`@RequestParam`) · `nodeId` Long **required**. Missing param → generic handler (msg UNKNOWN).
- Success `data`: `topicId` **string** · `nodeId` **string** · `closed` bool · when `closed`: `reasonCode` string|null · `contactText` string|null · `followupText` string|null · `approvedSubstitutes[]` `{kind: string, altNodeId?: string, evidenceType?: string}` (the last two keys omitted when null; `[]` when not closed) · `skipWithRewardAllowed` bool (always `false`).
  When not closed the keys `reasonCode`,`contactText`,`followupText` are absent (not null).
- Errors (500): `参数不合规` (≤0) · `主题不存在`.
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/play/node-closure?topicId=3001&nodeId=9001` → `{"code":200,"msg":"操作成功","data":{"topicId":"3001","nodeId":"9001","closed":true,"reasonCode":"VENUE_CLOSED","contactText":"…","followupText":"…","approvedSubstitutes":[{"kind":"ALT_NODE","altNodeId":"9002"}],"skipWithRewardAllowed":false}}`

---

## G54 — offline reading manifest and reading position

Base `@RequestMapping("/api/play/reading-g54")` (`ApiReadingRecoveryG54Controller.java:19`). Member from token (`currentMemberId()` `:71-78`, returns 0 on failure). All three routes first call `entry.nodes(member, activityId, topicId)` (`PlayEntryApplication.java:72+`) as the entitlement gate; **its error result is returned as-is** (messages such as `请先登录`, `参数有误`, `活动或主题不存在`, code 500; full list UNKNOWN, owned by the play module).
`contentIdentity` format: `"t<topicId>:cv<configVersion or 0>"` (`ReadingRecoveryG54Service.identityOf`).

### G54-1 `GET /api/play/reading-g54/manifest`
- Controller: `:29-40`. Builder `OfflineManifestBuilderG54.build`.
- Auth: token. `@RateLimiter` 60/10 s. Encoding: **form/query**.
- Params: `activityId` Long optional (null/0 = self-play) · `topicId` Long (needed when `activityId` is empty; nothing enforces it except `nodes()`).
- Success `data`: `manifestVersion:"g54-offline-manifest-1"` · `topicId` · `activityId` (0 when none) · `contentIdentity` · `resourceSetDigest` string (sha256 hex) · `lastSyncedAt` string (`Instant.toString()`, UTC ISO-8601) · `resources[]` · `resourcesTruncated` bool (cap 400) · `chapters[]` · `requiredCount` long · `optionalCount` long · `policy` `{cacheScope:"ACCOUNT_PRIVATE", cacheKey:string, partialPackageMayReplaceComplete:false, newVersionAutoReplacesRunningGame:false, sizeAndChecksumFromServer:false, offlinePackageVerified:false}` · `offlineScope` `{canReadOffline:["STORY_TEXT","IMAGES","AUDIO_NARRATION"], neverShownAsDoneOffline:["PAYMENT","COMPETITION","SETTLEMENT","ARRIVAL","ANSWER_JUDGEMENT"]}`.
  `resources[]`: `resourceId` ("r"+20 hex) · `url` · `kind` `"IMAGE"|"AUDIO"|"VIDEO"|"OTHER"` · `role` `"REQUIRED"|"OPTIONAL"` · `source` `"topicCover"|"topicAudio"|"chapterCover"|"chapterAudio"|"block"` · `chapterId` (any JSON type taken from the nodes payload, or null) · `offlineEligible` bool · `sizeBytes` null · `checksum` null · `integrity:"CLIENT_VERIFIES"`.
  `chapters[]`: `chapterId` · `audioResourceId` string|null · `audioHasTextAlternative` bool · `imageResourceIds` string[].
- Errors: nodes() errors pass through; `主题不存在` with `code 404` if the topic row is gone (`ServiceException(…,404)`).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/play/reading-g54/manifest?topicId=3001` → `{"code":200,"msg":"操作成功","data":{"manifestVersion":"g54-offline-manifest-1","topicId":3001,"activityId":0,"contentIdentity":"t3001:cv5","resourceSetDigest":"9f2c…","lastSyncedAt":"2026-11-08T02:00:00Z","resources":[{"resourceId":"r0123456789abcdef0123","url":"https://cdn/x.jpg","kind":"IMAGE","role":"OPTIONAL","source":"topicCover","chapterId":null,"offlineEligible":true,"sizeBytes":null,"checksum":null,"integrity":"CLIENT_VERIFIES"}],"resourcesTruncated":false,"chapters":[],"requiredCount":0,"optionalCount":1,"policy":{"cacheScope":"ACCOUNT_PRIVATE","cacheKey":"g54:3001:0:t3001:cv5","partialPackageMayReplaceComplete":false,"newVersionAutoReplacesRunningGame":false,"sizeAndChecksumFromServer":false,"offlinePackageVerified":false},"offlineScope":{"canReadOffline":["STORY_TEXT","IMAGES","AUDIO_NARRATION"],"neverShownAsDoneOffline":["PAYMENT","COMPETITION","SETTLEMENT","ARRIVAL","ANSWER_JUDGEMENT"]}}}`

### G54-2 `GET /api/play/reading-g54/position`
- Controller: `:42-49`. Service `read` (`ReadingRecoveryG54Service.java`).
- Auth: token. `@RateLimiter` 120/10 s. Encoding: **form/query**. Params: `activityId` optional · `topicId` required (>0, else `topicId 必填`).
- Success `data`: no bookmark → `{exists:false, currentContentIdentity, isProgress:false, affectsCompletion:false}`. Bookmark → `exists:true` · `chapterId` long · `blockIndex` int|null · `scrollRatio` double|null · `audioMs` long|null · `audioResourceId` string|null · `contentIdentity` · `clientSeq` long · `lastRequestId` string · `updatedAt` Date · `contentChanged` bool · `currentContentIdentity` · `isProgress:false` · `affectsCompletion:false` · `chapterExists` bool.
- Errors: entitlement errors pass through (code 500); `请先登录` code 401 and `topicId 必填` code 400 from the service (`ServiceException`); `主题不存在` code 404.
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/play/reading-g54/position?topicId=3001` → `{"code":200,"msg":"操作成功","data":{"exists":true,"chapterId":11,"blockIndex":4,"scrollRatio":0.35,"audioMs":null,"audioResourceId":null,"contentIdentity":"t3001:cv5","clientSeq":12,"lastRequestId":"3f2b8a40-1c2d-4e5f-8a9b-0c1d2e3f4a5b","updatedAt":"2026-11-08T10:00:00.000+08:00","contentChanged":false,"currentContentIdentity":"t3001:cv5","isProgress":false,"affectsCompletion":false,"chapterExists":true}}`

### G54-3 `POST /api/play/reading-g54/position`
- Controller: `:51-61` (javadoc: "Form encoded").
- Auth: token. `@RateLimiter` 120/10 s. Encoding: **form** (query string would also bind; no `@RequestBody`).
- Params: `activityId` Long optional · `topicId` Long required · `chapterId` Long required (>0) · `blockIndex` Integer optional (0..100000) · `scrollRatio` Double optional (0..1) · `audioMs` Long optional (0..86400000) · `audioResourceId` String optional (`^[A-Za-z0-9_-]+$`, ≤64) · `contentIdentity` String required (≤96) · `clientSeq` Long required (0..9007199254740992) · `requestId` String required, **lowercase UUID** (`ReadingPositionRulesG54.java`).
- Success `data`: same keys as G54-2 bookmark (without `chapterExists`) plus `applied` bool — `true` only when the stored `lastRequestId` equals this call's `requestId`; `false` means a position with an equal or higher `clientSeq` was already stored (no-op).
- Errors (`ServiceException`, body `code` = the number): 400 `chapterId 必填` / `requestId 须为小写 UUID` / `clientSeq 必须为非负整数` / `clientSeq 过大` / `blockIndex 越界` / `scrollRatio 须在 0..1` / `audioMs 越界` / `audioResourceId 不合规` / `contentIdentity 必填` / `topicId 必填` · 401 `请先登录` · 404 `章节不属于该主题`, `主题不存在` · entitlement errors pass through (500).
- **Idempotency: `requestId` (lowercase UUID per save) + monotonic `clientSeq`**; row is `ON DUPLICATE KEY UPDATE` guarded by `VALUES(client_seq) > client_seq`. Headers: none. Never writes play progress.
- Example (SYNTHETIC): req (form) `topicId=3001&chapterId=11&blockIndex=4&scrollRatio=0.35&contentIdentity=t3001%3Acv5&clientSeq=13&requestId=7d9e1c2a-5b3f-4a60-9c1d-2e3f4a5b6c7d` → res `{"code":200,"msg":"操作成功","data":{"exists":true,"chapterId":11,"blockIndex":4,"scrollRatio":0.35,"audioMs":null,"audioResourceId":null,"contentIdentity":"t3001:cv5","clientSeq":13,"lastRequestId":"7d9e1c2a-5b3f-4a60-9c1d-2e3f4a5b6c7d","updatedAt":"2026-11-08T10:05:00.000+08:00","contentChanged":false,"currentContentIdentity":"t3001:cv5","isProgress":false,"affectsCompletion":false,"applied":true}}`

---

## G55 — seats / invite / viewer projection

### G55-1 `POST /api/team/seats`
- Controller: `ApiTeamSeatsG55Controller.java:27-42`. Service `TeamSeatsG55Service.project` (`chengyinhub-admin/.../service/play/TeamSeatsG55Service.java`).
- Auth: token (fail-closed: if no member id → body `{code:401,msg:"AUTH_REQUIRED"}`, `:33`). `@RateLimiter` 60/10 s. Encoding: **JSON**, body optional.
- Body: `teamId` number|string · `inviteCode` string. If `inviteCode` is non-blank it wins over `teamId`. At least one is needed or the result is the refusal below.
- Success `data`: `teamId` long · `seats` `{capacity:int, occupied:int, available:int, paidOccupied:int|null, paidTicketMissing:int|null, pendingApplications:int|null}` (the last three are `null` unless the viewer has joined) · `invite` `{mode:"INVITE_ONLY"|"PUBLIC_APPLY", available:bool, expiresAt:Date|null, expired:bool}` · `viewer` `{signedIn:bool, joined:bool, leader:bool, pending:bool, canApply:bool, applyBlockedBy:string|null, canJoinWithCode:bool, joinBlockedBy:string|null}`. Block codes: `NOT_SIGNED_IN, ALREADY_JOINED, APPLY_REJECTED, INVITE_UNAVAILABLE, TEAM_NOT_PUBLIC, APPLY_PENDING, TEAM_UNDER_REVIEW, APPLY_BLOCKED, TICKET_REQUIRED, TEAM_FULL`. `canApply`/`canJoinWithCode` are hints only; the write path decides.
- Errors: 401 above · not visible / not found / wrong code / probe limit → `{code:500,msg:"队伍不存在或无权查看",errorCode:"TEAM_INFO_REFUSED"}` (same answer for all; 20 failed invite-code lookups per viewer per 10 min, in-memory per instance).
- Idempotency: read-only (POST is only for the body). Headers: none.
- Example (SYNTHETIC): req `{"inviteCode":"K7Q2ZD"}` → res `{"code":200,"msg":"操作成功","data":{"teamId":501,"seats":{"capacity":4,"occupied":2,"available":2,"paidOccupied":null,"paidTicketMissing":null,"pendingApplications":null},"invite":{"mode":"INVITE_ONLY","available":true,"expiresAt":"2026-11-09T10:00:00.000+08:00","expired":false},"viewer":{"signedIn":true,"joined":false,"leader":false,"pending":false,"canApply":false,"applyBlockedBy":"TEAM_NOT_PUBLIC","canJoinWithCode":true,"joinBlockedBy":null}}}`

---

## G56 — team leave / hand-over / resync / shared outcome

Base `@RequestMapping("/api/team")` (`ApiTeamHandoverG56Controller.java:18`). Member from token. Errors from `TeamRejectionG56` return `{code:500, msg, errorCode}` via `fail()` (`:79-83`). Unknown `teamId` (null/≤0 → msg `队伍参数有误`, row missing → `队伍不存在`) both use `errorCode:"NOT_IN_TEAM"`.

### G56-1 `GET /api/team/state-g56`
- Controller: `:28-33`. Service `state` (`TeamHandoverG56Service.java`). `@RateLimiter` 120/10 s. Encoding: **form/query**. Param: `teamId` Long required.
- Success `data`: `teamId` · `teamStatus` int (0 recruiting,1 locked,2 started,3 ended,4 disbanded — `TeamNamesG56.java`) · `joinedCount` int · `maxMembers` int · `leaderMemberId` long · `stateVersion` long (epoch ms of `update_time`) · `serverTime` long (epoch ms) · `viewer` `{membership:"PENDING"|"JOINED"|"QUIT"|"KICKED"|"REJECTED"|"WITHDRAWN"|"EXPIRED"|"UNKNOWN", isLeader:bool}`.
- Errors: `NOT_IN_TEAM` (`你不在该队伍中`, or team missing). Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/team/state-g56?teamId=501` → `{"code":200,"msg":"操作成功","data":{"teamId":501,"teamStatus":0,"joinedCount":2,"maxMembers":4,"leaderMemberId":88,"stateVersion":1794000000000,"serverTime":1794000100000,"viewer":{"membership":"JOINED","isLeader":false}}}`

### G56-2 `GET /api/team/leave-impact-g56`
- Controller: `:35-40`. `@RateLimiter` 60/10 s. **form/query**. Param: `teamId` Long required.
- Success `data`: `teamId` · `stateVersion` · `allowed` bool · `outcome` `"DISBAND_LAST"|"HANDOVER_THEN_QUIT"|"QUIT"|null` · `rejectionCode` `"TEAM_STATE_CHANGED"|"LEADER_HANDOVER_FAILED"|null` · `confirmRequired:true` · `effects` string[] (`LEAVE_TEAM`, then `TEAM_DISBANDS` or `SLOT_RELEASED` [+ `LEADERSHIP_TRANSFERS`]) · `successor` `{memberId}` (only when allowed and the viewer is leader) · `duties` `{leaderDuty:bool, storyRoleCode:string|null, hostPermissionDerivedFromLeader:false}`.
- Errors: `NOT_IN_TEAM`. Idempotency: read-only.
- Example (SYNTHETIC): `GET /api/team/leave-impact-g56?teamId=501` → `{"code":200,"msg":"操作成功","data":{"teamId":501,"stateVersion":1794000000000,"allowed":true,"outcome":"QUIT","rejectionCode":null,"confirmRequired":true,"effects":["LEAVE_TEAM","SLOT_RELEASED"],"duties":{"leaderDuty":false,"storyRoleCode":null,"hostPermissionDerivedFromLeader":false}}}`

### G56-3 `POST /api/team/quit-g56`
- Controller: `:43-50`. Service `quit` (`@Transactional`, row lock). `@RateLimiter` 20/10 s. Encoding: **JSON**.
- Body: `teamId` number required · `requestId` string required, **lowercase UUID**.
- Success `data`: `teamId` · `outcome` `"DISBAND_LAST"|"HANDOVER_THEN_QUIT"|"QUIT"` · `newLeaderMemberId` long|null · `replayed` bool.
- Errors (`code 500` + `errorCode`): `REQUEST_ID_INVALID` (`requestId 须为小写 UUID`, or `requestId 已用于其他请求` when reused on another team) · `NOT_IN_TEAM` · `TEAM_STATE_CHANGED` (`队伍状态已变化，请刷新后重试`; also returned for non-mutable team status and a lost DB race) · `LEADER_HANDOVER_FAILED` (`队长移交失败，请刷新后重试`).
- **Idempotency: `requestId`**; receipt table `play_team_leave_receipt_g56` keyed (member, requestId). Replay returns the stored result with `replayed:true`. Headers: none.
- Example (SYNTHETIC): req `{"teamId":501,"requestId":"0b8f6c1e-2a3d-4e5f-9a1b-7c8d9e0f1a2b"}` → res `{"code":200,"msg":"操作成功","data":{"teamId":501,"outcome":"QUIT","newLeaderMemberId":null,"replayed":false}}`

### G56-4 `GET /api/team/shared-outcome-g56`
- Controller: `:52-57`. `@RateLimiter` 60/10 s. **form/query**. Param: `teamId` Long required. Member must be JOINED.
- Success `data`: `scope` `{kind:"TEAM_RUN", teamId, activityId:long|null, windowFrom:long|null (epoch ms), windowTo:long (epoch ms)}` · `participants` `{count:int, scope:"THIS_TEAM", clubTotalIncluded:false}` · `sharedOutcome` `{completedNodeCount:int, membersWithProgress:int}` · `session` `{status, currentChapterId}`|null (column types UNKNOWN) · `needsAttention[]` `{kind:"STATION_PAUSED"|"PENDING_APPLICATIONS", count:int}` (pending only for the leader) · `merchant` `{canOperateMerchantAssets:false, reason:"READ_ONLY_PROJECTION"}`.
- Errors: `NOT_IN_TEAM`. Idempotency: read-only.
- Example (SYNTHETIC): `GET /api/team/shared-outcome-g56?teamId=501` → `{"code":200,"msg":"操作成功","data":{"scope":{"kind":"TEAM_RUN","teamId":501,"activityId":7001,"windowFrom":1793900000000,"windowTo":1794000100000},"participants":{"count":3,"scope":"THIS_TEAM","clubTotalIncluded":false},"sharedOutcome":{"completedNodeCount":5,"membersWithProgress":3},"session":{"status":"RUNNING","currentChapterId":11},"needsAttention":[],"merchant":{"canOperateMerchantAssets":false,"reason":"READ_ONLY_PROJECTION"}}}`

### G56-5 `POST /api/team/handle-g56`
- Controller: `:59-77`. Delegates to `IPlayTeamService.handle` (`PlayTeamServiceImpl.java:218-245`). `@RateLimiter` 30/10 s. Encoding: **JSON**.
- Body: `teamId` number · `memberId` number (the **applicant**; leader is the token) · `approved` bool, or string `"true"`/`"1"` (anything else = false).
- Success: `{"code":200,"msg":"已处理"}` (no `data`).
- Errors: `TeamRejection` → `{code:500, msg, errorCode}`: `APPLY_STATE_CHANGED` (when the legacy code was `APPLY_NOT_PENDING`; the original goes in `legacyErrorCode:"APPLY_NOT_PENDING"`) · `APPLY_BLOCKED` · `TICKET_REQUIRED` · `TEAM_FULL`. Any other `RuntimeException` (e.g. `只有队长可以操作`, `队伍参数有误`) → `{code:500,msg:"操作失败，请稍后重试"}` with **no** `errorCode` (`:74-76`).
- Idempotency: **no requestId**. A second identical call after success answers `APPLY_STATE_CHANGED`. Headers: none.
- Example (SYNTHETIC): req `{"teamId":501,"memberId":120,"approved":true}` → res `{"code":200,"msg":"已处理"}`; stale: `{"code":500,"msg":"申请已处理或已失效","errorCode":"APPLY_STATE_CHANGED","legacyErrorCode":"APPLY_NOT_PENDING"}`

---

## G57 — order / after-sales read facts

Base `@RequestMapping("/api/registration")` (`ApiRegistrationDeliveryG57Controller.java:16`). Both routes: `ResponseEntity<AjaxResult>` with `Cache-Control: no-store` (`:40-42`). Fail-closed: no member → body `{code:401,msg:"AUTH_REQUIRED"}` (`:24,:32`). Read-only, no money.

### G57-1 `POST /api/registration/delivery-g57`
- Controller: `:20-26`. Service `delivery` (`RegistrationDeliveryG57Service.java`). `@RateLimiter` 30/10 s. Encoding: **JSON** (`RegistrationRequest`), body optional.
- Body fields used: `tickets[]` `{ticketId: Long, count?, participateDate?}` (distinct ticketIds, max 20 kept) · or `ticketId` Long (used only when `tickets` yields nothing). Other `RegistrationRequest` fields (`ownerType, ownerId, realName, phone, …, requestId, payChannel`) are accepted but ignored here.
- Success `data`: `ticketCount` int · `mixedTickets` bool · `complete` bool (all requested ids resolved) · `perTicket[]` · `delivery` object|null (the single ticket's entry; null when mixed or none) · `deliveryNote` `"PER_TICKET_TYPE"`|null · `paymentChannels` `{wechat: bool, iap: null}`.
  `perTicket[]`: `ticketId` · `purchaseKind` null · `ticketName` · `teamSize` · `minPeople` · `maxPeople` · `needAudit` bool · `serviceStartAt` Date|null · `serviceEndAt` Date|null · `refundRule` string|null (null = never say refundable) · `beneficiaryKind:"PAYER_SELF"` · `amountFromServer:true`. No amounts.
- Errors: 401 above. Unknown ticket ids are silently dropped (`complete:false`). Idempotency: read-only. Headers: auth only.
- Example (SYNTHETIC): req `{"tickets":[{"ticketId":601,"count":2}]}` → res `{"code":200,"msg":"操作成功","data":{"ticketCount":1,"mixedTickets":false,"complete":true,"perTicket":[{"ticketId":601,"purchaseKind":null,"ticketName":"双人票","teamSize":2,"minPeople":2,"maxPeople":2,"needAudit":false,"serviceStartAt":"2026-11-20T09:00:00.000+08:00","serviceEndAt":"2026-11-20T18:00:00.000+08:00","refundRule":null,"beneficiaryKind":"PAYER_SELF","amountFromServer":true}],"delivery":{"ticketId":601,"…":"(same as perTicket[0])"},"deliveryNote":null,"paymentChannels":{"wechat":true,"iap":null}}}`

### G57-2 `POST /api/registration/order-check-g57`
- Controller: `:28-34`. Service `verify`/`classify`. `@RateLimiter` 60/10 s. Encoding: **form** (`Long id`, no body).
- Params: `id` Long (registration id); null/absent = NOT_FOUND.
- Success `data`: `state` `"QUERYING"|"PAID_CONFIRMED"|"PENDING_CONFIRM"|"CANCELLED"|"EXPIRED"|"FAILED"|"REFUNDED"|"NOT_FOUND"` · `entitlementOpen` bool (true only for `PAID_CONFIRMED`) · `registrationId` long|null · `registrationStatus` int|null · `paymentStatus` int|null · `payExpireTime` Date|null · `recoveryAction` `"REFRESH"|"RETRY_PAY"|"NONE"` · `serverNow` long (epoch ms). Someone else's order and a missing order both answer `NOT_FOUND` with nulls.
- Errors: 401 above. Idempotency: read-only. Headers: auth only.
- Example (SYNTHETIC): `POST /api/registration/order-check-g57` form `id=88001` → `{"code":200,"msg":"操作成功","data":{"state":"PENDING_CONFIRM","entitlementOpen":false,"registrationId":88001,"registrationStatus":1,"paymentStatus":1,"payExpireTime":"2026-11-08T10:15:00.000+08:00","recoveryAction":"REFRESH","serverNow":1794000100000}}`

---

## G58 — post-game projections

Base `@RequestMapping("/api")` (`ApiPostGameReadG58Controller.java:31`). Read-only, personal. Not-logged-in answers `error("请先登录")` (code 500).

### G58-1 `GET /api/refund/impact-g58`
- Controller: `:38-46`. Projector `RefundImpactProjectorG58.project`. `@RateLimiter` 60/10 s. Encoding: **form/query**.
- Params: `sourceType` String required, only `"registration"` accepted · `sourceId` Long required (>0).
- Success `data`: `refundStage` `"NONE"|"APPLIED_PENDING_REVIEW"|"REJECTED"|"APPROVED_PROCESSING"|"PENDING_MANUAL"|"MANUAL_HANDLED_AWAITING_REVIEW"|"COMPLETED"|"UNKNOWN"` (least-finished refund wins) · `amountsComplete` bool (false ⇒ amounts are lower bounds) · `refundPendingAmount` / `refundProcessingAmount` / `refundCompletedAmount` decimal (BigDecimal; JSON number) · `refunds[]` `{refundNo, stage, amount: decimal|null}` · `sourceType` · `sourceId`.
- Errors (500): `请先登录` · `参数不合规` · `订单不存在` (missing or not yours).
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/refund/impact-g58?sourceType=registration&sourceId=88001` → `{"code":200,"msg":"操作成功","data":{"refundStage":"APPROVED_PROCESSING","amountsComplete":true,"refundPendingAmount":0,"refundProcessingAmount":59.00,"refundCompletedAmount":0,"refunds":[{"refundNo":"RF2026110800001","stage":"APPROVED_PROCESSING","amount":59.00}],"sourceType":"registration","sourceId":88001}}`

### G58-2 `GET /api/creator/revenue-g58`
- Controller: `:49-65`. Projector `CreatorRevenueProjectorG58`. `@RateLimiter` 20/10 s. Encoding: **form/query**.
- Params: `from` String `yyyy-MM-dd` optional (default `to − 30 days`) · `to` String `yyyy-MM-dd` optional (default tomorrow, Asia/Shanghai; half-open end). Rule: `from < to` and span ≤ 366 days.
- Success `data` (`revenueState:"AVAILABLE"`): `periodStart` · `periodEnd` (strings) · `ledgerZone:"Asia/Shanghai"` · `revenueBasis:"ACCRUAL_ORIGINAL_LEDGER"` · `receiverBasis:"ORIGINAL_LEDGER_RECEIVER_MEMBER"` · `revenueBasisNote` · `revenueState` · `grossAmount` · `refundedAmount` (negative or 0) · `netAmount` · `entries[]` `{lineType, grossAmount, refundedAmount, netAmount, componentCount}` · `unattributed:null`.
  On read failure (`revenueState:"UNKNOWN"`): only the 6 base keys + `revenueState` + `unavailableReason:"收益暂不可用,请稍后重试"`; **no amount keys**, still `code 200`.
- Errors (500): `请先登录` · `参数不合规`. Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/creator/revenue-g58?from=2026-10-09&to=2026-11-09` → `{"code":200,"msg":"操作成功","data":{"periodStart":"2026-10-09","periodEnd":"2026-11-09","ledgerZone":"Asia/Shanghai","revenueBasis":"ACCRUAL_ORIGINAL_LEDGER","receiverBasis":"ORIGINAL_LEDGER_RECEIVER_MEMBER","revenueBasisNote":"不等于实收,也不等于可提现;到账与可提现以打款事实为准","revenueState":"AVAILABLE","grossAmount":120.00,"refundedAmount":-20.00,"netAmount":100.00,"entries":[{"lineType":"TICKET","grossAmount":120.00,"refundedAmount":-20.00,"netAmount":100.00,"componentCount":4}],"unattributed":null}}`

### G58-3 `GET /api/topic/post-game-outcome-g58`
- Controller: `:68-89`. Projector `PostGameOutcomeProjectorG58.project`. `@RateLimiter` 10/10 s. Encoding: **form/query**.
- Auth: token, owner of the topic (`scope=MERCHANT` supported). Params: `topicId` Long required · `windowDays` Integer optional (default 30, 1..365) · `scope` optional.
- Success `data`: `topicId` · `windowDays` · `retentionBasis:"SAME_TOPIC_DISTINCT_PARENT_ORDER_WITHIN_WINDOW"` · `cohortMembers` int · `matureMembers` int · `mature` bool · `retainedMembers` int|null · `retentionRate` decimal(4 dp)|null · `free` / `paid` each `{cohortMembers, matureMembers, retainedMembers|null, retentionRate|null}` · `excludedRegistrations` int · `clickRate` null · `clickRateBasis:"UNAVAILABLE_NO_SERVER_EVENT"` · `sourceWatermarks` string|null (ISO instant) · `basisVersion:"g58-postgame-1"` · `computedAt` string (ISO instant) · `historicalReplayable:false` · `testExclusionBasis:"NO_SERVER_MARKER"` · `dedupeScope:"SERVER_REGISTRATIONS_ONLY"`.
- Errors (500): `参数不合规` · `请先登录` · `主题不存在` · `无权操作该主题` · `统计暂不可用,请稍后重试` (read failure, never zeros). Invalid `scope` value → code 400.
- Idempotency: read-only. Headers: none.
- Example (SYNTHETIC): `GET /api/topic/post-game-outcome-g58?topicId=3001&windowDays=30` → `{"code":200,"msg":"操作成功","data":{"topicId":3001,"windowDays":30,"retentionBasis":"SAME_TOPIC_DISTINCT_PARENT_ORDER_WITHIN_WINDOW","cohortMembers":40,"matureMembers":25,"mature":false,"retainedMembers":6,"retentionRate":0.2400,"free":{"cohortMembers":10,"matureMembers":6,"retainedMembers":1,"retentionRate":0.1667},"paid":{"cohortMembers":30,"matureMembers":19,"retainedMembers":5,"retentionRate":0.2632},"excludedRegistrations":3,"clickRate":null,"clickRateBasis":"UNAVAILABLE_NO_SERVER_EVENT","sourceWatermarks":"2026-11-07T12:00:00Z","basisVersion":"g58-postgame-1","computedAt":"2026-11-08T02:00:00Z","historicalReplayable":false,"testExclusionBasis":"NO_SERVER_MARKER","dedupeScope":"SERVER_REGISTRATIONS_ONLY"}}`

### G58-4 `GET /api/leaderboard/rank-basis-g58`
- Controller: `:92-102`. `@RateLimiter` 60/10 s. Encoding: none (no params). Token required.
- Success `data` (constants, `:96-100`): `readsScore:false` · `branchOrPersonal:"ENDING_REACHED_FIRST_THEN_SHORTER_TOTAL_TIME"` · `linear:"MORE_NODES_FIRST_THEN_EARLIER_LAST_COMPLETION"` · `ties:"SAME_RANK_1_1_3"` · `hintsAffectRank:false`.
- Errors: none from the code beyond the common ones. Idempotency: read-only.
- Example (SYNTHETIC): `GET /api/leaderboard/rank-basis-g58` → `{"code":200,"msg":"操作成功","data":{"readsScore":false,"branchOrPersonal":"ENDING_REACHED_FIRST_THEN_SHORTER_TOTAL_TIME","linear":"MORE_NODES_FIRST_THEN_EARLIER_LAST_COMPLETION","ties":"SAME_RANK_1_1_3","hintsAffectRank":false}}`

---

## 2. Summary grid

| # | Group | Method | Path | Auth | Enc | Idempotency | iOS caller |
|---|---|---|---|---|---|---|---|
| 1 | G49 | POST | /api/template/topic-template/adoption-info | token | form | read | NONE |
| 2 | G50 | GET | /api/template/topic-template/location-todos-g50 | token+owner | query | read | NONE |
| 3 | G50 | POST | /api/template/topic-template/location-reconfirm-g50 | token+owner | JSON (+`scope` query) | `requestId` | NONE |
| 4 | G51 | POST | /api/template/topic-template/source-g51/adoption/record | token+owner | JSON | adopted-topic keyed | NONE |
| 5 | G51 | GET | /api/template/topic-template/source-g51/adoption | token+owner | query | read | NONE |
| 6 | G51 | POST | /api/template/topic-template/source-g51/credits/save | token+owner | JSON | whole-set replace | NONE |
| 7 | G51 | GET | /api/template/topic-template/source-g51/credits | token | query | read | NONE |
| 8 | G51 | GET | /api/template/topic-template/source-g51/preview | token | query | read | NONE |
| 9 | G52 | GET | /api/topic/publish-result-g52 | token+owner | query | read | NONE |
| 10 | G52 | GET | /api/topic/my-projects-status-g52 | token+owner | query | read | NONE |
| 11 | G53 | GET | /api/play/node-closure | token | query | read | NONE |
| 12 | G54 | GET | /api/play/reading-g54/manifest | token+entitlement | query | read | NONE |
| 13 | G54 | GET | /api/play/reading-g54/position | token+entitlement | query | read | NONE |
| 14 | G54 | POST | /api/play/reading-g54/position | token+entitlement | form | `requestId` + `clientSeq` | NONE |
| 15 | G55 | POST | /api/team/seats | token | JSON | read | NONE |
| 16 | G56 | GET | /api/team/state-g56 | token+member | query | read | NONE |
| 17 | G56 | GET | /api/team/leave-impact-g56 | token+member | query | read | NONE |
| 18 | G56 | POST | /api/team/quit-g56 | token+member | JSON | `requestId` | NONE |
| 19 | G56 | GET | /api/team/shared-outcome-g56 | token+member | query | read | NONE |
| 20 | G56 | POST | /api/team/handle-g56 | token+leader | JSON | none | NONE |
| 21 | G57 | POST | /api/registration/delivery-g57 | token | JSON | read | NONE |
| 22 | G57 | POST | /api/registration/order-check-g57 | token+owner | form | read | NONE |
| 23 | G58 | GET | /api/refund/impact-g58 | token+owner | query | read | NONE |
| 24 | G58 | GET | /api/creator/revenue-g58 | token | query | read | NONE |
| 25 | G58 | GET | /api/topic/post-game-outcome-g58 | token+owner | query | read | NONE |
| 26 | G58 | GET | /api/leaderboard/rank-basis-g58 | token | none | read | NONE |

## 3. UNKNOWN list

- Exact string format of `Date` fields (G54 `updatedAt`, G55 `invite.expiresAt`, G57 `serviceStartAt/EndAt/payExpireTime`) and `adoptedAt` (G51): not run live.
- Whether null map values are serialized as `null` or dropped: no override found, assumed `null`.
- Message text of `entry.nodes()` failures (G54) and of missing/malformed-parameter errors (G53 and any `@RequestBody` route).
- Column types for `templateStatus/evidenceLevel/isOfficial` (G49), `session.status/currentChapterId` (G56), `TopicTemplateDetailVO` scalars (G51 preview), `LocationTodoLogicG50.reason()` strings.
- `TemplateAdoptionPolicyG49.INTENT_KEEP/INTENT_SWITCH` literal values (not read).
- `HttpStatus` of business errors on the wire (inferred 200).
- Whether `GlobalExceptionHandler` maps `ServiceException` with `code==null` to 500 (`:134-146` branches on `code`; null path not read).
