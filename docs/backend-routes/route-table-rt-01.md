# Route table rt-01 (groups G01-G12)

Source: static read of `origin/claude/be-v2-fixes` (537e43c74). Not run against a live server: this is a static contract. iOS callers from `origin/wip/wave5-build` (3f4f6053). All JSON examples are SYNTHETIC (derived from code, not captured). UNKNOWN = not determinable from code. Parts are by group range; each part has a summary table and per-route detail.

Cross-cutting findings (from the parts below):
- G01 `main-line`/`environment` read `app_mauth_g01_release`, but G02 writes `merchant_authoring_release_g02`; G02 publish returns 503 until something implements `AuthoringDraftSourceG02`.
- G06/G07 City adapters and 3 G02 city-value routes are UNREGISTERED (404 today); G03 city-value `result` returns 503 (no host bean).
- `/api/merchant/insight` has no mapping; real route is `POST /api/ai/merchant/insight`.
- Reward-pledge routes live partly in `ApiRewardPledgeG19Controller` (not G10) and are absent unless `chengyin.pledge-v1.enabled=true`.
- G08/G09 POSTs reject unknown body keys with 400 (iOS `source_*` fields would be rejected); `ApiFriendG22Controller` exists on the branch and was not read.
- `/api/workshop/purchased/*` has no route on this branch; `/api/topic/attribute-author` routes exist but are not live.


---

# Route table, groups G01-G03

Source: /home/user/chengyin @ cloud/rt-01 (= origin/claude/be-v2-fixes). iOS: /home/user/ios-w5 @ origin/wip/wave5-build (3f4f6053). Static reading only; nothing compiled or run.
Controller dir `C/` = `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`. System dir `S/` = `chengyinhub-system/src/main/java/com/chengyinhub/business/`.

## Common facts (apply to every route unless a row says otherwise)

- Envelope: `AjaxResult` = JSON map `{"code":int,"msg":string,"data":any?, ...extra}`. Success = `code 200`, `msg "操作成功"`, `data` (AjaxResult.java success()).
- HTTP status: all routes except city-value `result` and CRM `download` return HTTP 200 even for business failure; the failure is in body `code`. `ServiceException(msg,code)` is turned into `{"code":code,"msg":msg}` by `GlobalExceptionHandler.handleServiceException` (framework/.../GlobalExceptionHandler.java:130-142, no `@ResponseStatus`). `msg` passes through `UserSafeMessage.of` (technical text replaced by a generic phrase).
- Auth gate: `SecurityConfig.java:166` `anyRequest().authenticated()`. None of the paths in G01-G03 is in any permitAll list (checked lines 117-163). So every route needs a valid app token (JWT filter). Body of the not-logged-in rejection from the filter chain: UNKNOWN (entry point not read in full). Guest allowed: NO for all routes.
- `getAppUserId()` = `SecurityUtils.getLoginAppUser().getAppUser().getUserId()` (BaseController.java:222).
- Business codes are "HTTP-like" numbers in body `code`; `errorCode` (string) exists only where stated.
- All three G01/G02/G03 backends were never compiled (per reports); this file records what the source says, not what runs.
- Feature flags: only G01 writes (`merchant.authoring.g01.writes-enabled`, default false => code 503) and city-value (`enabled` default false => 503 `CITY_VALUE_REPORT_DISABLED`) have flags. No others found in .yml/.properties (grep returned nothing; the flag defaults live in `@Value` defaults).
- DB tables for G01/G02/G03 come from `chengyinhub-admin/sql/migration_g0{1,2,3}_20261108.sql` (not run by this task).

## Summary table

| # | Grp | Method | Full path | Controller:line | Auth | Encoding | Flag (default) | iOS caller | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | G01 | GET | /api/merchant/authoring/drafts | C/ApiMerchantAuthoringG01Controller.java:19 | token | none | none | Core/MerchantAuthoringService.swift:192 | registered |
| 2 | G01 | POST | /api/merchant/authoring/drafts | ...G01Controller.java:20 | token | JSON | writes-enabled=false => 503 | MerchantAuthoringService.swift:204 | registered |
| 3 | G01 | GET | /api/merchant/authoring/drafts/{draftId} | ...G01Controller.java:21 | token | path | none | MerchantAuthoringService.swift:272 | registered |
| 4 | G01 | POST | /api/merchant/authoring/drafts/{draftId} | ...G01Controller.java:22 | token | JSON | writes-enabled=false => 503 | MerchantAuthoringService.swift:238 | registered |
| 5 | G01 | POST | /api/merchant/authoring/jobs | ...G01Controller.java:26 | token | JSON | writes-enabled=false => 503 | MerchantAuthoringService.swift:214 | registered |
| 6 | G01 | GET | /api/merchant/authoring/jobs | ...G01Controller.java:27 | token | query | none | MerchantAuthoringService.swift:363 | registered |
| 7 | G01 | POST | /api/merchant/authoring/jobs/cancel | ...G01Controller.java:28 | token | JSON | none (not gated by flag) | MerchantAuthoringService.swift:226 | registered |
| 8 | G01 | GET | /api/merchant/authoring/main-line | ...G01Controller.java:30 | token | query | none | MerchantAuthoringService.swift:298 | registered |
| 9 | G01 | GET | /api/merchant/authoring/environment | ...G01Controller.java:34 | token | query | provider property empty | MerchantAuthoringService.swift:310 | registered |
| 10 | G01 | POST | /api/merchant/authoring/draft-selection/list | ...G01Controller.java:41 | token | JSON (body optional) | none | Core/ProjectMerchantDraftClient.swift:44 | registered |
| 11 | G01 | POST | /api/merchant/authoring/draft-selection/resolve | ...G01Controller.java:42 | token | JSON | none | Core/ProjectMerchantDraftClient.swift:49 | registered |
| 12 | G02 | POST | /api/merchant/authoring/releases | C/ApiMerchantAuthoringReleaseG02Controller.java:29 | token + merchant PROJECT_MANAGE | JSON | none; fails 503 if no AuthoringDraftSourceG02 bean (none exists) | MerchantAuthoringService.swift:265 | registered, functionally dead |
| 13 | G02 | GET | /api/merchant/authoring/releases | ...G02Controller.java:35 | token + PROJECT_MANAGE | query | none | MerchantAuthoringService.swift:378 | registered |
| 14 | G02 | POST | /api/merchant/authoring/releases/{id}/withdraw | ...G02Controller.java:41 | token + PROJECT_MANAGE | JSON optional | none | NONE (route builder `MerchantAuthoringRoute.withdraw` defined at MerchantAuthoringService.swift:23, no call site) | registered |
| 15 | G02 | GET | /api/merchant/authoring/public | ...G02Controller.java:46 | token (any member) | query | none | MerchantAuthoringService.swift:286 | registered |
| 16 | G02 | GET | /api/merchant/authoring/player/{merchantId}/game | ...G02Controller.java:54 | token (any member) | path | none | Core/MerchantGamePlayer.swift:79 | registered |
| 17 | G02 | GET | /api/merchant/authoring/player/{merchantId}/requests/{requestId} | ...G02Controller.java:61 | token (any member) | path | none | Core/MerchantGamePlayer.swift:99 | registered |
| 18 | G02 | GET | /api/merchant/city-value/report | C/CityValueReportMVCAdapter.java:12 | n/a | query | disabled | Core/CityMerchantValueService.swift:51 | UNREGISTERED |
| 19 | G02 | GET | /api/merchant/city-value/events | C/CityValueReportMVCAdapter.java:13 | n/a | query | disabled | Core/CityMerchantValueService.swift:61 | UNREGISTERED |
| 20 | G02 | GET | /api/merchant/city-value/event/{id}/benefit | C/CityValueReportMVCAdapter.java:14 | n/a | query | disabled | Core/CityMerchantValueService.swift:57 | UNREGISTERED |
| 21 | G03 | GET | /api/merchant/city-value/result/{id} | C/ApiCityValueResultG03Controller.java:192 | token + merchant (inside host) | query | host bean absent => 503 | Core/CityMerchantValueService.swift:53 | registered, functionally 503 |
| 22 | G03 | POST | /api/merchant/crm/customers/{customerMemberId}/detail | C/ApiMerchantCrmController.java:173 | token + CRM_READ | none | none | Core/MerchantBusinessQuery.swift:77 ; MerchantEngagementContracts.swift:138 | registered |
| 23 | G03 | POST | /api/merchant/crm/customers/{customerMemberId}/contact | C/ApiMerchantCrmController.java:182 | token + CRM_SENSITIVE_READ | JSON | none | Core/MerchantEngagementContracts.swift:194 | registered |
| 24 | G03 | POST | /api/merchant/crm/exports/{taskId}/status | C/ApiMerchantCrmController.java:279 | token + CRM_EXPORT | none (empty `{}`) | none | Core/MerchantEngagementContracts.swift:137 | registered |
| 25 | G03 | GET | /api/merchant/crm/exports/{taskId}/download | C/ApiMerchantCrmController.java:288 | token + CRM_EXPORT + header token | header | none | Core/MerchantEngagementContracts.swift:195 ; MerchantEngagementService.swift:109 | registered |
| 26 | G03 | POST | /api/ai/merchant/insight (iOS group path /api/merchant/insight does NOT exist) | C/ApiAiController.java:404 | token + MARKETING_READ | none | none | Core/MerchantMarketingService.swift:140 (correct path); wrong-path constant at MerchantAndPublishAuthoringAudit.swift:119 and MerchantDecorAndShopApplyWizardAudit.swift:23 | registered |
| 27 | G03 | POST | /api/merchant/npc/avatar/generate | C/ApiMerchantNpcAssetG03Controller.java:130 | token + merchant PROFILE_WRITE | JSON | none | Core/MerchantNPCHTTP.swift:89 | registered |
| 28 | G03 | POST | /api/merchant/npc/avatar/status | ...NpcAssetG03Controller.java:125 | token + PROFILE_WRITE | none (iOS sends `{}`) | none | Core/MerchantOperationsService.swift:122 | registered |
| 29 | G03 | POST | /api/merchant/npc/knowledge-review | ...NpcAssetG03Controller.java:137 | token + PROFILE_WRITE | JSON | none | Core/MerchantNPCKnowledgeReviewWriter.swift:215 (builder; body fields at :202-208) | registered |
| 30 | G03 | GET | /api/merchant/npc/knowledge-review/request | ...NpcAssetG03Controller.java:144 | token + PROFILE_WRITE | query | none | Core/MerchantNPCKnowledgeReviewWriter.swift:240-249 | registered |

Registered controller routes: 27. UNREGISTERED (adapter, no `@RestController`/mapping): 3 (rows 18-20). Total rows: 30.

---

## G01 detail (service: S/service/support/MerchantAuthoringServiceG01.java, rules: MerchantAuthoringRulesG01.java, SQL: chengyinhub-system/src/main/resources/mapper/business/MerchantAuthoringG01Mapper.xml)

Shared G01 rules
- `requestId` must be a canonical 36-char UUID (Rules:30-33). `draftId` = `^[A-Za-z0-9_-]{1,64}$` (Rules:26). Invalid => `ServiceException 400` ("requestId 无效" / "draftId 无效" / "请求格式无效").
- Write gate: `requireWrites()` throws `ServiceException("商家创作写入未开启",503)` unless property `merchant.authoring.g01.writes-enabled=true` (Service:257, default false at Service:24).
- `ownedMerchant(member)`: no member => 401 "请先登录"; no row in `mms_merchant` with `member_id=? AND status=1 AND del_flag=0` => 403 "请先完成商家入驻" (Service:205-210, Mapper.xml ownedMerchantId). This is the ONLY ownership check: it is a plain owner row; it does NOT use IMerchantAccessService, so operators (staff) get 403 here while G02/G03 allow them.
- Not-found and not-owned draft both => 404 "草稿不存在" (Service:216).
- No `errorCode` field is emitted by any G01 route (only `code`+`msg`).
- Idempotency is by `requestId` (see each route). No header requirements.

### 1. GET /api/merchant/authoring/drafts
- Params: none. Auth: token; owner merchant (403 else).
- Success `data`: `{"drafts":[{"draftId":string,"currentVersion":int,"merchantId":long|null,"publishOutcome":string}]}`; up to 100, ordered update_time DESC (Mapper listDrafts). `publishOutcome` is `NONE|PUBLISHED|WITHDRAWN` per column comment; nothing in this repo writes PUBLISHED/WITHDRAWN to it (column "written by the release module"; G02 writes a different table).
- Errors: 401/403 above.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"drafts":[{"draftId":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","currentVersion":0,"merchantId":42,"publishOutcome":"NONE"}]}}`

### 2. POST /api/merchant/authoring/drafts (create)
- Body JSON (fastjson2 JSONObject, required): `requestId` string UUID (required, becomes the draftId); `templateId` string 1-64 (required); `themeId` long (optional); `skuId` long (optional); `scene` string <=32 (optional, default "").
- Idempotency: `INSERT IGNORE` keyed by draft_id then `SELECT ... FOR UPDATE`; replay with same owner+templateId+themeId returns the first result; otherwise `409 "原请求号对应的内容不一致"` (Service:52-54). Note `skuId`/`scene` are not part of the comparison.
- Success `data` (draftRevision): `{"draftId":string,"currentVersion":int,"version":int,"bodyHash":string,"themeId":long?}` (`themeId` only when non-null). New draft: currentVersion 0, bodyHash "" (column defaults).
- Errors: 503 writes off; 401; 403; 400 "requestId 无效" / "templateId 无效" / "scene 无效"; 409 as above.
- SYNTHETIC request: `{"requestId":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","templateId":"7","themeId":5,"scene":"cafe"}`
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"draftId":"3F2504E0-4F89-41D3-9A0C-0305E82C3301","currentVersion":0,"version":0,"bodyHash":"","themeId":5}}`

### 3. GET /api/merchant/authoring/drafts/{draftId}
- Path: `draftId`. Success `data`: same draftRevision shape as route 2 (body JSON is NOT returned, only hash+version). Errors: 400 invalid id; 404 not found/not owned; 401.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"draftId":"3F25...3301","currentVersion":2,"version":2,"bodyHash":"<64 hex sha256>"}}`

### 4. POST /api/merchant/authoring/drafts/{draftId} (save)
- Body JSON: `expectedVersion` int >=0 (required); `body` JSON object (required, must be a Map).
- Server strips keys `approved, merchantFactsApproval, themeContentApproval, stage` recursively, sorts keys, hashes SHA-256 of the canonical JSON (Rules:40-54). Body containing the quoted tokens `"NEW_ROUTE"`, `"TIME_LIMIT"`, `"CASH"`, `"PRIZE"`, `"STOCK_PROMISE"` => 422 "包含不允许的效果" (Service:69). Canonical body > 65536 bytes => 400 "内容过大".
- Idempotency: replay of a lost response (`current == expected+1 && sameHash`) returns the current revision (Service:75); a stale `expectedVersion` => `UPDATE ... WHERE current_version=expected` affects 0 rows => 409 "版本冲突" (Service:76). Version +1 per save.
- Success `data`: draftRevision (route 2 shape) with new `currentVersion`.
- Errors: 503 writes off; 400 (invalid id/format/size); 404; 409; 422; 401.
- SYNTHETIC request: `{"expectedVersion":0,"body":{"canonical_plot":"...","approved_branches":["a"]}}`
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"draftId":"3F25...3301","currentVersion":1,"version":1,"bodyHash":"<sha256>"}}`

### 5. POST /api/merchant/authoring/jobs
- Body JSON: `requestId` UUID (required); `draftId` (required); `templateId`, `themeId` (long), `scene` (all optional, hashed only).
- Behaviour: records a `QUEUED` row only (insert ignore on `(owner_member_id, request_id)`); NO model call (Service:81-93). Draft must be owned (404 else). Does not use `ownedMerchant`, so no 403.
- Idempotency: replay with same hash returns the stored job; different hash => 409 "原请求号对应的内容不一致". Hash = sha256(draftId\ntemplateId\nthemeId\nscene).
- Success `data`: `{"requestId":string,"draftId":string,"outcome":"QUEUED|SUCCEEDED|FAILED|CANCELLED","errorCode":string?}` (`errorCode` only when set). Nothing in repo moves a job past QUEUED.
- Errors: 503 writes off; 400; 404; 409; 401.
- SYNTHETIC request: `{"requestId":"9B2E...","draftId":"3F25...3301","templateId":"7","themeId":5,"scene":"cafe"}`
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"requestId":"9B2E...","draftId":"3F25...3301","outcome":"QUEUED"}}`

### 6. GET /api/merchant/authoring/jobs?requestId=
- Query: `requestId` (required, String; Spring 400 if absent, handler shape UNKNOWN). Success `data`: jobView as route 5. Errors: 400 invalid UUID; 404 "任务不存在"; 401.

### 7. POST /api/merchant/authoring/jobs/cancel
- Body JSON: `requestId` (UUID). NPE-risk: `body` is not `required=false`, so empty body => Spring 400 (shape UNKNOWN). Cancel updates only when outcome=QUEUED, else leaves unchanged; always returns current jobView (Service:102-109). Not gated by the write flag. Errors: 400; 404; 401.
- SYNTHETIC request: `{"requestId":"9B2E..."}`; response: `{"code":200,"msg":"操作成功","data":{"requestId":"9B2E...","draftId":"3F25...","outcome":"CANCELLED"}}`

### 8. GET /api/merchant/authoring/main-line?merchantId=&themeId=
- Query: `merchantId` long (required), `themeId` long (optional). Any logged-in member can read any merchant (no ownership check: `getAppUserId()` only, Controller:31).
- Reads table `app_mauth_g01_release` (Mapper latestRelease) which NO code in the repo writes (G02 writes `merchant_authoring_release_g02`). So today it always returns the NONE branch.
- Success `data`: no release => `{"outcome":"NONE"}` (code 200); release => `{"outcome":"PUBLISHED","releaseId":long,"facts":{<subset of 13 public keys>}}`.
- Errors: 401 only.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"outcome":"NONE"}}`

### 9. GET /api/merchant/authoring/environment?releaseId=
- Query `releaseId` long required. Success `data`: `{"provider":string,"action":"NONE","branch":null}`; `provider` = property `merchant.authoring.g01.environment-provider` (default ""). Release must exist in `app_mauth_g01_release` with outcome PUBLISHED else `404 "发布不存在"` (always 404 today for the reason in route 8). Errors: 404; 401.
- SYNTHETIC response (if a release row existed): `{"code":200,"msg":"操作成功","data":{"provider":"","action":"NONE","branch":null}}`

### 10. POST /api/merchant/authoring/draft-selection/list
- Body JSON optional: `beforeSourceId` long >0 (cursor). Owner merchant required (403). 20 per page, `cms_member_template` of the caller, id DESC.
- Success `data`: `{"profile":"MERCHANT_AUTHORING_DRAFT_SELECTION_PAGE_V1","ownerMemberId":long,"merchantRowId":long,"templateIdNamespace":"CMS_MEMBER_TEMPLATE","currentness":"PAGE_CURRENT_NOT_SNAPSHOT","merchantFactsFreshness":"HISTORICAL_INPUT_ONLY","approvalProof":false,"usageRightsProof":false,"publicationAuthority":false,"rows":[{"sourceId":long,"memberTemplateId":long,"state":"READY","source":{"kind":"MERCHANT_AI_TEMPLATE_SOURCE_V1","sourceId":long,"sourceVersion":1,"contentHash":string},"templateTitle":string(<=256),"templateContentHash":string}],"nextBeforeSourceId":long|null}`. `nextBeforeSourceId` non-null only when exactly 20 rows returned.
- Errors: 400 "beforeSourceId 无效"; 401; 403.
- SYNTHETIC request: `{"beforeSourceId":120}`

### 11. POST /api/merchant/authoring/draft-selection/resolve
- Body JSON: `memberTemplateId` long >0 (required), `templateContentHash` string (required). Success `data`: same common fields as route 10 with `profile "MERCHANT_AUTHORING_DRAFT_SELECTION_RESOLVE_V1"`, `currentness "CURRENT_AT_READ_ONLY"`, and `row` (single row object as above) instead of `rows`.
- Errors: 400 "请求格式无效"; 404 "模板不存在或无权使用"; 409 "模板内容已变化" (hash mismatch); 401; 403.
- SYNTHETIC request: `{"memberTemplateId":7,"templateContentHash":"<64 hex>"}`

---

## G02 detail (service impl: S/service/impl/MerchantAuthoringReleaseG02ServiceImpl.java, outcome: S/service/support/AuthoringOutcomeG02.java, SQL: MerchantAuthoringReleaseG02Mapper.xml)

Shared G02 rules
- Error path: `wrap()` => `AjaxResult.error(status,message)` plus `errorCode` string (Controller:78-86). HTTP status still 200; `code` in body.
- `owner(member)` = `IMerchantAccessService.require(member, PROJECT_MANAGE)`; any RuntimeException => null => 403 FORBIDDEN (Impl:43-48). Merchant id comes from the access context, never from the request.
- Routes 15-17 only call `getAppUserId()` (any logged-in member may read any merchant).
- UUID check regex `UUID_RE` (Impl:30); `draftId` regex `^[A-Za-z0-9_-]{1,64}$`.
- Release `outcome` strings: `PUBLISHED` / `WITHDRAWN` (domain MerchantAuthoringReleaseG02.java:7-8).
- No feature flag.
- Facts are limited to the 13 public keys: store_knowledge, service_information, canonical_plot, allowed_variables, approved_branches, accessibility_alternative, offline_alternative, fail_exit, business_segment, duration_minutes, headcount, noise_limit, photo_limit.

### 12. POST /api/merchant/authoring/releases (publish)
- Body JSON (Map): `requestId` UUID, `draftId` string, `version` int >=1 (all required; a missing/invalid field => 400 INVALID_REQUEST).
- Flow: validate -> owner (403) -> existing release for (merchant, requestId)? replay (hash = sha256(draftId|version); mismatch => 409 REQUEST_ID_REUSED) -> `ObjectProvider<AuthoringDraftSourceG02>.getIfAvailable()`; none => 503 DRAFT_SOURCE_UNAVAILABLE -> draft null => 404 DRAFT_NOT_FOUND -> version differs => 409 VERSION_CONFLICT -> approvals missing => 409 REVIEW_REQUIRED -> no public facts => 409 EMPTY_FACTS -> insert. Race on unique key falls back to replay.
- DISCREPANCY/UNWIRED: the only references to `AuthoringDraftSourceG02` are the interface, the service, and a test; no `@Component` implements it. So in production this route always answers 503 DRAFT_SOURCE_UNAVAILABLE for a new requestId. It is also not connected to the G01 draft table.
- Success `data` (releaseView with facts): `{"outcome":"PUBLISHED","releaseId":long,"merchantId":long,"draftId":string,"version":int,"requestId":string,"themeId":long?,"facts":{...}}`.
- Idempotency key: `requestId` unique per (merchant_id, request_id). 
- SYNTHETIC request: `{"requestId":"A1B2C3D4-0000-4000-8000-000000000001","draftId":"3F25...3301","version":1}`
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"outcome":"PUBLISHED","releaseId":9,"merchantId":42,"draftId":"3F25...3301","version":1,"requestId":"A1B2C3D4-...0001","facts":{"canonical_plot":"..."}}}`; error: `{"code":503,"msg":"Draft store unavailable","errorCode":"DRAFT_SOURCE_UNAVAILABLE"}`

### 13. GET /api/merchant/authoring/releases?requestId=
- Query `requestId` (optional in mapping, but null/invalid => 400 INVALID_REQUEST). Owner required (403). Not found => 404 NOT_FOUND. Success `data`: releaseView (with `facts` only while PUBLISHED; WITHDRAWN rows omit `facts`).
- Note: path is the same string as route 12, differing by method.

### 14. POST /api/merchant/authoring/releases/{id}/withdraw
- Path `id` long >0; body optional `{"requestId":UUID}` (invalid UUID => 400). Owner required. Row looked up by (merchant, id); none => 404 NOT_FOUND. If PUBLISHED => mapper.withdraw then re-read; if already WITHDRAWN => idempotent success. Success `data`: releaseView without facts: `{"outcome":"WITHDRAWN","releaseId":..,"merchantId":..,"draftId":..,"version":..,"requestId":..,"themeId"?}`.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"outcome":"WITHDRAWN","releaseId":9,"merchantId":42,"draftId":"3F25...","version":1,"requestId":"A1B2..."}}`

### 15. GET /api/merchant/authoring/public
- Query: `merchantId` long (required), `themeId` long?, `releaseId` long?, `binding` string (required non-empty, <=128 enforced by service), `runId` string? (<=64). `binding`/`runId` are validated and discarded.
- Errors: 400 INVALID_REQUEST; 404 NOT_FOUND (no row); 404 NOT_PUBLISHED (latest matched row is withdrawn). Success `data`: releaseView with facts.
- SYNTHETIC request: `GET /api/merchant/authoring/public?merchantId=42&binding=x`

### 16. GET /api/merchant/authoring/player/{merchantId}/game
- Path `merchantId` long >0 else 400. Success `data`: no row => `{"merchantId":L,"outcome":"NONE"}`; withdrawn => `{"merchantId":L,"outcome":"WITHDRAWN","releaseId":L}`; published => `{"merchantId":L,"outcome":"PUBLISHED","releaseId":L,"revisionVersion":int,"facts":{...}}`.
- This duplicate path was removed from the G01 controller (G01Controller.java:37-39 comment); G01 service still has `playerGame`/`playerRequest` unused (reading `app_mauth_g01_*`).
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"merchantId":42,"outcome":"NONE"}}`

### 17. GET /api/merchant/authoring/player/{merchantId}/requests/{requestId}
- Path `merchantId` long, `requestId` string. Calls `NpcChatService.readOriginalRequest("merchant", merchantId, requestId, userId)` (S/service/impl/NpcChatService.java:660); null or `outcomeStatus == "NOT_FOUND"` => `{"code":404,"msg":"Not found","errorCode":"NOT_FOUND"}`.
- Success `data`: `{"merchantId":long,"requestId":string,"outcomeStatus":string,"safetyDecision":string,"safeText":string,"errorCode":string|null,"retryable":bool,"ai":bool}`. Other outcomeStatus values are whatever NpcChatService emits (PROCESSING/SUCCEEDED/FAILED/REJECTED per the G01 table comment; not enumerated here: UNKNOWN beyond `NOT_FOUND`).
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"merchantId":42,"requestId":"...","outcomeStatus":"SUCCEEDED","safetyDecision":"PASS","safeText":"...","errorCode":null,"retryable":false,"ai":true}}`

### 18-20. city-value report / events / event/{id}/benefit (UNREGISTERED)
- `C/CityValueReportMVCAdapter.java` is a `public final class` with header comment "deliberately no route or controller annotations"; methods `report(HttpServletRequest,Map)`, `events(...)`, `benefit(request,id,Map)` call `CityValueReportAPIHost.read(request,"report"|"events"|"benefit",...)`. No Spring mapping exists for them anywhere (grep for "city-value" in controllers finds only `ApiCityValueResultG03Controller`). Calling the URLs gives the framework 404 "请求路径不存在".
- Would be GET if wired (per be-g02 report and iOS); required query keys when wired, from CityValueReportExecution.java: report = exactly `{requestId,regionId,boardId,seasonId,rulesReleaseId,from,to}` (from/to ISO-8601 Instant; requestId via CityBoardDraftDocument.isId); events = exactly `{regionId,boardId,seasonId,rulesReleaseId,from,to,cursor}`; benefit = exactly `{regionId,boardId,seasonId,rulesReleaseId,from,to,snapshotId}` + path id. Any other key set => 400 MISSING_PARAM. Request-id idempotency: report derives `mv_`+sha256(actor\nmerchant\nrequestId).
- iOS callers (these will 404 today): CityMerchantValueService.swift:51 (report), :61 (events), :57 (benefit).
- Response shape: UNKNOWN (built by CityValueReportSource, not read).

---

## G03 detail

### 21. GET /api/merchant/city-value/result/{id}
- Controller: `ApiCityValueResultG03Controller` (C/ line 187-202), `@RequestMapping(CityValueReportMVCAdapter.BASE="/api/merchant/city-value")`, `@GetMapping("/result/{id}")`. Not extending BaseController; returns `ResponseEntity<AjaxResult>` so the HTTP status is real here.
- Host: `@Autowired(required=false) CityValueReportAPIHost host`. A repo-wide grep finds no `@Bean`/`@Component` that creates it (only `CityValueReportAssembly.closed(...)` static factory at framework/.../CityValueReportAssembly.java:8, never called). So `host==null` => HTTP 503, body `{"code":503,"msg":"Disabled","errorCode":"CITY_VALUE_REPORT_DISABLED"}`; `id<=0` (with a host) => 400 `MISSING_PARAM`.
- If a host were wired: `CityValueReportAPIHost.read` (framework/.../CityValueReportAPIHost.java:12): `enabled` default false => 503 CITY_VALUE_REPORT_DISABLED; token captured from the request via `CitySnapshotRequestAuthority` => else 401 UNAUTHORIZED; `CityValueReportExecution.execute` (default `enabled=false` also => 503): merchant via `CityValueReportLiveAccess.merchant(memberId)` else 403 PERMISSION_DENIED; query keys must be exactly `{regionId,rulesReleaseId}` else 400 MISSING_PARAM; then `readMerchantResult` (CityValueReportSource.java:204): 404 NOT_FOUND (row missing), account-changed failure when row actor != caller or principalKind != APP_MERCHANT, 409 SCOPE_MISMATCH (merchantId in stored body, regionId, or rulesReleaseId differ), 503 SOURCE_UNAVAILABLE on exceptions.
- Response headers: `Cache-Control: no-store`, `Pragma: no-cache`; body always carries `"candidate":true` (Host:19). Failure bodies: `{"code":<http>,"msg":<message>,"errorCode":<string>,"data":<map if any>,"candidate":true}`.
- Success `data`: the stored report body map (stored JSON, keys not defined in code I read: UNKNOWN) plus `"resultId":long`.
- Idempotency/headers: none. Flag: effectively disabled until BE-INT-1 assembles host + dependencies + enable flags.
- SYNTHETIC request: `GET /api/merchant/city-value/result/55?regionId=R1&rulesReleaseId=RR1`
- SYNTHETIC response today: HTTP 503 `{"code":503,"msg":"Disabled","errorCode":"CITY_VALUE_REPORT_DISABLED"}`

### 22. POST /api/merchant/crm/customers/{customerMemberId}/detail
- Path `customerMemberId` Long; no body. `principal()` swallows auth exceptions and returns `error("请先登录")` (AjaxResult code 500) when no/invalid user (Crm:173-180, `principal()` at :312).
- Service `MerchantCrmAppServiceImpl.detail` (S/service/impl/MerchantCrmAppServiceImpl.java:297): `merchantAccessService.require(CRM_READ)` (ServiceException 403 "商家身份无效或权限不足" -> `serviceError`: `new AjaxResult(code,msg)`); id <=0 => 400 "客户ID无效"; not an owned customer => 404 "客户不存在或不属于当前商家" (:531); campaign receipt row incomplete => 409 "客户触达回执不完整". Without `CRM_SENSITIVE_READ`, `summary.paidAmount` is null.
- Success `data`: `{"summary":{customerMemberId:long,displayName:string,avatar:string,arrivedCount:int,pendingCount:int,refundedCount:int,paidAmount:decimal|null,lastInteractionTime:date, ...(other fields in MerchantCrmCustomerSummary.java, not all listed)},"systemTags":[{code,label}],"merchantTags":[{id,tagName,tagColor}],"tags":[same as merchantTags],"timeline":[{key,type,title,description,occurredAt,noteId,noteVersion,correctsNoteId}]}`; timeline max `TIMELINE_LIMIT` (value not read), sorted newest first. systemTags codes: ARRIVED/REPEAT/PENDING/REFUNDED. SystemTagVO field names: assumed `code,label` from constructor args, field names UNKNOWN.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"summary":{"customerMemberId":1001,"displayName":"A","arrivedCount":2,"pendingCount":0,"refundedCount":0,"paidAmount":null},"systemTags":[...],"merchantTags":[],"tags":[],"timeline":[]}}`

### 23. POST /api/merchant/crm/customers/{customerMemberId}/contact
- Body JSON optional (`MerchantCrmContactRequest`): `purpose` string, must be `call` or `copy` (case-insensitive after trim) else 400 "联系方式用途无效". (A null body => purpose null => 400.)
- Permission `CRM_SENSITIVE_READ`. Errors (all body `code`, no `errorCode`): 403 permission (also audited as DENIED); 400 "客户ID无效"; 404 "客户不存在或不属于当前商家"; 403 "由俱乐部带团，联系请找俱乐部负责人"; 404 "客户未留电话"; 403 "客户未授权联系方式共享"; 429 "今日获取联系号码次数已达上限，请联系平台客服" (limit 50/day per operator, counted from audit rows); 503 "联系号码频控不可用，请稍后重试"; 409 "联系方式访问审计写入失败". Each success writes an audit row `CRM_CONTACT_REVEAL`.
- No idempotency key (each success counts toward the limit).
- Success `data`: `{"phone":string}` (plaintext).
- SYNTHETIC request: `{"purpose":"call"}`; response `{"code":200,"msg":"操作成功","data":{"phone":"13800000000"}}`

### 24. POST /api/merchant/crm/exports/{taskId}/status
- POST with empty/`{}` body; path `taskId` Long. Permission `CRM_EXPORT`. Errors: 400 "导出任务ID无效"; 404 "导出任务不存在或不属于当前商家"; 403.
- Success `data` (MerchantCrmExportTaskVO via toVO): `{"id":long,"status":string,"rowCount":int,"errorMessage":string|null,"expiresAt":date|null,"downloadToken":null}` (`downloadToken` is never set by status(); only `create` returns it; Jackson may emit null or omit depending on config: UNKNOWN). `status` values: constant `MerchantCrmExportTask.SUCCESS` used; full set UNKNOWN (not read).
- Confirms be-g03 note: iOS uses POST (MerchantEngagementContracts.swift:137).
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"id":12,"status":"SUCCESS","rowCount":30,"expiresAt":"2026-11-08 12:00:00"}}`

### 25. GET /api/merchant/crm/exports/{taskId}/download
- Header `X-CRM-Export-Token` (optional in mapping; required in practice: length 32-128 and sha256 must equal stored `tokenHash`, else 403 "导出下载凭证无效"). Token is issued by `POST /api/merchant/crm/exports` (create; token TTL 15 min, `TOKEN_TTL_MILLIS`), not by this group.
- Output: binary `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`, filename `merchant-crm-{id}.xlsx`. Errors are written as JSON with real HTTP status = error code (`writeDownloadError`, Crm:~318): `{"code":N,"msg":...}` where N: 401 "请先登录"; 400 invalid id; 403 role lacks CRM_SENSITIVE_READ for paid-amount exports ("当前角色无权下载含敏感字段的导出文件") / bad token / no CRM_EXPORT; 404 task or file missing; 409 not ready ("导出文件尚未就绪"); 410 expired or customer consent withdrawn; 500 file/token facts incomplete.
- Query: none. Idempotency: download completion marks the task downloaded via `completeDownload` (single-use semantics not verified: UNKNOWN).
- SYNTHETIC request: `GET /api/merchant/crm/exports/12/download` with header `X-CRM-Export-Token: <40+ char token from create>`. Response: xlsx bytes.

### 26. POST /api/ai/merchant/insight
- NOT `/api/merchant/insight`: no controller maps that path (grep: only `@PostMapping("/merchant/insight")` under `@RequestMapping("/api/ai")`, ApiAiController.java:47,404). iOS already calls the correct path at MerchantMarketingService.swift:140 (and fixture MerchantMarketingFixtures.swift:34). The two constants naming `api/merchant/insight` are in the audit files only.
- No body/params (merchant taken from login). `@RateLimiter(time=60,count=10,limitType=MEMBER)`. Errors via `error(msg)` => code 500: "请先登录" (no user); "店铺参谋仅商家身份可用" when `merchantAccessService.require(MARKETING_READ)` throws ServiceException; "AI 服务暂时不可用,请稍后重试" on other RuntimeException; `AiServiceException` message otherwise. Rate-limit rejection shape: UNKNOWN (annotation aspect not read).
- Success `data` (MerchantInsightResp): `{"facts":object,"ai":{"traceId","summary","opportunity","problem","audiences":[{label,reason}],"suggestions":[{title,type,timeSlot,audience,reason,basis}],"recommendedTopics":[{id,reason}],"recommendedPartners":[{id,reason}]}|null,"aiError":string|null,"generatedAt":string,"profile":object,"recommendedTopics":[object],"recommendedPartners":[object],"recentVisitors":[{nickname,avatar,visitCount,topicName,lastAtText}],"trends":object}`. Cached per merchant per day (only when AI succeeded). Field-level types of `facts`/`profile`/`trends` are free-form JSON: UNKNOWN.
- Idempotency: none (read-like POST). Flags: none found.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"generatedAt":"2026-11-08 10:00:00","ai":{"summary":"...","audiences":[],"suggestions":[]},"recommendedTopics":[],"recommendedPartners":[],"recentVisitors":[],"facts":{},"profile":{},"trends":{}}}`

### 27. POST /api/merchant/npc/avatar/generate
- Body JSON (Map; null body => `error("参数有误")` code 500): `imageUrl` string (https, host required, no userinfo, no fragment, trimmed length 1-512) and `style` string in `["pixel","chibi","watercolor"]`. Non-String values are treated as null (Controller:165).
- Auth: `run()` -> `getAppUserId()` failure or id<1 => `error("请先登录")` (code 500); then `merchantAccessService.require(PROFILE_WRITE)` throws ServiceException 403 outside the try (global handler => body code 403).
- Behaviour (S/npcg03/MerchantNpcAssetG03Service.java:43-65): one active job per merchant (unique `active_key = merchantId`). Same inputs while one is PENDING => returns that job; different inputs => 409 errorCode `AVATAR_JOB_PENDING`; insert race with no winner => 503 `AVATAR_BUSY`. No worker exists, so jobs stay PENDING.
- Errors with `errorCode`: 400 `IMAGE_URL_INVALID`, 400 `AVATAR_STYLE_INVALID`, 409 `AVATAR_JOB_PENDING`, 503 `AVATAR_BUSY` (body `{"code":N,"msg":..,"errorCode":..}`).
- Success `data` (jobView): `{"jobId":long,"status":"PENDING"|...,"style":string,"modelUrl":string|null,"thumbUrl":string|null,"failReason":string|null}`.
- Idempotency: the (merchant, pending) uniqueness; no requestId. Flag: none.
- SYNTHETIC request: `{"imageUrl":"https://cdn.example.com/a.png","style":"pixel"}`
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"jobId":3,"status":"PENDING","style":"pixel","modelUrl":null,"thumbUrl":null,"failReason":null}}` (note: `jobId` may be null on a fresh insert if the mapper does not populate generated keys: UNKNOWN, mapper not read).
- iOS note: Swift MerchantNPCHTTP.swift:89 is in a client whose transport is `MerchantNPCDormantTransport` (MerchantNPCHTTP.swift: `perform` throws `.disabled`) unless a transport is injected.

### 28. POST /api/merchant/npc/avatar/status
- No body/params. Same auth as 27. Success `data`: `{"available":true,"styles":["pixel","chibi","watercolor"],"job":<jobView of latest job>|null}`. `available` is the constant true (Service:69). Errors: 403/500 as above. No errorCode path.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"available":true,"styles":["pixel","chibi","watercolor"],"job":null}}`
- iOS: also listed as NOT in `MerchantNPCHTTPClient.servedPaths` (MerchantNPCHTTP.swift:25-30), but read directly by MerchantOperationsService.swift:122.

### 29. POST /api/merchant/npc/knowledge-review
- Body JSON: `requestId` UUID string (required), `name` (1-64), `greeting` (1-500), `persona` (1-2000), `knowledge` (1-8000); all required non-blank, non-String values => null => invalid. Auth as 27.
- Idempotency: `requestId`, unique per (member, requestId); `INSERT IGNORE` then select; same content hash => same receipt; different => 409 `REQUEST_ID_REUSED`; select returns null => 503 `REVIEW_UNAVAILABLE`.
- Errors: 400 `REQUEST_ID_INVALID`, 400 `FIELD_INVALID`, 409 `REQUEST_ID_REUSED`, 503 `REVIEW_UNAVAILABLE`; null body => code 500 "参数有误".
- Success `data`: `{"requestId":string,"memberId":long,"status":"PENDING_REVIEW"}` (status default from SQL column default `PENDING_REVIEW`; the Java field is read from the stored row). Records only; does not touch `npc_profile`.
- SYNTHETIC request: `{"requestId":"9B2E...","name":"Aki","greeting":"Hi","persona":"...","knowledge":"..."}`; response `{"code":200,"msg":"操作成功","data":{"requestId":"9B2E...","memberId":88,"status":"PENDING_REVIEW"}}`

### 30. GET /api/merchant/npc/knowledge-review/request?requestId=
- Query `requestId` UUID (optional in mapping; null/invalid => 400 `REQUEST_ID_INVALID`). Scope: member's own rows only (select by memberId+requestId) => 404 `REVIEW_NOT_FOUND` otherwise. Requires PROFILE_WRITE like the others.
- Success `data`: `{"requestId":string,"memberId":long,"status":string,"name":string,"greeting":string,"persona":string,"knowledge":string}`.
- SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"requestId":"9B2E...","memberId":88,"status":"PENDING_REVIEW","name":"Aki","greeting":"Hi","persona":"...","knowledge":"..."}}`

---

## Discrepancies vs be-g01/g02/g03 reports

1. G01 vs G02 data split (not in either report): G01 `main-line`/`environment` read table `app_mauth_g01_release`; G02 publish/withdraw write `merchant_authoring_release_g02`; nothing writes `app_mauth_g01_release` or `app_mauth_g01_player_request` or `app_mauth_g01_draft.publish_outcome`. Net: `main-line` always `{"outcome":"NONE"}`, `environment` always 404, even after a G02 publish.
2. G02 publish is dead on this branch: no bean implements `AuthoringDraftSourceG02` (report says "until the integrator provides one"; confirmed none exists, and it is not backed by G01's draft table). Always 503 DRAFT_SOURCE_UNAVAILABLE for a new requestId.
3. G01 report lists `player/{merchantId}/game` and `.../requests/{requestId}` as G01 IMPLEMENTED (and the group file lists them under G01 too); the G01 handlers were removed, they are served only by the G02 controller. The G01 `playerRequest` reads `app_mauth_g01_player_request`; the G02 one calls `NpcChatService`. The report's "Route collision fix" paragraph is accurate; its path table is stale.
4. G01 ownership is the plain owner row (`mms_merchant.status=1`), while G02 and G03 use `IMerchantAccessService` (staff/operators allowed). Same user can pass G02 but 403 on G01 drafts.
5. G02 report says player/public reads "need a logged-in member only": confirmed; they accept any merchantId (no ownership/visibility check).
6. G03 report says city-value `result` is IMPLEMENTED (route only): confirmed route exists; no `CityValueReportAPIHost` bean anywhere, so it is permanently 503 until BE-INT-1. The other three city-value adapters (G02 EXISTS-UNROUTED) are confirmed UNREGISTERED.
7. G03 report: insight "EXISTS as POST /api/ai/merchant/insight": confirmed; `/api/merchant/insight` has no mapping, two iOS audit constants still point at it.
8. G03 report: exports status is POST: confirmed; iOS call site now found at MerchantEngagementContracts.swift:137.
9. G03 avatar `jobId`/error-body notes: `AjaxResult.error(code,msg)` + `errorCode`; controller returns code 500 (not 401) for unauthenticated inside `run()` for G03 NPC routes; CRM routes also return code 500 "请先登录".
10. G03 city-value `result` is the only route in this set returning real non-200 HTTP statuses (via ResponseEntity), alongside the CRM download error writer.

---

# Route table, groups G04-G07

Source: /home/user/chengyin @ cloud/rt-01 (537e43c74, = origin/claude/be-v2-fixes). iOS: /home/user/ios-w5 (origin/wip/wave5-build). Static reading only; nothing compiled, run or modified.
Dir aliases: `C/` = `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`; `S/` = `chengyinhub-system/src/main/java/com/chengyinhub/business/`; `F/` = `chengyinhub-framework/src/main/java/com/chengyinhub/framework/web/service/`; `Core/`, `App/` = ios-w5 `Core/`, `App/`.

## Common facts

### CF-1 Club-style envelope (G04, G05 routes, rows 1-10)
- Success: `AjaxResult.success(map)` -> HTTP 200 `{"code":200,"msg":"操作成功","data":{...}}` (AjaxResult.java success()).
- Business failure: `throw new ServiceException("<CODE_STRING>", <int>)`. `GlobalExceptionHandler.handleServiceException` (framework/web/exception/GlobalExceptionHandler.java:130-143) returns `AjaxResult.error(code, message)`, no `@ResponseStatus`, so HTTP status is 200 and the body is `{"code":<int>,"msg":"<CODE_STRING>"}`. There is NO separate `errorCode` field: the business error string is in `msg` (passes `UserSafeMessage`, plain ASCII codes are not masked). In the tables below "errors" are written `code / msg`.
- Unauthenticated: `SecurityConfig.java:166` `anyRequest().authenticated()`; none of the paths in this file is in a permitAll list (grep of SecurityConfig: no `club/`, no `city-game`). Entry point `AuthenticationEntryPointImpl.commence` answers `{"code":401,"msg":"登录状态已失效，请重新登录"}` with HTTP 401 for `/api` URIs. Guest: NOT allowed on any route here.
- Token: header `Authorization` (yml `token.header`), raw token or `Bearer ` prefix (TokenService strips `Constants.TOKEN_PREFIX`). iOS sends the raw token (AuthRequestBuilder.swift:36). `getAppUserId()` = `getLoginAppUser().getAppUser().getUserId()` (common/.../BaseController.java:222-225).

### CF-2 City-style envelope (G06, G07 routes, rows 11-36)
Produced by each `City*APIHost.respond()` (F/City*APIHost.java). HTTP status = `outcome.httpStatus` (a real `ResponseEntity`), headers `Cache-Control: no-store` (+ `Pragma: no-cache` except action-budget, which sets only Cache-Control).
- 200: `{"code":200,"msg":"操作成功","data":{...}}`.
- non-200: `{"code":<httpStatus>,"msg":<message>,"errorCode":"<CODE>","data"?:{...}}` (`AjaxResult.error(httpStatus,message)` then `put("errorCode")`, `put("data")` only if data != null). For most outcomes message == errorCode.
- Stored-request outcome unknown: HTTP 202 `{"code":202,"msg":"OUTCOME_UNKNOWN","errorCode":"OUTCOME_UNKNOWN","data":{"requestId":"..","requestStatus":"UNKNOWN"}}`.
- Auth (identical in every Host `run()`): `CitySnapshotRequestAuthority.capture(request)` (F/CitySnapshotRequestAuthority.java) calls `AppTokenService.getLoginAppUser(request)` (token from `Authorization`) and requires userId>0, token non-blank, sessionEpoch, expireTime and absoluteExpireTime not passed, and `sessions.isCurrentEpoch(actor, epoch)`. Failure -> 401 `UNAUTHORIZED`. Re-checked after the operation (session change mid-call -> 401). No guest. Actor is always taken from the token; no actor field is accepted from the client.
- Flags (all City hosts): NOT properties. `readsEnabled`/`writesEnabled` are constructor booleans of the Host AND of the Execution, default `false/false`. Every `City*Assembly.create(...)` builds host AND execution with `writes=false` hard-coded, `reads=readApproved` (default false) (e.g. F/CityActionBudgetAssembly.java:37-41). Closed -> 503 `<DOMAIN>_READ_NOT_APPROVED` / `<DOMAIN>_WRITE_NOT_APPROVED`. No `@Value`, no yml key. Writes can only be turned on by hand-constructing `new City*APIHost(..., true, true)` and `new City*Execution(deps, true, true)`; nothing in main sources does.
- Common read-path failure codes (every GET): 503 `<DOMAIN>_SOURCE_UNAVAILABLE` (any RuntimeException), 503 `<DOMAIN>_READ_TRANSACTION_REQUIRED`, 401 `UNAUTHORIZED`. `state` additionally 400 `INVALID_QUERY` unless query keys are exactly `{regionId}`; then pass-through of `CityBaseParticipationService.state` failures (400 `INVALID_ID`, 401, 503 `CITY_PARTICIPATION_SOURCE_UNAVAILABLE`, and board-binding failures not enumerated here).
- Command idempotency (all `POST .../command`): key = body `requestId` (regex `\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\z`, CityBoardDraftDocument.java:41). Request row is claimed first (`insertRequest`), then executed in a second transaction. Same requestId + same canonical-body SHA-256 -> stored result replayed (same HTTP status, `data.requestId`, `data.requestStatus:"COMPLETE"`). Same requestId + different body -> 409 `REQUEST_ID_REUSED`. Another member's requestId -> 404 `NOT_FOUND`. Interrupted -> 202 `OUTCOME_UNKNOWN`. No custom idempotency HTTP header; only `Authorization` (+ iOS sets `Content-Type: application/json`, `Accept: application/json`).
- Body must be a JSON object with an exact key set (unknown or missing key -> 400 `INVALID_COMMAND`). Every request also needs `kind`.

### CF-3 REGISTRATION STATUS (G06/G07)
`registerOriginalRoutes(RequestMappingHandlerMapping)` exists in the adapters for acquisition, action-budget, arrival-evidence, neutral-tasks, onsite-tasks (plus participation/task-history, other groups). Grep of all main sources (excluding tests): ZERO callers of `registerOriginalRoutes`, ZERO callers of any `City*Assembly.create`, no `@RestController`/`@Component`/`@Configuration` on any `City*MVCAdapter` (class javadoc: "not discovered or registered automatically"). `CityMerchantIntentMVCAdapter`, `CityPlayerRulesMVCAdapter`, `CityOrderedMapMVCAdapter` have no mapping annotations and no registration helper at all (methods only). => every G06/G07 route is **UNREGISTERED**: it returns HTTP 404 on this branch (and could never return the codes below until BE-INT-1 wires it). The Spring Security allowlist also has no `/api/city-game/**` entry, so once registered they sit behind `anyRequest().authenticated()` as well as the Host's own session check.
Contrast: the G03 city-value route in the same package is a real `@RestController` (`C/ApiCityValueResultG03Controller.java:22`); G06/G07 are not.

## Summary table

| # | Grp | Method | Full path | Handler file:line | Auth | Encoding | Flag (default) | iOS caller | Status |
|---|---|---|---|---|---|---|---|---|---|
| 1 | G04 | POST | /api/club/channels | C/ApiClubChannelsG04Controller.java:15 | token, owner/member of club | JSON `{clubId}` | none | label only (Core/ChannelDiscordMessaging.swift:3008) | registered |
| 2 | G04 | POST | /api/club/admission/receipt | C/ApiClubOrdinaryAdmissionRecoveryController.java:14 | token, own receipt | JSON | `app.club-ordinary-admission.reads-enabled` false -> 503 | Core/ClubActionService.swift:70 | registered |
| 3 | G04 | POST | /api/club/badge/original-receipt | C/ApiClubController.java:1351 (class `@RequestMapping("/api/club")` :103) | token, own receipt | JSON | `app.club-badge-original.reads-enabled` false -> 503 | Core/ClubBadgeManagementService.swift:63 (route Core/ClubBadgeManagementModels.swift:90) | registered |
| 4 | G04 | POST | /api/club/event-ops/series/original-result | C/ApiClubEventOpsController.java:67 (class :26) | token + ACTIVITY_MANAGE on club | JSON | `chengyin.club.series-original-result.enabled` false -> 403 | Core/ClubSeriesOriginalResult.swift:128 | registered |
| 5 | G05 | POST | /api/club/post/operation/create | C/ApiClubPostOriginalController.java:19 | token (+ original writer's own checks) | JSON | `app.club-post-original.reads-enabled` AND `.writes-enabled` false -> 503 | Core/ClubPostOriginalService.swift:45 | registered |
| 6 | G05 | POST | /api/club/post/operation/update | C/ApiClubPostOriginalController.java:25 | token | JSON | same as 5 | Core/ClubPostOriginalService.swift:45 | registered |
| 7 | G05 | POST | /api/club/post/operation/receipt | C/ApiClubPostOriginalController.java:32 | token, own receipt | JSON | `.reads-enabled` false -> 503 | Core/ClubPostOriginalService.swift:28 ; legacy Core/ClubCommunityPendingJournal.swift:410 (wire mismatch, see detail) | registered |
| 8 | G05 | POST | /api/club/post/operation/comment/create | C/ApiClubCommentOriginalController.java:17 | token | JSON | `app.club-comment-original.reads-enabled` AND `.writes-enabled` false -> 503 | Core/ClubCommentOriginalService.swift:50 | registered |
| 9 | G05 | POST | /api/club/post/operation/comment/receipt | C/ApiClubCommentOriginalController.java:24 | token, own receipt | JSON | `.reads-enabled` false -> 503 | Core/ClubCommentOriginalService.swift:28 | registered |
| 10 | G05 | POST | /api/club/open-settings/welcome-note-receipt | C/ApiClubWelcomeNoteRecoveryController.java:16 | token, own receipt | JSON | controller bean absent unless `app.club-welcome-original.reads-enabled=true` (default false -> route 404) | Core/ClubWelcomeNoteFlow.swift:372 | registered only if flag true |
| 11 | G06 | GET | /api/city-game/acquisition/state | C/CityAcquisitionMVCAdapter.java:22 (map :42) | token + epoch | query `regionId` | reads=false -> 503 | Core/CityAcquisitionService.swift:131 | UNREGISTERED |
| 12 | G06 | GET | /api/city-game/acquisition/titles | C/CityAcquisitionMVCAdapter.java:24 (map :43) | same | query `regionId` | reads=false | Core/CityAcquisitionService.swift:137 | UNREGISTERED |
| 13 | G06 | GET | /api/city-game/acquisition/quote/{id} | C/CityAcquisitionMVCAdapter.java:23 (map :44) | same | path | reads=false | Core/CityAcquisitionService.swift:144 | UNREGISTERED |
| 14 | G06 | POST | /api/city-game/acquisition/command | C/CityAcquisitionMVCAdapter.java:25 (map :45) | same | JSON | writes=false -> 503 (replays still readable) | Core/CityAcquisitionService.swift:148 | UNREGISTERED |
| 15 | G06 | GET | /api/city-game/acquisition/request/{requestId} | C/CityAcquisitionMVCAdapter.java:26 (map :46) | same | path | reads=false | Core/CityAcquisitionService.swift:150 | UNREGISTERED |
| 16 | G06 | GET | /api/city-game/action-budget/state | C/CityActionBudgetMVCAdapter.java:22 (map :41) | same | query `regionId` | reads=false | Core/CityActionBudgetReader.swift:27 | UNREGISTERED |
| 17 | G06 | POST | /api/city-game/action-budget/command | C/CityActionBudgetMVCAdapter.java:23 (map :42) | same | JSON | writes=false | Core/CityActionBudgetRecovery.swift:131 | UNREGISTERED |
| 18 | G06 | GET | /api/city-game/action-budget/result/{resultId} | C/CityActionBudgetMVCAdapter.java:24 (map :43) | same | path | reads=false | NONE | UNREGISTERED |
| 19 | G06 | GET | /api/city-game/action-budget/request/{requestId} | C/CityActionBudgetMVCAdapter.java:25 (map :44) | same | path | reads=false | Core/CityActionBudgetReader.swift:45 | UNREGISTERED |
| 20 | G06 | GET | /api/city-game/arrival-evidence/state | C/CityArrivalEvidenceMVCAdapter.java:22 (map :42) | same | query `regionId` | reads=false | Core/CityArrivalEvidenceService.swift:158 | UNREGISTERED |
| 21 | G06 | GET | /api/city-game/arrival-evidence/merchant | C/CityArrivalEvidenceMVCAdapter.java:23 (map :43) | same + merchant staff | none | reads=false | Core/CityArrivalEvidenceService.swift:176 | UNREGISTERED |
| 22 | G06 | GET | /api/city-game/arrival-evidence/evidence/{id} | C/CityArrivalEvidenceMVCAdapter.java:24 (map :44) | same | path | reads=false | Core/CityArrivalEvidenceService.swift:202 | UNREGISTERED |
| 23 | G06 | POST | /api/city-game/arrival-evidence/command | C/CityArrivalEvidenceMVCAdapter.java:25 (map :45) | same (+ merchant staff for CONFIRM/REJECT) | JSON | writes=false | Core/CityArrivalEvidenceService.swift:181 | UNREGISTERED |
| 24 | G06 | GET | /api/city-game/arrival-evidence/request/{id} | C/CityArrivalEvidenceMVCAdapter.java:26 (map :46) | same | path | reads=false | Core/CityArrivalEvidenceService.swift:184 | UNREGISTERED |
| 25 | G07 | GET | /api/city-game/neutral-tasks/state | C/CityNeutralTaskMVCAdapter.java:22 (map :40) | same | query `regionId` | reads=false | Core/CityNeutralTaskService.swift:145 | UNREGISTERED |
| 26 | G07 | POST | /api/city-game/neutral-tasks/command | C/CityNeutralTaskMVCAdapter.java:23 (map :41) | same | JSON | writes=false | Core/CityNeutralTaskService.swift:154 | UNREGISTERED |
| 27 | G07 | GET | /api/city-game/neutral-tasks/request/{requestId} | C/CityNeutralTaskMVCAdapter.java:24 (map :42) | same | path | reads=false | Core/CityNeutralTaskService.swift:159 | UNREGISTERED |
| 28 | G07 | GET | /api/city-game/onsite-tasks/state | C/CityOnsiteTaskMVCAdapter.java:22 (map :41) | same | query `regionId` | reads=false | Core/CityOnsiteTaskService.swift:150 | UNREGISTERED |
| 29 | G07 | GET | /api/city-game/onsite-tasks/result/{id} | C/CityOnsiteTaskMVCAdapter.java:23 (map :42) | same | path | reads=false | Core/CityOnsiteTaskService.swift:187 | UNREGISTERED |
| 30 | G07 | POST | /api/city-game/onsite-tasks/command | C/CityOnsiteTaskMVCAdapter.java:24 (map :43) | same | JSON | writes=false | Core/CityOnsiteTaskService.swift:158 | UNREGISTERED |
| 31 | G07 | GET | /api/city-game/onsite-tasks/request/{requestId} | C/CityOnsiteTaskMVCAdapter.java:25 (map :44) | same | path | reads=false | Core/CityOnsiteTaskService.swift:167 | UNREGISTERED |
| 32 | G07 | GET | /api/city-game/merchant/operations/availability | C/CityMerchantIntentMVCAdapter.java:15 (no mapping; path/verb only in javadoc :9-10) | same + live merchant access | query `regionId` | reads=false | Core/CityMerchantOperationsService.swift:140 | UNREGISTERED, no registration helper |
| 33 | G07 | POST | /api/city-game/merchant/operations/intent | C/CityMerchantIntentMVCAdapter.java:16 (javadoc only) | same | JSON | writes=false | Core/CityMerchantOperationsService.swift:146 | UNREGISTERED, no registration helper |
| 34 | G07 | GET | /api/city-game/merchant/operations/request/{requestId} | C/CityMerchantIntentMVCAdapter.java:17 (javadoc only) | same | path | reads=false | Core/CityMerchantOperationsService.swift:149 | UNREGISTERED, no registration helper |
| 35 | G07 | GET | /api/city-game/player-rules | C/CityPlayerRulesMVCAdapter.java:11 (javadoc only :7) | same | query (8-10 keys) | enabled=false | Core/CityPlayerRulesClient.swift:43 | UNREGISTERED, no registration helper |
| 36 | G07 | GET | /api/city-game/state/deltas | C/CityOrderedMapMVCAdapter.java:17 (javadoc only :11) | same (own check in host) | query | `CityOrderedConfiguration` all-false; cannot be enabled via public API | Core/CityOrderedMapScopedTransport.swift:76 (route check :49) | UNREGISTERED, no registration helper |
| (37) | adjacent | GET | /api/city-game/state/snapshot (`sync=TRANSACTIONAL_EVENTS_V1` variant) | C/CityOrderedMapMVCAdapter.java:16 | same | query | same as 36 | Core/CityOrderedMapScopedTransport.swift:76 | UNREGISTERED. Not in G06/G07 path list; same adapter. Not counted. |

Counted routes: 36 (10 registered controller routes of which row 10 is flag-conditional, 26 UNREGISTERED).

## No route (BLOCKED paths) - nothing exists to document

Grep of all `@*Mapping` in chengyinhub-admin main: none of these paths is mapped (only unrelated `POST /api/club/join-requests`, ApiClubController.java:995, which is NOT `/join-requests/apply`).

| Path | Group | Reason (from BE report + verified: no mapping in code) |
|---|---|---|
| /api/club/activity/join | G04 | BLOCKED: no iOS contract; paid-activity join is order/payment logic. Existing alternatives named in report: /api/registration/quote, /create, /api/club/event-ops/waitlist/join |
| /api/club/activity/cancel | G04 | BLOCKED-ON-OWNER-PAYMENT-DECISION (cancel implies refund) |
| /api/club/activity/detail | G04 | BLOCKED (no contract); report says POST /api/activity/info covers it |
| /api/club/events | G04 | BLOCKED (no contract); report: existing /api/club/event-ops/series/list etc. |
| /api/club/events/Checkin | G04 | BLOCKED: arrival must be server-authoritative; no write route/contract; owner decision needed |
| /api/club/events/proxy-enroll | G04 | BLOCKED-ON-OWNER-PAYMENT-DECISION (creates registrations/orders for another member) |
| /api/club/join-requests/apply | G05 | BLOCKED (label only in iOS); real flow is POST /api/club/join, /apply, /admission/receipt |
| /api/club/notices/send | G05 | BLOCKED (label only); real flow POST /api/club/event-notification/send |
| /api/club/notices | G05 | BLOCKED (label only); no notice-history list exists |
| /api/club/events/save | G05 | BLOCKED (label only); real flow /api/club/event-ops/series/create, /series/update-future |
| /api/club/group-code | G05 | BLOCKED (label only); real flow POST /api/verify/groupcode/issue |
| /api/club/group-code/save | G05 | BLOCKED: no route anywhere, no per-club config store |
| /api/city-game/ (prefix), /api/city-game/acquisition/ , /action-budget, /action-budget/, /arrival-evidence/, /neutral-tasks/, /onsite-tasks/, /merchant/operations, /merchant/operations/request/ (trailing), /player-rules (as a prefix) , `/api/city-game/{}/request/{}` | G06/G07 | Not separate routes: they are path prefixes / templates that the iOS catalogue lists. The concrete routes are rows 11-36. Generic `{}/request/{}` = the per-domain `/request/{requestId}` GET (rows 15, 19, 24, 27, 31, 34) |

iOS label-only facts (verified): `api/club/channels` appears in Swift only at Core/ChannelDiscordMessaging.swift:50,65 (doc comments on display models) and :3008 (`nativeOnlyEndpoints: ["api/club/channels"]`). No `URLRequest` builds it.

---

# G04 detail

## Row 1  POST /api/club/channels  (G04)
- Handler: C/ApiClubChannelsG04Controller.java:12-20 (`@RestController`, `@RequestMapping("/api/club/channels")`, `@PostMapping`), service S/service/impl/ClubChannelDirectoryG04Service.java, SQL chengyinhub-system/src/main/resources/mapper/business/ClubChannelG04Mapper.xml, tables in chengyinhub-admin/sql/migration_g04_20261108.sql.
- Auth: token required (CF-1). Then membership: club owner (`OwnershipUtils.isOwner`) or any row in club_member via `selectByClubAndMember` (status semantics not read: UNKNOWN). Guest not allowed.
- Encoding: JSON body `@RequestBody(required=false) Map`. 
- Params: `clubId` number (JSON number only; a string `"12"` is treated as missing), required, > 0.
- Success `data`: `{clubId:number, categories:[{id,clubId,name,position}], channels:[{id,clubId,categoryId,name,kind,visibility,position,archivedAt:string|null "yyyy-MM-ddTHH:mm:ss"}]}`. Channels with `visibility > 0` are dropped unless caller is owner. Tables are empty (nothing writes them), so today `categories:[]`, `channels:[]` for a member.
- Errors (code / msg): 401 / CLUB_CHANNELS_LOGIN_REQUIRED (memberId null); 400 / CLUB_CHANNELS_REQUEST_INVALID (clubId missing/non-number/<=0); 404 / CLUB_CHANNELS_CLUB_NOT_FOUND; 403 / CLUB_CHANNELS_MEMBERS_ONLY. Unauthenticated: filter-chain 401 (CF-1).
- Idempotency: read-only; none. Headers: Authorization only.
- Flags: none.
- iOS caller: label only (see above). iOS has display models only (`ChannelDirectoryCategory/Entry`, ChannelDiscordMessaging.swift:50-100); wire shape (POST+JSON, field names) is unverified against any Swift code.
- SYNTHETIC example:
  - req `{"clubId":12}`
  - res `{"code":200,"msg":"操作成功","data":{"clubId":12,"categories":[{"id":1,"clubId":12,"name":"General","position":0}],"channels":[{"id":5,"clubId":12,"categoryId":1,"name":"chat","kind":"TEXT","visibility":0,"position":0,"archivedAt":null}]}}`

## Row 2  POST /api/club/admission/receipt  (G04)
- Handler: C/ApiClubOrdinaryAdmissionRecoveryController.java:12-14 (class `/api/club/admission` + `/receipt`), service S/service/impl/ClubOrdinaryAdmissionOriginalService.java:`receipt` (~line 66-72).
- Auth: token; own receipt only (`receipts.own(actor, club, request)`), no current-membership check. 
- Encoding: JSON. iOS builds it with `AuthRequestBuilder.makeFormRequest(fields:[:])` then overwrites `Content-Type: application/json` and sets `httpBody` JSON (ClubActionService.swift:70-73), so it is JSON on the wire.
- Params (body keys must be EXACTLY these four, else 400): `clubId` JSON number matching `[1-9][0-9]{0,17}`; `requestId` string lowercase UUID `[0-9a-f]{8}-...-[0-9a-f]{12}`; `action` string in `join|apply|leave`; `payloadSHA256` string 64 lowercase hex. iOS digest = SHA-256 of `action + "\n" + message` (message empty unless `apply`).
- Success `data`: if no stored receipt: `{actorMemberId, clubId, action, requestId, payloadSHA256, state:"UNKNOWN"}`; if stored: same keys with `state:"APPLIED"` plus `membershipState` (`joined` | `pending` | `left`). Unknown extra stored fields are never returned.
- Errors: 400 / CLUB_ADMISSION_REQUEST_INVALID (controller key-set/type check, or validate()); 503 / CLUB_ADMISSION_NOT_CONFIGURED (reads flag off); 409 / CLUB_ADMISSION_RECEIPT_CONFLICT; 409 / CLUB_ADMISSION_RECEIPT_INVALID.
- Idempotency: read-only; the key is the `requestId` of the ORIGINAL write (`/api/club/join|quit`, which carries headers `X-Club-Admission-Request-Id`, `X-Club-Admission-Action`, `X-Club-Admission-Payload-SHA256`; those headers are not used on this receipt route and iOS asserts they are absent, ClubOrdinaryAdmissionRoute.swift:20,24).
- Flags: `app.club-ordinary-admission.reads-enabled` (default false, `@Value` in service) -> 503. Writes flag `.writes-enabled` (default false) irrelevant to this route.
- iOS caller: Core/ClubActionService.swift:70 (`recover`), route validator Core/ClubOrdinaryAdmissionRoute.swift:22; composition-root passthrough App/AppCompositionRoot.swift:3158-3170.
- SYNTHETIC example:
  - req `{"clubId":12,"requestId":"3f2b8c1e-5a7d-4e90-9b1a-2c4d6e8f0a1b","action":"join","payloadSHA256":"cf93e6b3235d7080df87a8caf721257602dba87a3aef799a24f82a09a3d63ec2"}` (digest = sha256("join\n"))
  - res `{"code":200,"msg":"操作成功","data":{"actorMemberId":77,"clubId":12,"action":"join","requestId":"3f2b8c1e-5a7d-4e90-9b1a-2c4d6e8f0a1b","payloadSHA256":"cf93e6b3...3ec2","state":"UNKNOWN"}}`

## Row 3  POST /api/club/badge/original-receipt  (G04)
- Handler: C/ApiClubController.java:1350-1353 (`@PostMapping("/badge/original-receipt")` under class `@RequestMapping("/api/club")`, :103) -> `badgeOriginal.receipt(currentMemberId(), body)`; service S/service/impl/ClubBadgeOriginalService.java:`receipt` (~line 105-118). `currentMemberId()` behaviour when unauthenticated: not read (UNKNOWN; the security filter normally rejects first).
- Auth: token; own immutable audit fact only (survives owner revocation).
- Encoding: JSON.
- Params (exact key set, else 400): `clubId` number `[1-9][0-9]{0,17}`; `requestId` lowercase UUID; `operation` string `CREATE|GRANT`; `sourceSHA256` 64 hex. (Hash is the client-computed `CLUB_BADGE_V1` canonical digest, ClubBadgeManagementModels.swift sourceHash.)
- Success `data`: not found -> `{protocolVersion:1, clubId, actorMemberId, requestId, operation, sourceSHA256, state:"UNKNOWN"}`. Found -> `{protocolVersion, clubId, actorMemberId, requestId, operation, sourceSHA256, state:"CREATED"|"GRANTED"|"ALREADY_GRANTED", badgeId, badgeCode, memberId(null for CREATE), appliedAt(epoch ms), auditId}`.
- Errors: 503 / CLUB_BADGE_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_BADGE_ORIGINAL_INVALID; 409 / CLUB_BADGE_ORIGINAL_RECEIPT_CONFLICT; 409 / CLUB_BADGE_ORIGINAL_RECEIPT_INVALID. `ClubBadgeOriginalSchema.verifyCurrent(..., false)` may also throw (codes not read: UNKNOWN).
- Idempotency: read-only; key = `requestId` of the original `/api/club/badge/create|grant` write, which sends headers `X-Club-Badge-Request-Id` and `X-Club-Badge-Source-SHA256` (ClubBadgeOriginalService REQUEST_HEADER/SOURCE_HEADER). Not used on this route (iOS asserts none, ClubBadgeManagementModels.swift:108).
- Flags: `app.club-badge-original.reads-enabled` default false -> 503 (`writes-enabled` default false is for the writer).
- iOS caller: Core/ClubBadgeManagementService.swift:63 (`receipt(entry)`), request validated by `ClubBadgeManagementRoute` Core/ClubBadgeManagementModels.swift:90-119; fields Core/ClubBadgeManagementJournal.swift:23.
- SYNTHETIC example:
  - req `{"clubId":12,"requestId":"9a1c0e44-7d2b-4f55-8e61-0b3a5c7d9e21","operation":"CREATE","sourceSHA256":"<64 hex>"}`
  - res `{"code":200,"msg":"操作成功","data":{"protocolVersion":1,"clubId":12,"actorMemberId":77,"requestId":"9a1c0e44-...","operation":"CREATE","sourceSHA256":"<64 hex>","state":"UNKNOWN"}}`

## Row 4  POST /api/club/event-ops/series/original-result  (G04)
- Handler: C/ApiClubEventOpsController.java:66-74 (class `/api/club/event-ops`, :26); service S/service/impl/ClubEventOpsServiceImpl.java:329-342 `readSeriesOriginalResult`; store S/service/support/ClubSeriesOriginalResultStore.java:69 `read`.
- Auth: token (controller `principal()` returns null if no login -> `error("请先登录")`), then `clubAccessService.require(actor, clubId, ClubPermission.ACTIVITY_MANAGE)` with a club owner row lock and re-check. Not an own-row-only read: needs current ACTIVITY_MANAGE.
- Encoding: JSON `ClubEventSeriesRequest` (`@RequestBody(required=false)`, Jackson bean in S/domain/dto/ClubEventSeriesRequest.java). Unknown JSON keys are ignored by Jackson default (not verified for this app's ObjectMapper config).
- Params: `clubId` Long >0 required; `topicId` Long >0 required; `requestId` string 1-64 chars after trim, required; the retained original create inputs the store re-hashes: `recurrenceType`, `startDate`, `startTime`, `occurrenceCount`, `customDates[]`, `rrule`, `defaultLeadMemberId`, `capacity`, `waitlistEnabled`, `offerMinutes`, `seriesId`, `expectedVersion` (iOS sends `original.fields` verbatim, sorted keys, <=65536 bytes).
- Success `data`: not found -> `{version:1, actorMemberId, clubId, topicId, requestId, state:"UNKNOWN"}`. Found (state "APPLIED") -> `{version, actorMemberId, clubId, topicId, requestId, state:"APPLIED", wire:{...echo of request fields...}, series:{id,clubId,topicId,createdByMemberId,requestId,requestFingerprint,recurrenceType,timezone,defaultLeadMemberId,defaultCapacity,waitlistEnabled,offerMinutes,status,version,createBy,createdAtEpochMs,updateBy,updatedAtEpochMs,remark,params}, effectiveDates:["yyyy-MM-dd"], startTime, occurrences:[{id,seriesId,activityId,occurrenceAtEpochMs,defaultLeadMemberId,status,version,createdAtEpochMs}], receiptHash}`.
- Errors: this controller uses `serviceError(e)` -> `new AjaxResult(e.getCode(), e.getMessage())`, so `msg` is Chinese text, NOT a code string, HTTP 200: 500 / 请先登录 (no principal; `error()` default code 500, controller :69-70); 400 / 缺少原系列请求 (null body); 400 / 原系列请求不完整 (clubId/topicId not positive); 400 / requestId 需为 1 至 64 字; 403 / 俱乐部身份无效或权限不足 (flag off, or no ACTIVITY_MANAGE, or owner mismatch); 409 / 原系列结果损坏 | 原系列结果校验不符 | 原系列结果版本或字段不符 | 原系列请求身份不符 | 原系列结果范围不符 | 原系列回执与原记录身份不符 (store.fail(), 409). Schema `preflight()` failures: UNKNOWN.
- Idempotency: read-only replay of the original `/api/club/event-ops/series/create`, whose key is the same `requestId` (+ clubId, topicId, actor). No special headers.
- Flags: `chengyin.club.series-original-result.enabled` (ClubEventOpsServiceImpl.java:71, default false) -> 403 as above.
- iOS caller: Core/ClubSeriesOriginalResult.swift:128 (POST, `Content-Type: application/json`, `Authorization`), approval path constant :9.
- SYNTHETIC example:
  - req `{"clubId":12,"topicId":3,"requestId":"series-20261108-001","recurrenceType":"WEEKLY","startDate":"2026-11-15","startTime":"19:00","occurrenceCount":4}`
  - res (never created) `{"code":200,"msg":"操作成功","data":{"version":1,"actorMemberId":77,"clubId":12,"topicId":3,"requestId":"series-20261108-001","state":"UNKNOWN"}}`

---

# G05 detail

Common to rows 5-9: request identity (`ClubPostOriginalService.identity`, S/service/impl/ClubPostOriginalService.java:107-120; `ClubCommentOriginalService.identity`) must be an object whose key set is EXACTLY `{receiptNamespace, operationId, requestId, operationKind, clubId, postId, commentId, version}` for receipt, plus `{content, images}` (post write) or `{content}` (comment write). `receiptNamespace` = `"club-post-v1"`; `operationId` = UPPERCASE UUID `[0-9A-F]{8}-...`; `requestId` = `[A-Za-z0-9_.:-]{1,64}`; `clubId` positive integer; `postId`,`commentId`,`version` non-negative integers (regex `0|[1-9][0-9]{0,17}`). Violation -> 400 / `CLUB_POST_ORIGINAL_INVALID` (comment: `CLUB_COMMENT_ORIGINAL_INVALID`); `actor` null -> 401 same code.
Receipts live in `business_audit_event` (action `CLUB_POST_ORIGINAL` / comment equivalent); idempotency = (actor, clubId, requestId, operationId) + `sourceSHA256` of the identity+content; a repeat with different identity/hash -> 409 `..._CONFLICT`. A write whose original writer returns a non-200 AjaxResult is stored as `status:"REJECTED"` with `rejectedCode` and still returns envelope code 200.

## Row 5  POST /api/club/post/operation/create  (G05)
- Handler: C/ApiClubPostOriginalController.java:19-24 (class `/api/club/post/operation`, :15), service ClubPostOriginalService.execute (:36-90), delegates to `ApiClubController.postCreateOriginalResult`.
- Auth: token; permission is whatever the original writer enforces (membership/text-security/media provenance), not read here (UNKNOWN detail). Audit needs `IClubAccessService.resolve` role, else 409 `CLUB_POST_ORIGINAL_AUDIT_UNAVAILABLE`.
- Encoding: JSON.
- Params: identity keys above with `operationKind:"create"`, `postId:0`, `version:0`, `commentId:0` (else 400 `CLUB_POST_ORIGINAL_KIND_INVALID` when kind != create at controller :34, or `_INVALID`); `content` String <=300; `images` String <=2000 (iOS joins refs with ";").
- Success `data`: `{commentId, clubId, operationId, operationKind:"create", postId, receiptNamespace, requestId, version, sourceSHA256, status:"ACKNOWLEDGED", resultPostId, resultVersion}` (key order is the TreeSet-sorted identity); or `status:"REJECTED"`, `rejectedCode:<int>` instead of the result pair.
- Errors: 503 / CLUB_POST_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_POST_ORIGINAL_INVALID | CLUB_POST_ORIGINAL_KIND_INVALID; 404 / CLUB_POST_ORIGINAL_TARGET_UNAVAILABLE; 409 / CLUB_POST_ORIGINAL_CONFLICT | _UNKNOWN | _RECEIPT_FAILED | _AUDIT_UNAVAILABLE.
- Idempotency: `requestId` + `operationId` in body (see above); replay returns stored fact. No headers.
- Flags: `app.club-post-original.reads-enabled` AND `.writes-enabled`, both default false (`@Value` ClubPostOriginalService.java:25-26) -> 503.
- iOS caller: Core/ClubPostOriginalService.swift:45 (suffix create/update), request builder :16-24, route guard Core/ClubPostOriginalRuntime.swift:13-40.
- SYNTHETIC example:
  - req `{"receiptNamespace":"club-post-v1","operationId":"B6F1C2D3-0A1B-4C5D-8E9F-112233445566","requestId":"op-b6f1c2d3","operationKind":"create","clubId":12,"postId":0,"commentId":0,"version":0,"content":"hello","images":""}`
  - res `{"code":200,"msg":"操作成功","data":{"clubId":12,"commentId":0,"operationId":"B6F1C2D3-...","operationKind":"create","postId":0,"receiptNamespace":"club-post-v1","requestId":"op-b6f1c2d3","version":0,"sourceSHA256":"<64 hex>","status":"ACKNOWLEDGED","resultPostId":901,"resultVersion":1}}`

## Row 6  POST /api/club/post/operation/update  (G05)
- Handler: C/ApiClubPostOriginalController.java:25-31 -> `ApiClubController.postUpdate(ClubPostMutationRequest)` (CAS on `version`).
- Auth/encoding/flags/errors/idempotency/iOS: as row 5, with `operationKind:"edit"`, `postId > 0`, `version >= 0` (the post version the edit is based on, `Math.toIntExact`), `commentId:0`. Extra check: target post must belong to the club, else 404 `CLUB_POST_ORIGINAL_TARGET_UNAVAILABLE`; acknowledged `resultPostId` must equal `postId` and `resultVersion >= version`.
- Note: the create/update mutual kind check is at controller `requireKind` (:34).
- SYNTHETIC example:
  - req `{"receiptNamespace":"club-post-v1","operationId":"C7A2D3E4-1B2C-4D6E-9FA0-223344556677","requestId":"op-c7a2d3e4","operationKind":"edit","clubId":12,"postId":901,"commentId":0,"version":1,"content":"hello v2","images":""}`
  - res `data.status:"ACKNOWLEDGED"`, `resultPostId:901`, `resultVersion:2` (same shape as row 5).

## Row 7  POST /api/club/post/operation/receipt  (G05)
- Handler: C/ApiClubPostOriginalController.java:32-34 -> `ClubPostOriginalService.receipt` (:93-99).
- Auth: token; own receipt only (`receipts.own(actor, clubId, requestId, operationId)`).
- Encoding: JSON. Params: the eight identity keys only (no content/images). `operationKind` in `create|edit`.
- Success `data`: stored fact (shape of row 5) or, if nothing stored, the identity map plus `status:"PENDING"` ("Absent is UNKNOWN, not permission to repeat a write", service comment).
- Errors: 503 / CLUB_POST_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_POST_ORIGINAL_INVALID; 409 / CLUB_POST_ORIGINAL_CONFLICT.
- Idempotency: read-only. Flags: `app.club-post-original.reads-enabled` default false.
- iOS caller: Core/ClubPostOriginalService.swift:28 (wire matches: sends all 8 keys incl. `receiptNamespace`, Core/ClubPostOriginalContracts.swift:18-22). DISCREPANCY: legacy `ClubCommunityHTTPPendingOutcomeQuery` Core/ClubCommunityPendingJournal.swift:410 also POSTs here with keys `clubId,postId,commentId,operationId,operationKind,requestId[,version]` and NO `receiptNamespace` (:395-404); the backend rejects that as 400 `CLUB_POST_ORIGINAL_INVALID` (key set must equal the identity set). grep: that class is referenced only in Tests/ besides its definition (not in Core/App composition), so it is a dormant legacy adapter.
- SYNTHETIC example: req = row 5 identity (8 keys) ; res `{"code":200,"msg":"操作成功","data":{...identity...,"status":"PENDING"}}`.

## Row 8  POST /api/club/post/operation/comment/create  (G05)
- Handler: C/ApiClubCommentOriginalController.java:17-23 (class `/api/club/post/operation/comment`, :13), service S/service/impl/ClubCommentOriginalService.java:34-77, delegates to `ApiClubController.commentCreateOriginalResult`. Root comments only.
- Auth: token. Encoding: JSON.
- Params: identity keys with `operationKind:"comment"`, `postId` >0 (target post), `version` >=0 (must equal the target post's current `version`, else the stored result becomes REJECTED code 409 "原动态已变化"), `commentId:0` (replies rejected 400), `clubId`>0; `content` String non-blank, trimmed, <=300.
- Success `data`: identity keys + `sourceSHA256` + `status:"ACKNOWLEDGED"` + `resultPostId`, `resultVersion`, `resultCommentId`; or `status:"REJECTED"` + `rejectedCode`.
- Errors: 503 / CLUB_COMMENT_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_COMMENT_ORIGINAL_INVALID; 404 / CLUB_COMMENT_ORIGINAL_TARGET_UNAVAILABLE; 409 / CLUB_COMMENT_ORIGINAL_CONFLICT | _UNKNOWN | _RECEIPT_FAILED | _AUDIT_UNAVAILABLE.
- Idempotency: `requestId` + `operationId` in body. Flags: `app.club-comment-original.reads-enabled` AND `.writes-enabled` default false.
- iOS caller: Core/ClubCommentOriginalService.swift:50 (request builder :16-24), guard Core/ClubCommentOriginalRuntime.swift:13.
- SYNTHETIC example: req `{"receiptNamespace":"club-post-v1","operationId":"D8B3E4F5-2C3D-4E7F-A0B1-334455667788","requestId":"op-d8b3e4f5","operationKind":"comment","clubId":12,"postId":901,"commentId":0,"version":2,"content":"nice"}` ; res `data.status:"ACKNOWLEDGED","resultPostId":901,"resultVersion":2,"resultCommentId":5001`.

## Row 9  POST /api/club/post/operation/comment/receipt  (G05)
- Handler: C/ApiClubCommentOriginalController.java:24-26 -> `ClubCommentOriginalService.receipt` (:79-84). Own receipt only.
- Params: eight identity keys, `operationKind:"comment"`. Success: stored fact or identity + `status:"PENDING"`. Errors: 503 / CLUB_COMMENT_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_COMMENT_ORIGINAL_INVALID; 409 / CLUB_COMMENT_ORIGINAL_CONFLICT. Flag `app.club-comment-original.reads-enabled` default false. Read-only.
- iOS caller: Core/ClubCommentOriginalService.swift:28.
- SYNTHETIC example: req = row 8 identity without `content`; res `data = identity + "status":"PENDING"`.

## Row 10  POST /api/club/open-settings/welcome-note-receipt  (G05)
- Handler: C/ApiClubWelcomeNoteRecoveryController.java:12-18 (class `/api/club/open-settings`, `@ConditionalOnProperty(app.club-welcome-original.reads-enabled, havingValue=true)`; the service bean ClubWelcomeNoteOriginalService has the same condition) -> `original.receipt(actor, body)` (S/service/impl/ClubWelcomeNoteOriginalService.java ~line 104-116, `@Transactional(propagation=NEVER)`). With the flag at its default the controller bean does not exist: **route 404**.
- Auth: token; own fact after owner loss (event actor == owner == caller).
- Encoding: JSON. Params (exact key set): `clubId` number `[1-9][0-9]{0,17}`; `requestId` lowercase UUID; `sourceSHA256` 64 hex (`CLUB_WELCOME_NOTE_V1` digest, iOS Core/ClubWelcomeNoteFlow.swift:235).
- Success `data`: not found -> `{protocolVersion:1, actorMemberId, clubId, requestId, sourceSHA256, state:"UNKNOWN"}`; found APPLIED -> adds `welcomeNote:string`, `recordedAt:epoch ms`, `auditId`; found REJECTED -> adds `message:string`, `recordedAt`, `auditId` instead of `welcomeNote`.
- Errors: 503 / CLUB_WELCOME_ORIGINAL_NOT_CONFIGURED; 400 / CLUB_WELCOME_ORIGINAL_INVALID; 409 / CLUB_WELCOME_ORIGINAL_RECEIPT_CONFLICT | _RECEIPT_INVALID.
- Idempotency: read-only; key = `requestId` of original write (`POST /api/club/open-settings/welcome-note` with headers `X-Club-Welcome-Request-Id`, `X-Club-Welcome-Source-SHA256`). 
- Flags: `app.club-welcome-original.reads-enabled` default false (route absent); `.writes-enabled` default false (writer).
- iOS caller: Core/ClubWelcomeNoteFlow.swift:372 (fields `clubId,requestId,sourceSHA256`, :233; matches).
- SYNTHETIC example: req `{"clubId":12,"requestId":"5e6f7a8b-9c0d-4e1f-a2b3-c4d5e6f70819","sourceSHA256":"<64 hex>"}` ; res `{"code":200,"msg":"操作成功","data":{"protocolVersion":1,"actorMemberId":77,"clubId":12,"requestId":"5e6f7a8b-...","sourceSHA256":"<64 hex>","state":"UNKNOWN"}}`.

---

# G06 detail  (ALL UNREGISTERED, see CF-3; envelope CF-2)

Common: identifiers. `regionId`, `boardId`, `pointId`, `taskId`, `optionId`, `requestId`, `challengeId`? (no: UUID) per `CityBoardDraftDocument.isId` = `[A-Za-z0-9][A-Za-z0-9_-]{0,95}`; "uuid" below = lowercase 8-4-4-4-12 hex. Hash = 64 lowercase hex. Read-only GET errors listed once in CF-2.

## ACQUISITION  (Host F/CityAcquisitionAPIHost.java, Execution S/citygame/acquisition/CityAcquisitionExecution.java, Service CityAcquisitionService.java)
Flag text: `readsEnabled`/`writesEnabled` false by default -> 503 `CITY_ACQUISITION_READ_NOT_APPROVED` / `CITY_ACQUISITION_WRITE_NOT_APPROVED`. Source-unavailable 503 `CITY_ACQUISITION_SOURCE_UNAVAILABLE`, `CITY_ACQUISITION_READ_TRANSACTION_REQUIRED`.

### Row 11  GET /api/city-game/acquisition/state
- Query: `regionId` (required, EXACTLY the only key, else 400 INVALID_QUERY; invalid id 400 `INVALID_REGION`).
- Success data: `{contract:"CITY_ACQUISITION_V1", memberId:number, regionId, writeApproved:bool, ownTitles:[TitleView personal], status:"JOIN_REQUIRED"|"AVAILABLE", [teamId], candidates:[{instanceId,taskId,pointId,eligibility:"QUOTE_AVAILABLE"|"ALREADY_OWNED"|<denial code>, pointCost,actionCost,maxHoldingsPerTeam,termSeconds,evidenceAcceptance:"MERCHANT_ATTESTED"}], binding:{...}, ownership:[TitleView public]}` (JOIN_REQUIRED has `candidates:[]`, `ownership:[]`, writeApproved:false).
- TitleView (CityAcquisitionService.titleView): `titleId,regionId,boardId,seasonId,pointId,ownerTeamId,pointVersion,releaseId,contentHash,acquiredAt(ISO),titleRetained,transferAllowed,serviceFeesAvailable,status("ACTIVE_TERM"|"TERM_REVIEW_REQUIRED"|"PAUSED_TERM_FROZEN"|"SOURCE_UNAVAILABLE_TITLE_RETAINED")`; personal adds `payerMemberId,sessionId,roundId,requestId,quoteId,taskResultId,evidenceId,pointCost,pointsBefore,pointsAfter,pointsBusinessKey,actionCost,actionsBefore,actionsAfter,budgetVersion,termSeconds,policyHash`.
- Errors: CF-2 plus 400 INVALID_REGION, 401 UNAUTHORIZED. Idempotency: none (read). iOS: Core/CityAcquisitionService.swift:131 (builder :200-209). 
- SYNTHETIC: `GET .../acquisition/state?regionId=city-1` -> `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ACQUISITION_V1","memberId":77,"regionId":"city-1","writeApproved":false,"ownTitles":[],"status":"JOIN_REQUIRED","candidates":[],"ownership":[]}}`

### Row 12  GET /api/city-game/acquisition/titles
- Query `regionId` only. Success data `{contract:"CITY_ACQUISITION_V1", memberId, regionId, titles:[TitleView personal]}`. Errors: 400 INVALID_QUERY | INVALID_REGION, 401, CF-2. iOS: CityAcquisitionService.swift:137.
- SYNTHETIC res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ACQUISITION_V1","memberId":77,"regionId":"city-1","titles":[]}}`

### Row 13  GET /api/city-game/acquisition/quote/{id}
- Path `id` = uuid (400 INVALID_ID otherwise); only the caller's own quote (404 NOT_FOUND otherwise).
- Success data `{contract:"CITY_ACQUISITION_V1", quote:{...terms..., quoteHash, writeApproved, expired}}`; terms keys (CityAcquisitionService.terms): `quoteId,confirmRequestId(UPPERCASE UUID to use as requestId for CONFIRM),payerMemberId,beneficiaryTeamId,sessionId,regionId,boardId,seasonId,roundId,pointId,releaseId,contentHash,policyHash,taskInstanceId,taskResultId,evidenceId,evidenceAssurance:"MERCHANT_ATTESTED",merchantId,placeId,pointCost,actionCost,maxHoldingsPerTeam,termSeconds,teamVersion,budgetVersion,pointVersion,merchantVersion,platformVersion,createdAt,expiresAt,mode,releasePolicy,termPolicy,pausePolicy,rewardPolicy:"NONE",pointsBalanceAtQuote,actionsRemainingAtQuote,evidenceAcceptanceReason`.
- Errors: 400 INVALID_ID, 404 NOT_FOUND, 401, CF-2; 503 `CITY_QUOTE_SOURCE_UNAVAILABLE` only as an IllegalStateException -> `CITY_ACQUISITION_SOURCE_UNAVAILABLE`. iOS: CityAcquisitionService.swift:144.

### Row 14  POST /api/city-game/acquisition/command
- Encoding JSON object, <=2048 bytes. Two shapes (exact key sets):
  - `kind:"QUOTE"`: `{requestId, kind, regionId, instanceId(uuid)}`
  - `kind:"CONFIRM"`: `{requestId, kind, regionId, quoteId(uuid), quoteHash(64 hex), confirmed:true}` (`confirmed` must be boolean true; `requestId` must equal the quote's server-issued `confirmRequestId`, else 409 `ORIGINAL_CONFIRM_KEY_REQUIRED`).
- Success data: QUOTE -> `{contract, quote:{...as row 13}, effectsStatus:"NOT_EXECUTED", requestId, requestStatus:"COMPLETE"}`; CONFIRM -> `{contract, title:TitleView personal, effectsStatus:"COMMITTED", requestId, requestStatus:"COMPLETE"}` (debits points and action budget, inserts title + outbox).
- Errors (HTTP = code): 400 INVALID_COMMAND; 404 NOT_FOUND; 409 ORIGINAL_OUTCOME_UNRESOLVED | POINT_ALREADY_OWNED | TASK_EFFECT_ALREADY_COMMITTED | HOLDING_LIMIT_REACHED | INSUFFICIENT_POINTS | ACTION_BUDGET_EXHAUSTED | QUOTE_EXPIRED | QUOTE_CHANGED | QUOTE_BINDING_CHANGED | ACTION_VERSION_CHANGED | PASSED_TASK_REQUIRED | TASK_NOT_APPROVED_FOR_ACQUISITION | TASK_BINDING_CHANGED | EVIDENCE_EXPIRED | CITY_TEAM_NOT_READY | CITY_RELEASE_UNAVAILABLE | CITY_ACQUISITION_NOT_CONFIGURED | REQUEST_ID_REUSED | ORIGINAL_CONFIRM_KEY_REQUIRED; 503 CITY_ACTION_BUDGET_SOURCE_UNAVAILABLE | CITY_ACQUISITION_WRITE_NOT_APPROVED | CITY_ACQUISITION_SOURCE_UNAVAILABLE; 202 OUTCOME_UNKNOWN; 401.
- Idempotency: body `requestId` (CF-2). Order: a prior request row is replayed BEFORE the write-flag check (so receipts stay readable with writes off).
- iOS: CityAcquisitionService.swift:148 (`submit`), body guard CityAcquisitionRoute :89-96.
- SYNTHETIC req `{"requestId":"A1B2C3D4-0000-4000-8000-000000000001","kind":"QUOTE","regionId":"city-1","instanceId":"11111111-2222-4333-8444-555555555555"}` ; res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ACQUISITION_V1","quote":{"quoteId":"...","quoteHash":"<64 hex>","pointCost":50,"actionCost":1,"expiresAt":"2026-11-08T10:00:00Z","writeApproved":false,"expired":false},"effectsStatus":"NOT_EXECUTED","requestId":"A1B2C3D4-0000-4000-8000-000000000001","requestStatus":"COMPLETE"}}`

### Row 15  GET /api/city-game/acquisition/request/{requestId}
- Path `requestId` isId (400 INVALID_ID); 404 NOT_FOUND if absent or another member's. Success: the stored command outcome replayed with its ORIGINAL HTTP status/errorCode and `data{...,requestId,requestStatus:"COMPLETE"}`; incomplete -> 202 OUTCOME_UNKNOWN. iOS: CityAcquisitionService.swift:150.

## ACTION BUDGET  (Host F/CityActionBudgetAPIHost.java, Execution S/citygame/budget/CityActionBudgetExecution.java, Service CityActionBudgetService.java, Rules CityActionBudgetRules.java)
Flag: 503 `CITY_ACTION_BUDGET_READ_NOT_APPROVED` / `_WRITE_NOT_APPROVED`; source 503 `CITY_ACTION_BUDGET_SOURCE_UNAVAILABLE`. NOTE: header set is only `Cache-Control: no-store`.

### Row 16  GET /api/city-game/action-budget/state
- Query `regionId` only (else 400 INVALID_QUERY).
- Success data: not joined -> `{contract:"CITY_ACTION_BUDGET_V1", scope:"CITY", status:"JOIN_REQUIRED", writeApproved:false, recentResults:[]}`; joined -> `{contract:"CITY_ACTION_BUDGET_V1"|"CITY_ACTION_BUDGET_V2" (V2 when acquisitionCost>0), scope:"CITY", binding:{...}, teamId, teamVersion, [sessionId], movementStatus:"UNAVAILABLE", arrivalProof:"NOT_PROVIDED", ownershipEffect:"NONE", pointsEffect:"NONE", effectsStatus:"NOT_EXECUTED", status:"NOT_CONFIGURED"|"TEAM_NOT_READY"|"EXHAUSTED"|"AVAILABLE", writeApproved:bool, [rules:{actionKind,chargeTiming,refillPolicy,resultPolicy,rollCost,scope:"TEAM_ROUND",totalUnits,unit:"ACTION",[acquisitionCost]}, dice:{diceId,faces:[long],weights:[int]}, version, usedUnits, remainingUnits, rollCount, [acquisitionCount]], recentResults:[ResultView]}`.
- ResultView: `resultId,requestId,rollNumber,budgetVersion,costUnits,beforeUnits,afterUnits,diceId,faceIndex,faceValue,createdAt(ISO),effectsStatus:"NOT_EXECUTED",verifier:"SERVER_WEIGHTED_SECURE_RANDOM_V1"`.
- Errors: CF-2 plus pass-through; 401; 404 NOT_FOUND / 401 (Denied) from access.read; 503 CITY_ACTION_BUDGET_SOURCE_UNAVAILABLE (stored row inconsistent with rules).
- iOS: Core/CityActionBudgetReader.swift:27 (GET, `Authorization`, `Accept`). SYNTHETIC res: `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ACTION_BUDGET_V1","scope":"CITY","status":"JOIN_REQUIRED","writeApproved":false,"recentResults":[]}}`

### Row 17  POST /api/city-game/action-budget/command
- JSON object <=4096 chars; keys EXACTLY `{requestId, kind, regionId, teamId, expectedTeamVersion, releaseId, contentHash, expectedVersion}`; `kind` must be `"ROLL"`; `requestId`/`regionId` isId; `teamId` uuid; `contentHash` 64 hex; `expectedTeamVersion` int >=1, `releaseId` int >=1, `expectedVersion` int >=0 (all <= 2^53-1). No client face/probability accepted (server draws).
- Success data: `{contract, scope:"CITY", binding, teamId, sessionId, result:ResultView, requestId, requestStatus:"COMPLETE"}` (HTTP 200).
- Errors: 400 INVALID_COMMAND; 409 VERSION_CONFLICT | TEAM_VERSION_CONFLICT | CITY_TEAM_NOT_READY | CITY_ACTION_BUDGET_NOT_CONFIGURED | CITY_SNAPSHOT_CHANGED | BUDGET_BINDING_CHANGED | ACTION_BUDGET_EXHAUSTED | REQUEST_ID_REUSED; 404 NOT_FOUND; 401; 503 CITY_ACTION_BUDGET_WRITE_NOT_APPROVED | _SOURCE_UNAVAILABLE; 202 OUTCOME_UNKNOWN. Stored 4xx outcomes are replayed with `data.requestStatus:"COMPLETE"`.
- Idempotency: body `requestId` (CF-2). iOS: Core/CityActionBudgetRecovery.swift:131 (bytes from the journal, `Content-Type: application/json`).
- SYNTHETIC req `{"requestId":"roll-20261108-0001","kind":"ROLL","regionId":"city-1","teamId":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","expectedTeamVersion":3,"releaseId":12,"contentHash":"<64 hex>","expectedVersion":0}` ; res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ACTION_BUDGET_V1","scope":"CITY","teamId":"aaaaaaaa-...","sessionId":"...","result":{"resultId":"...","requestId":"roll-20261108-0001","rollNumber":1,"budgetVersion":1,"costUnits":1,"beforeUnits":6,"afterUnits":5,"diceId":"d6","faceIndex":3,"faceValue":4,"createdAt":"2026-11-08T09:00:00Z","effectsStatus":"NOT_EXECUTED","verifier":"SERVER_WEIGHTED_SECURE_RANDOM_V1"},"requestId":"roll-20261108-0001","requestStatus":"COMPLETE"}}`

### Row 18  GET /api/city-game/action-budget/result/{resultId}
- Path uuid (400 INVALID_ID); 404 NOT_FOUND if absent; access.read(actor, result.teamId) must pass (membership of that team; 404/401 Denied otherwise).
- Success data `{contract, scope:"CITY", binding, teamId, sessionId, result:ResultView}`. iOS: NONE (the scoped transport allows only `state`, `request/`, `command`, CityActionBudgetScopedTransport.swift:50-66; no other Swift file builds this path).

### Row 19  GET /api/city-game/action-budget/request/{requestId}
- Path isId; stored outcome replayed (status 200/400/409 or 202 OUTCOME_UNKNOWN); other member's / missing -> 404 NOT_FOUND. iOS: Core/CityActionBudgetReader.swift:45 (decodes with `Receipt` rules :56-62; also generic Core/CityOriginalReceiptReading.swift:9).

## ARRIVAL EVIDENCE  (Host F/CityArrivalEvidenceAPIHost.java, Execution S/citygame/arrival/CityArrivalEvidenceExecution.java, Service CityArrivalEvidenceService.java)
Flag: 503 `CITY_ARRIVAL_READ_NOT_APPROVED` / `CITY_ARRIVAL_WRITE_NOT_APPROVED`; `CITY_ARRIVAL_SOURCE_UNAVAILABLE`. Evidence is MERCHANT_ATTESTED only (no GPS proof).

### Row 20  GET /api/city-game/arrival-evidence/state
- Query `regionId` only. Success data: not joined `{contract:"CITY_ARRIVAL_EVIDENCE_V1", status:"JOIN_REQUIRED", writeApproved:false, points:[]}`; joined `{contract, scope:"CITY", binding, teamId, teamVersion, [sessionId], effectsStatus:"NOT_EXECUTED", taskEligibility:"NOT_EVALUATED", status:"NOT_CONFIGURED"|"READY"|"TEAM_NOT_READY", writeApproved, points:[{pointId,title,merchantId,placeId,rules,attemptVersion,[evidence],[challenge],canIssue,availability}]}`.
- challenge view: `challengeId,requestId,pointId,teamId,sessionId,memberId,merchantId,placeId,releaseId,contentHash,regionId,boardId,seasonId,roundId,rulesReleaseId,policyHash,state("ISSUED"|"SUBMITTED"|"CONFIRMED"|"REJECTED"|"EXPIRED"),version,ordinal,expiresAt`. evidence view: `evidenceId,challengeId,requestId,teamId,sessionId,memberId,pointId,merchantId,placeId,releaseId,contentHash,regionId,boardId,seasonId,roundId,rulesReleaseId,policyHash,assurance:"MERCHANT_ATTESTED",reason,reviewerMemberId,reviewerRole,createdAt,expiresAt,timeStatus,currentTaskEligibility,effectsStatus`.
- Errors: CF-2 + pass-through (400 INVALID_ID etc.); Denied 4xx/409 codes from access.team. iOS: Core/CityArrivalEvidenceService.swift:158. 

### Row 21  GET /api/city-game/arrival-evidence/merchant
- No params. Needs the caller to be merchant staff (`access.staff(actor)`; failure -> its Denied code, 403 `FORBIDDEN` seen in this package). Success data `{contract, merchantId, ownerMemberId, role, writeApproved, pending:[challengeView + pointTitle]}` (only SUBMITTED, unexpired, ready-team claims whose roster does not include the reviewer). iOS: Core/CityArrivalEvidenceService.swift:176.

### Row 22  GET /api/city-game/arrival-evidence/evidence/{id}
- Path uuid (400 INVALID_ID); 404 NOT_FOUND if absent; visible to the evidence's member or staff of the evidence's merchant (else 404). Success data `{contract, evidence:evidenceView, currentTaskEligibility:"NOT_EVALUATED", effectsStatus:"NOT_EXECUTED"}`. iOS: Core/CityArrivalEvidenceService.swift:202.

### Row 23  POST /api/city-game/arrival-evidence/command
- JSON <=4096. `kind` selects an exact key set (all include `requestId`(isId), `kind`, `expectedVersion` int >=0):
  - `ISSUE`: `regionId, teamId(uuid), pointId, releaseId>=1, contentHash(64 hex), expectedTeamVersion>=1`
  - `SUBMIT`: `challengeId(uuid), displayCode` (32 uppercase hex)
  - `CONFIRM`: `challengeId, displayCode (32 uppercase hex), reason` (trimmed 1-500 chars)
  - `REJECT`: `challengeId, displayCode:""` (must be empty), `reason`
- CONFIRM/REJECT require merchant staff of the challenge's merchant; reviewer may not be a roster member (403 `TEAM_CANNOT_ATTEST_ITSELF`).
- Success data: ISSUE `{contract, challenge, displayCode(32 uppercase hex, shown once), effectsStatus:"NOT_EXECUTED", requestId, requestStatus:"COMPLETE"}`; SUBMIT/REJECT `{challenge, effectsStatus}`; CONFIRM `{challenge, evidence, effectsStatus}`.
- Errors: 400 INVALID_COMMAND | INVALID_ID; 403 FORBIDDEN | TEAM_CANNOT_ATTEST_ITSELF; 404 NOT_FOUND; 409 PLACE_CHANGED | LOCATION_PERMISSION_UNAVAILABLE | VERSION_CONFLICT | MERCHANT_UNAVAILABLE | CITY_MERCHANT_UNAVAILABLE | INVALID_STATE | CITY_TEAM_NOT_READY | CHALLENGE_CODE_MISMATCH | MERCHANT_OWNER_CHANGED | EVIDENCE_ALREADY_RECORDED | CITY_SNAPSHOT_CHANGED | CITY_ARRIVAL_NOT_CONFIGURED | CHALLENGE_LIMIT_REACHED | CHALLENGE_EXPIRED | CHALLENGE_BINDING_CHANGED | CHALLENGE_ALREADY_ACTIVE | REQUEST_ID_REUSED; 503 CITY_ARRIVAL_WRITE_NOT_APPROVED | CITY_ARRIVAL_SOURCE_UNAVAILABLE; 202 OUTCOME_UNKNOWN; 401. Write flag is checked BEFORE the key set validation, and also before any replay (unlike acquisition).
- Idempotency: `requestId`. iOS: Core/CityArrivalEvidenceService.swift:181; body guard :113-130 (iOS requestId is UPPERCASE UUID).
- SYNTHETIC req (ISSUE) `{"requestId":"E1F2A3B4-0000-4000-8000-000000000002","kind":"ISSUE","regionId":"city-1","teamId":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","pointId":"p-001","releaseId":12,"contentHash":"<64 hex>","expectedTeamVersion":3,"expectedVersion":0}` ; res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_ARRIVAL_EVIDENCE_V1","challenge":{"challengeId":"...","state":"ISSUED","version":1,"ordinal":1,"expiresAt":"2026-11-08T09:10:00Z"},"displayCode":"0123456789ABCDEF0123456789ABCDEF","effectsStatus":"NOT_EXECUTED","requestId":"E1F2A3B4-0000-4000-8000-000000000002","requestStatus":"COMPLETE"}}`

### Row 24  GET /api/city-game/arrival-evidence/request/{id}
- Path variable is named `id` in this adapter (`/request/{id}`), value = the original requestId (isId; 400 INVALID_ID). Stored outcome replay as rows 15/19; 404 NOT_FOUND. iOS: Core/CityArrivalEvidenceService.swift:184.

---

# G07 detail  (ALL UNREGISTERED, see CF-3; envelope CF-2)

## NEUTRAL TASKS  (Host F/CityNeutralTaskAPIHost.java, Service S/citygame/neutral/CityNeutralTaskService.java)
Flag: 503 `CITY_NEUTRAL_READ_NOT_APPROVED` / `CITY_NEUTRAL_WRITE_NOT_APPROVED`; `CITY_NEUTRAL_SOURCE_UNAVAILABLE`.

### Row 25  GET /api/city-game/neutral-tasks/state
- Query `regionId` only. Success data: not joined `{contract:"CITY_NEUTRAL_TASK_V1", scope:"CITY", status:"JOIN_REQUIRED", writeApproved:false, tasks:[]}`; joined `{contract, scope:"CITY", status:"AVAILABLE"|"TEAM_NOT_READY", writeApproved, binding, teamId, teamVersion, [sessionId], tasks:[{definition:<playerView>, status:"NOT_ACCEPTED"|"ACTIVE"|"PASSED"|"EXHAUSTED", version, attempts, [instanceId, acceptedAt, result:{resultId,outcome,attemptNumber,requestId,createdAt,verifier:"NATIVE_OBJECTIVE_QA_PICK_V1"}]}], arrivalProof:"NOT_PROVIDED", ownershipEffect:"NONE", pointsEffect:"NONE"}`.
- Errors: CF-2 + pass-through; Denied 404 `TASK_NOT_SUPPORTED`, 404 NOT_FOUND, 401. iOS: Core/CityNeutralTaskService.swift:145.

### Row 26  POST /api/city-game/neutral-tasks/command
- JSON <=4096. Keys: `ACCEPT` = `{requestId, kind, regionId, teamId(uuid), expectedTeamVersion>=1, releaseId>=1, contentHash, taskId, expectedVersion}` (expectedVersion must be 0); `SUBMIT` = same + `instanceId(uuid), optionId(isId)` (expectedVersion = instance version).
- Success data `{contract:"CITY_NEUTRAL_TASK_V1", scope:"CITY", task:<state task view>, requestId, requestStatus:"COMPLETE"}`. A server-side objective judge decides pass; attempts capped by `maxAttempts`.
- Errors: 400 INVALID_COMMAND | INVALID_OPTION; 404 NOT_FOUND | TASK_NOT_SUPPORTED; 409 TEAM_VERSION_CONFLICT | CITY_TEAM_NOT_READY | CITY_SNAPSHOT_CHANGED | VERSION_CONFLICT | ORIGINAL_TASK_EXISTS | TASK_BINDING_CHANGED | TASK_TERMINAL | ATTEMPTS_EXHAUSTED | REQUEST_ID_REUSED; 503 CITY_NEUTRAL_WRITE_NOT_APPROVED | CITY_NEUTRAL_SOURCE_UNAVAILABLE; 202 OUTCOME_UNKNOWN; 401.
- Idempotency: `requestId`. iOS: Core/CityNeutralTaskService.swift:154 (receipt always read after POST, :155-156 comment).
- SYNTHETIC req (ACCEPT) `{"requestId":"F1A2B3C4-0000-4000-8000-000000000003","kind":"ACCEPT","regionId":"city-1","teamId":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","expectedTeamVersion":3,"releaseId":12,"contentHash":"<64 hex>","taskId":"t-neutral-1","expectedVersion":0}` ; res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_NEUTRAL_TASK_V1","scope":"CITY","task":{"definition":{},"status":"ACTIVE","version":1,"attempts":0,"instanceId":"..."},"requestId":"F1A2B3C4-...","requestStatus":"COMPLETE"}}` (`definition` content = CityNeutralTaskDefinition.playerView(), not expanded here).

### Row 27  GET /api/city-game/neutral-tasks/request/{requestId}
- isId path; stored outcome replay; 404 NOT_FOUND. iOS: Core/CityNeutralTaskService.swift:159.

## ONSITE TASKS  (Host F/CityOnsiteTaskAPIHost.java, Service S/citygame/onsite/CityOnsiteTaskService.java)
Flag: 503 `CITY_ONSITE_READ_NOT_APPROVED` / `CITY_ONSITE_WRITE_NOT_APPROVED`; `CITY_ONSITE_SOURCE_UNAVAILABLE`.

### Row 28  GET /api/city-game/onsite-tasks/state
- Query `regionId` only. Success: not joined `{contract:"CITY_ONSITE_TASK_V1", scope:"CITY", status:"JOIN_REQUIRED", writeApproved:false, tasks:[]}`; joined `{contract, scope:"CITY", status:"NOT_CONFIGURED"|"TEAM_NOT_READY"|"AVAILABLE", writeApproved, binding, teamId, teamVersion, memberId, [sessionId], tasks:[{definition, [evidence:{evidenceId,memberId,pointId,merchantId,placeId,teamId,sessionId,releaseId,contentHash,policyHash,roundId,expiresAt,assurance:"MERCHANT_ATTESTED"}], eligibility:"EVIDENCE_REQUIRED"|"TEAM_NOT_READY"|"ELIGIBLE"|"EVIDENCE_ALREADY_BOUND"|<denial>, canAct, status, version, attempts, [instanceId, evidenceId, acceptRequestId, acceptedAt, result:ResultView]}], arrivalProof:"MERCHANT_ATTESTED_ONLY", ownershipEffect:"NONE", pointsEffect:"NONE", effectsStatus:"NOT_EXECUTED"}`. iOS: Core/CityOnsiteTaskService.swift:150.

### Row 29  GET /api/city-game/onsite-tasks/result/{id}
- Path uuid (400 INVALID_ID); 404 NOT_FOUND unless the result belongs to the caller (acceptedBy and memberId). Success data `{contract:"CITY_ONSITE_TASK_V1", result:{resultId,instanceId,taskId,requestId,acceptRequestId,outcome,memberId,attemptNumber,createdAt,evidenceCheckedAt,evidenceExpiresAt,evidenceId,evidencePolicyHash,pointId,merchantId,placeId,teamId,sessionId,regionId,boardId,seasonId,roundId,releaseId,rulesReleaseId,contentHash,taskHash,verifier:"NATIVE_OBJECTIVE_QA_PICK_V1",arrivalAssurance:"MERCHANT_ATTESTED",effectsStatus:"NOT_EXECUTED"}, effectsStatus:"NOT_EXECUTED"}`. iOS: Core/CityOnsiteTaskService.swift:187.

### Row 30  POST /api/city-game/onsite-tasks/command
- JSON <=4096. `ACCEPT`: `{requestId, kind, regionId, teamId(uuid), expectedTeamVersion>=1, releaseId>=1, contentHash, taskId, evidenceId(uuid), expectedVersion(=0)}`; `SUBMIT` adds `instanceId(uuid), optionId`. Evidence (from arrival-evidence CONFIRM) must still be valid at execution.
- Success data `{...task/result view..., requestId, requestStatus:"COMPLETE"}` (SUBMIT includes `result` when terminal).
- Errors: 400 INVALID_COMMAND | INVALID_OPTION; 404 NOT_FOUND; 409 TEAM_VERSION_CONFLICT | CITY_TEAM_NOT_READY | CITY_SNAPSHOT_CHANGED | VERSION_CONFLICT | ORIGINAL_TASK_EXISTS | EVIDENCE_ALREADY_BOUND | TASK_BINDING_CHANGED | TASK_TERMINAL | ATTEMPTS_EXHAUSTED | REVIEWER_PERMISSION_WITHDRAWN | MERCHANT_OWNER_CHANGED | EVIDENCE_SOURCE_CHANGED | EVIDENCE_EXPIRED | EVIDENCE_BINDING_CHANGED | CITY_ONSITE_NOT_CONFIGURED | REQUEST_ID_REUSED; 503 CITY_ONSITE_WRITE_NOT_APPROVED | CITY_ONSITE_SOURCE_UNAVAILABLE; 202 OUTCOME_UNKNOWN; 401. Idempotency: `requestId`. iOS: Core/CityOnsiteTaskService.swift:158 (`permitsStoredRejection: true`).
- SYNTHETIC req (ACCEPT) like row 26 plus `"evidenceId":"11111111-2222-4333-8444-555555555555"`.

### Row 31  GET /api/city-game/onsite-tasks/request/{requestId}
- isId path; stored replay; iOS: Core/CityOnsiteTaskService.swift:167.

## MERCHANT OPERATIONS  (Host F/CityMerchantIntentAPIHost.java, Source S/citygame/operations/CityMerchantIntentSource.java, Engine CityMerchantIntentReceiptEngine.java; outcome class CityGameOperationsOutcome)
The adapter C/CityMerchantIntentMVCAdapter.java contains plain methods with NO mapping annotations and NO registration helper; verb/path are documented only in its javadoc (":9-10 GET /availability?regionId; POST /intent; GET /request/{requestId}") and in iOS. Flag: 503 `CITY_MERCHANT_INTENT_READ_NOT_APPROVED` / `_WRITE_NOT_APPROVED`, `CITY_MERCHANT_INTENT_SOURCE_UNAVAILABLE`. Business failures here carry Chinese `msg` plus an English `errorCode` (Source.fail(status, code, message)). Authorization: caller must resolve to a merchant account via `CityMerchantIntentLiveAccess` (`access.resolve(memberId)`), else 403 `NO_AUTHORITY` (msg 本店授权已失效).

### Row 32  GET /api/city-game/merchant/operations/availability
- Query `regionId` only (else 400 INVALID_QUERY). Success data `{merchantId:string, version:long, status:"NONE"|..., effectiveState:"INHERIT"|"PAUSED"|..., kind, requestId, originalRequestId, approvalHash, runtimeApplied:false, execution:"CONFIG_ONLY", ownerMemberId, scope:"merchant_operational_fact", allowedFields:["PAUSE_MERCHANT","RESTORE"], availability:"AVAILABLE"|"PUBLISHED_MERCHANT_RELATION_UNAVAILABLE", relation:{...}|null, approvalHash}`.
- Errors: 403 NO_AUTHORITY, CF-2. iOS: Core/CityMerchantOperationsService.swift:140.
- SYNTHETIC res `{"code":200,"msg":"操作成功","data":{"merchantId":"88","version":0,"status":"NONE","effectiveState":"INHERIT","kind":null,"requestId":null,"originalRequestId":null,"approvalHash":"<64 hex>","runtimeApplied":false,"execution":"CONFIG_ONLY","ownerMemberId":77,"scope":"merchant_operational_fact","allowedFields":["PAUSE_MERCHANT","RESTORE"],"availability":"AVAILABLE","relation":{}}}` (`relation` shape = CityMerchantIntentBoardRelation.view(), not expanded).

### Row 33  POST /api/city-game/merchant/operations/intent
- JSON object, keys EXACTLY `{requestId, expectedVersion, regionId, kind, reason, approvalHash}` (unknown -> 400 UNKNOWN_FIELD / PROTECTED_FIELD; missing -> 400 MISSING_PARAM). `kind` in `PAUSE_MERCHANT|RESTORE`; `reason` text 1-500 trimmed; `approvalHash` = value from availability; `expectedVersion` = availability `version`.
- Success data `{merchantId, version(+1), status:"IN_REVIEW", effectiveState, kind, requestId, originalRequestId, approvalHash(proposal), runtimeApplied:false, execution:"CONFIG_ONLY", chain:[audit entries], resent:false}`. It records an intent for review only; nothing is paused at runtime.
- Errors (errorCode): 400 OBJECT_SCOPE | REASON_REQUIRED | MISSING_PARAM | UNKNOWN_FIELD | PROTECTED_FIELD | CLIENT_APPROVAL_REJECTED | CLIENT_EVIDENCE_REJECTED; 403 NO_AUTHORITY | ASSET_SCOPE_REJECTED; 409 PUBLISHED_MERCHANT_RELATION_UNAVAILABLE | VERSION_CONFLICT | APPROVAL_CHANGED | PENDING_REVIEW | INVALID_STATE | CONFLICT | UNKNOWN (UNKNOWN data `{requestId,state:"UNKNOWN",resent:false,candidate:true,transport}`); 503 CITY_MERCHANT_INTENT_WRITE_NOT_APPROVED | _SOURCE_UNAVAILABLE; 401.
- Idempotency: body `requestId` (isId; replays by request-row `CityGameOperationsRequestRow`, same hash -> stored, different -> `replay()` conflict (code CONFLICT 409 presumed; exact branch not read: UNKNOWN)). Host sets `Cache-Control: no-store`, `Pragma: no-cache`.
- iOS: Core/CityMerchantOperationsService.swift:146 (body keys at :143: `requestId(UPPERCASE UUID), expectedVersion, regionId, kind, reason, approvalHash`; matches).
- SYNTHETIC req `{"requestId":"0F1E2D3C-0000-4000-8000-000000000004","expectedVersion":0,"regionId":"city-1","kind":"PAUSE_MERCHANT","reason":"renovation","approvalHash":"<64 hex>"}`.

### Row 34  GET /api/city-game/merchant/operations/request/{requestId}
- Path isId (else 400 MISSING_PARAM "原请求号无效"); 404 NOT_FOUND ("原请求不存在，请勿自动重发"); another actor's -> 403 NO_AUTHORITY. Success: stored outcome + `audit:[...]`, `resent:false`. iOS: Core/CityMerchantOperationsService.swift:149.

## PLAYER RULES  (Host F/CityPlayerRulesAPIHost.java, Execution S/citygame/playerrules/CityPlayerRulesExecution.java, Source CityPlayerRulesSource.java)

### Row 35  GET /api/city-game/player-rules
- Verb/path only in the adapter javadoc (C/CityPlayerRulesMVCAdapter.java:7 "Unregistered GET /api/city-game/player-rules"). Flag `enabled` false by default -> 503 `CITY_PLAYER_RULES_READ_NOT_APPROVED`; `CityPlayerRulesAssembly.create` has no approval parameter at all.
- Query (exact key set, else 400 INVALID_QUERY): `gameId, regionId, boardId, seasonId, rulesReleaseId` (isId), `rulesHash` (64 hex), `revision` (integer string 0..2^53-1), `membership` in `JOINED|NOT_JOINED|UNAVAILABLE`; when `JOINED` also `participationId` (isId) and `membershipVersion` (integer string).
- Success data `{contract:"CITY_PLAYER_RULES_V1", scope:"CITY", status:"AVAILABLE", board:{gameId,regionId,boardId,seasonId,rulesReleaseId,rulesHash,revision,...}, releaseId, sections:[...projection of the frozen document...], eligibility:{status:"NOT_CONFIGURED"|"PREVIOUS_RELEASE"|"NO_QUALIFICATION"|"ABSENT"|"FORMING"|"CONFIRMATION_REQUIRED"|"TEAM_WAITING"|"MEMBERSHIP_CONFIRMED", [teamId,teamVersion,present,confirmed,memberCount,presentCount,confirmedCount,sessionId,sessionVersion]}, grantsParticipation:false, grantsAction:false}`.
- Errors: 400 INVALID_QUERY; 401 UNAUTHORIZED; 403 CITY_PLAYER_RULES_ACCESS_WITHDRAWN; 404 CITY_NO_CURRENT_BOARD; 409 CITY_SNAPSHOT_CHANGED | CITY_MEMBERSHIP_CHANGED; 503 CITY_PLAYER_RULES_READ_NOT_APPROVED | CITY_PLAYER_RULES_SOURCE_UNAVAILABLE | CITY_PLAYER_RULES_MEMBERSHIP_UNAVAILABLE (status from upstream). Host does not put `data` into error bodies.
- Idempotency: none (read). iOS: Core/CityPlayerRulesClient.swift:43 (query keys built :36-39, sorted; GET, `Accept`, `Authorization`).
- SYNTHETIC req `GET /api/city-game/player-rules?gameId=g1&regionId=city-1&boardId=b1&seasonId=s1&rulesReleaseId=r1&rulesHash=<64 hex>&revision=3&membership=NOT_JOINED` ; res `{"code":200,"msg":"操作成功","data":{"contract":"CITY_PLAYER_RULES_V1","scope":"CITY","status":"AVAILABLE","board":{},"releaseId":12,"sections":[],"eligibility":{"status":"NO_QUALIFICATION"},"grantsParticipation":false,"grantsAction":false}}`

## ORDERED MAP  (Host F/CityOrderedMapAPIHost.java, Service S/citygame/sync/CityOrderedReadService.java, Config CityOrderedConfiguration.java)

### Row 36  GET /api/city-game/state/deltas
- Adapter C/CityOrderedMapMVCAdapter.java:17 `deltas(request, Map query)`, no mapping; path only in javadoc (:11). Row 37 (snapshot) is the sibling method (:16); javadoc: a future dispatcher (F/CityStateSnapshotModeDispatcher.java, constructed disabled, `enabled=false`, no caller) would route `sync` queries to it.
- Auth: Host does its own check (not CitySnapshotRequestAuthority): `tokens.getLoginAppUser` valid, session epoch current. Failure 401 `UNAUTHORIZED`.
- Query (from CityOrderedReadService.read + CityOrderedSnapshotSource BASE set): `sync=TRANSACTIONAL_EVENTS_V1` (else 400 `CITY_MAP_QUERY_INVALID`), `cursor` = `<uuid>.<sequence>` (required for deltas; sequence integer >=0, canonical decimal), plus the snapshot scope keys `regionId, boardId, seasonId, rulesReleaseId, revision, south, west, north, east, datum(WGS84|GCJ02), zoom, layers (comma list of MERCHANT|POI|PLATFORM_VIRTUAL), limit`. The cursor must be bound to the same scope hash, credential hash, actor and unexpired stream.
- Success data: `{contract:"CITY_TRANSACTIONAL_MAP_V1", scope:"CITY", mode:"TRANSACTIONAL_EVENTS_V1", streamId, scopeHash, sequence, cursor:"<streamId>.<sequence>", boardVersion, capturedAtMillis, validUntilMillis, grantsAction:false, grantsNavigation:false, kind:"DELTAS", afterSequence, batches:[{events:[...]}]}`; the AjaxResult additionally carries top-level `"candidate":true` and response header `X-Chengyin-Candidate: city-transactional-map`.
- Errors: 400 CITY_MAP_QUERY_INVALID; 401 UNAUTHORIZED; 409 CITY_ORDERED_RESET_REQUIRED (stale/foreign cursor, permissions changed, too many events; client must re-read snapshot); 422 CITY_QUERY_TOO_BROAD; 503 CITY_ORDERED_READ_NOT_APPROVED | CITY_ORDERED_UNAVAILABLE; plus CITY_MAP_QUERY_INVALID / CITY_SNAPSHOT_CHANGED from the snapshot source. The `msg` for these is a fixed Chinese string ("增量未完成；请重新读取完整当前快照，不会重发任何业务动作"), `errorCode` is the code.
- Flags: `CityOrderedConfiguration()` public ctor = writer/reader/jobs/cleanup all false -> `readEnabled()` false; its enabling ctor is package-private; `CityOrderedMapAPIHost` enabling ctor is package-private too. So via the public API this route can only ever return 503 `CITY_ORDERED_READ_NOT_APPROVED`, even if registered (not "default-off", structurally closed).
- Idempotency: none, but each call may write private transport rows (stream/inbox) inside its own transaction.
- iOS: Core/CityOrderedMapScopedTransport.swift:76 (request build `make`, GET, `Authorization`, `Accept`), route allowlist :49-60.
- SYNTHETIC req `GET /api/city-game/state/deltas?regionId=city-1&boardId=b1&seasonId=s1&rulesReleaseId=r1&revision=3&south=30.0&west=120.0&north=30.1&east=120.1&datum=GCJ02&zoom=15&layers=MERCHANT,POI&limit=50&sync=TRANSACTIONAL_EVENTS_V1&cursor=11111111-2222-4333-8444-555555555555.4` ; res (if it were open) `{"code":200,"msg":"操作成功","data":{"contract":"CITY_TRANSACTIONAL_MAP_V1","kind":"DELTAS","afterSequence":4,"sequence":5,"cursor":"11111111-....5","batches":[]},"candidate":true}`; actual today `{"code":503,"msg":"增量未完成；请重新读取完整当前快照，不会重发任何业务动作","errorCode":"CITY_ORDERED_READ_NOT_APPROVED","candidate":true}` (message text per CityOrderedReadService.fail only for its own failures; the Host's own 503 uses `fail(503,code)` whose msg == code: `{"code":503,"msg":"CITY_ORDERED_READ_NOT_APPROVED",...}`).

## Row 37 (adjacent, not counted)  GET /api/city-game/state/snapshot (sync variant)
C/CityOrderedMapMVCAdapter.java:16; iOS Core/CityOrderedMapScopedTransport.swift:76 (when `cursor == nil`). Same flag/auth/closure as row 36; query = row 36 minus `cursor`; a `cursor` here -> 400 CITY_MAP_QUERY_INVALID; success `kind:"SNAPSHOT"`, `snapshot`, `versions`. Listed only because the adapter and the iOS path pair belong together.

---

## Discrepancies vs the BE reports (for the integrator)
1. G06 report says the iOS call sites could not be compared; they exist on wip/wave5-build and are cited above. All of acquisition/action-budget/arrival/neutral/onsite/merchant/player-rules/state-deltas have real Swift callers (only action-budget `result/{id}` has none).
2. G07 report states merchant/operations, player-rules, state/deltas EXISTS; the code confirms they are method-only (no mapping, no registration helper) and the ordered-map route is structurally closed (package-private enabling constructors), not merely default-off. G06 report's "10 EXISTS" omits several adapter routes (acquisition/titles+quote+state, arrival/merchant+evidence+state, action-budget/result).
3. G04/G05 reports say iOS has no real call site for channels/club notices/etc.: confirmed for `/api/club/channels` (label only). The G05 `post/operation/receipt` has a second, dormant legacy iOS caller (ClubCommunityPendingJournal.swift:410) whose body lacks `receiptNamespace`; the backend would answer 400 CLUB_POST_ORIGINAL_INVALID. Series `original-result` errors use Chinese `msg` strings (serviceError), unlike other club routes which use code strings in `msg`.

---

# Route table part: G08, G09, G10 (static extraction)

Source: /home/user/chengyin on branch `cloud/rt-01` (= origin/claude/be-v2-fixes), HEAD 537e43c74. iOS: /home/user/ios-w5 (origin/wip/wave5-build, 3f4f6053). Nothing was compiled or run; everything below is read from code. Anything not provable from code is marked UNKNOWN. All JSON examples are SYNTHETIC (derived from code shape, not captured traffic).

Total routes: **36** (G08 = 8, G09 = 10, G10 = 18: 12 in `ApiRewardPledgeG10Controller` + 6 in `ApiRewardPledgeG19Controller`, which share the `/api/reward-pledge` prefix and which the G10 report attributes to G10).

Controller dir (abbrev `CD`): `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`

## Cross-cutting facts (apply to every route unless the route block says otherwise)

**Auth.** None of `/api/friend/**` or `/api/reward-pledge/**` is in `SecurityConfig` permitAll lists (`chengyinhub-framework/.../config/SecurityConfig.java:133-163`; last rule `anyRequest().authenticated()`, line ~166), and no controller uses an anonymous annotation. So: token REQUIRED, guest NOT allowed. `JwtAuthenticationTokenFilter` takes the `/api` path branch and resolves `LoginAppUser` from the `Authorization` header (`token.header: Authorization`, application.yml:115) via redis (`AppTokenService.getLoginAppUser`). Viewer id = `BaseController.getAppUserId()` (BaseController.java:222) = token member id; never read from body/query. iOS sends the raw token string in `Authorization` (no "Bearer " prefix seen in Swift; whether the server also accepts a prefix: UNKNOWN, not read). Missing/invalid token: iOS comments say HTTP 401 + `{code:401}` from the entry point (not verified here).

**Envelope.** `AjaxResult` = `{"code":int,"msg":string,"data":any}`; success `code:200,msg:"操作成功"` and `data` present when non-null. Errors are returned as `AjaxResult` with the business code in `code` and the stable string in `msg`; neither `@ResponseStatus` nor an advice sets the HTTP status (only `PlayCompatibilityAdviceG37`, not applicable), so HTTP status is expected to be 200 for every business error (UNKNOWN at runtime; inferred from `GlobalExceptionHandler.handleServiceException`, lines 130-143). `msg` goes through `UserSafeMessage.of` for non-200 codes (strings like `FRIEND_VERSION_CONFLICT` pass; text >120 chars or leak-patterns become "系统繁忙，请稍后重试").

**Unhandled input faults (all routes).** Missing required query param, non-numeric `peer_id`, or missing/unreadable `@RequestBody` are not handled by a route-specific handler; they fall to `GlobalExceptionHandler` generic handlers which return `code:500` with a sanitized message (handlers at lines 159, 178, 190). Exact msg UNKNOWN.

**Friend (G08/G09) body handling.** POST bodies are bound as raw `@RequestBody String` and parsed with Jackson `readTree`; the object must contain exactly the required keys plus optional keys; any unknown key (including the iOS `source_type`/`source_id`/`source_generation` fields that iOS adds only when `command.source != nil`) gives `400 FRIEND_INVALID_REQUEST`. `Content-Type` is not constrained by the mapping (no `consumes`); iOS sends `application/json`, also on GET. `request_id` must be a 36-char UUID string, stored lower-cased; receipts live in `friend_receipt_g08` keyed (viewer, action, request_id). Replaying the same request_id with the same payload hash returns the stored receipt; a different hash gives `409 REQUEST_ID_CONFLICT`. No special HTTP headers required beyond `Authorization`. Feature flag: NONE (G08/G09 controllers are unconditional `@RestController`). Tables are created by `migration_g08_20261108.sql` (not verified applied).

**Friend error mapping.** `ServiceException(msg, code)` -> envelope `{code, msg}`. iOS (NativeFriendService.swift:~150) treats `409 REQUEST_ID_CONFLICT` as unknown outcome.

**Pledge (G10/G19) cross-cutting.** Both controllers are `@ConditionalOnProperty(chengyin.pledge-v1.enabled=true, matchIfMissing=false)`: **default OFF -> the routes are not registered** (an authenticated call would hit the not-found handler, 404). `PledgeV1Availability` reads `${chengyin.pledge-v1.enabled:false}`; every service method also calls `availability.requireEnabled()` (throws `PledgeRejection("PLEDGE_V1_DISABLED")`). No property is set in application*.yml in the repo (grep found only the code defaults). Store/owner/principal come from `IMerchantAccessService.require(getAppUserId(), permission)`: failure throws `ServiceException("商家身份无效或权限不足", 403)` (MerchantAccessServiceImpl.java:97-98) -> envelope `code:403`. Inside `run(...)`, `PledgeRejection(code)` becomes `AjaxResult.error(httpLike(code), code)` with mapping NOT_FOUND->404, FORBIDDEN->403, INVALID_INPUT/NOT_CONFIRM->400, everything else->409 (`code(String)` G10:194-199 and G19:111-116); `msg` = the rejection string. `PledgeRejection` thrown OUTSIDE `run` (draft's `principal(ctx)`, any `store()` null-ctx check, `availability.requireEnabled()` in the controller) is a RuntimeException -> generic handler -> `code:500`, `msg` = the string (e.g. "FORBIDDEN").
Request encoding: JSON bodies where stated (iOS sets `Content-Type: application/json`); POSTs with no body (submit, confirm, hold, withdraw, return-to-pool) take only the path variable and no `@RequestBody`. No idempotency header anywhere; idempotency is by business key stored in the ops table (`w17_reward_pledge_op`: op + key), described per route. Policy gates read `mapper.findPolicy(code, ruleVersion)`; a missing row = closed (`POLICY_CLOSED`, code 409).
Stock-bearing responses embed `Stock` rows serialized from public fields: `versionId, quantity, available, reserved, awardedUnredeemed, redeemed, expired, frozenUnits, withdrawn, versionNo`.

---

## Route table

| # | Grp | Method | Full path | Controller:line | Auth | Request enc. | iOS caller |
|---|---|---|---|---|---|---|---|
| 1 | G08 | GET | /api/friend/list | ApiFriendG08Controller.java:15 | token | query | Core/NativeFriendService.swift:53 |
| 2 | G08 | POST | /api/friend/accept | ApiFriendG08Controller.java:19 | token | JSON | Core/NativeFriendService.swift:97 |
| 3 | G08 | POST | /api/friend/cancel | ApiFriendG08Controller.java:21 | token | JSON | Core/NativeFriendService.swift:97 |
| 4 | G08 | GET | /api/friend/directory | ApiFriendG08Controller.java:24 | token | query | Core/NativeFriendDirectoryService.swift:43 |
| 5 | G08 | GET | /api/friend/directory/detail | ApiFriendG08Controller.java:30 | token | query | Core/NativeFriendDirectoryService.swift:63 |
| 6 | G08 | GET | /api/friend/group/list | ApiFriendG08Controller.java:35 | token | none | Core/NativeFriendMetadataService.swift:62 |
| 7 | G08 | POST | /api/friend/group/save | ApiFriendG08Controller.java:37 | token | JSON | Core/NativeFriendMetadataService.swift:69 |
| 8 | G08 | POST | /api/friend/group/delete | ApiFriendG08Controller.java:39 | token | JSON | Core/NativeFriendMetadataService.swift:69 |
| 9 | G09 | GET | /api/friend/relationship | ApiFriendG09Controller.java:15 | token | query | Core/NativeFriendService.swift:81; Core/NativeFriendRemovalService.swift:48 |
| 10 | G09 | GET | /api/friend/receipt | ApiFriendG09Controller.java:19 | token | query | Core/NativeFriendService.swift:102 |
| 11 | G09 | POST | /api/friend/reject | ApiFriendG09Controller.java:24 | token | JSON | Core/NativeFriendService.swift:97 |
| 12 | G09 | GET | /api/friend/metadata | ApiFriendG09Controller.java:27 | token | query | Core/NativeFriendMetadataService.swift:57 |
| 13 | G09 | POST | /api/friend/remark | ApiFriendG09Controller.java:31 | token | JSON | Core/NativeFriendMetadataService.swift:69 |
| 14 | G09 | GET | /api/friend/metadata/receipt | ApiFriendG09Controller.java:33 | token | query | Core/NativeFriendMetadataService.swift:74 |
| 15 | G09 | POST | /api/friend/metadata/settle | ApiFriendG09Controller.java:38 | token | JSON | NONE (path constant at NativeFriendMetadataService.swift:17 only; `settle()` at :77 throws notSent) |
| 16 | G09 | GET | /api/friend/removal/receipt | ApiFriendG09Controller.java:41 | token | query | Core/NativeFriendRemovalService.swift:66 |
| 17 | G09 | POST | /api/friend/removal/settle | ApiFriendG09Controller.java:46 | token | JSON | NONE (constant at NativeFriendRemovalService.swift:14 only; `settle()` at :57 throws notSent) |
| 18 | G09 | GET | /api/friend/progress | ApiFriendG09Controller.java:49 | token | query | Core/NativeFriendProgressService.swift:55 |
| 19 | G10 | POST | /api/reward-pledge/drafts | ApiRewardPledgeG10Controller.java:50 | token + merchant COUPON_MANAGE | JSON | Core/RewardPledge.swift:383 (build), :987 (send); App/RewardPledgeViews.swift:646 |
| 20 | G10 | POST | /api/reward-pledge/{pledgeId}/submit | ApiRewardPledgeG10Controller.java:60 | token + COUPON_MANAGE | none | Core/RewardPledge.swift:412/:990; App/RewardPledgeViews.swift:656 |
| 21 | G10 | POST | /api/reward-pledge/{pledgeId}/confirm | ApiRewardPledgeG10Controller.java:67 | token + COUPON_MANAGE | none | Core/RewardPledge.swift:415/:993; App/RewardPledgeViews.swift:662 |
| 22 | G10 | POST | /api/reward-pledge/{pledgeId}/freeze | ApiRewardPledgeG10Controller.java:74 | token + BASIC_READ (+policy REVIEWER/RULE) | JSON | Core/RewardPledge.swift:423/:1002; App/RewardPledgeViews.swift:728,742 |
| 23 | G10 | GET | /api/reward-pledge/{pledgeId} | ApiRewardPledgeG10Controller.java:82 | token + COUPON_MANAGE | path | Core/RewardPledge.swift:418/:996; App/RewardPledgeViews.swift:668 |
| 24 | G10 | GET | /api/reward-pledge/{pledgeId}/stats | ApiRewardPledgeG10Controller.java:89 | token + COUPON_MANAGE | path | Core/RewardPledge.swift:447/:1023; App/RewardPledgeViews.swift:777 |
| 25 | G10 | POST | /api/reward-pledge/awards/{awardId}/return-to-pool | ApiRewardPledgeG10Controller.java:96 | token + COUPON_MANAGE (+policy RETURN_TO_POOL) | none | Core/RewardPledge.swift:435/:1014; App/RewardPledgeViews.swift:802 |
| 26 | G10 | GET | /api/reward-pledge/fulfilment/awards | ApiRewardPledgeG10Controller.java:105 | token + merchant VERIFY | none | Core/RewardPledge.swift:336/:951; App/RewardPledgeViews.swift:266 |
| 27 | G10 | POST | /api/reward-pledge/fulfilment/resolve | ApiRewardPledgeG10Controller.java:112 | token + VERIFY | JSON | Core/RewardPledge.swift:349/:954; App/RewardPledgeViews.swift:287 |
| 28 | G10 | POST | /api/reward-pledge/fulfilment/preview | ApiRewardPledgeG10Controller.java:125 | token + VERIFY | JSON | Core/RewardPledge.swift:303/:981; App/RewardPledgeViews.swift:276,430 |
| 29 | G10 | POST | /api/reward-pledge/fulfilment/redeem | ApiRewardPledgeG10Controller.java:135 | token + VERIFY | JSON | Core/RewardPledge.swift:308/:984; App/RewardPledgeViews.swift:443 |
| 30 | G10 | POST | /api/reward-pledge/fulfilment/expire | ApiRewardPledgeG10Controller.java:145 | token + VERIFY | JSON | Core/RewardPledge.swift:432/:1011; App/RewardPledgeViews.swift:790 |
| 31 | G10* | GET | /api/reward-pledge/pledges | ApiRewardPledgeG19Controller.java:38 | token + COUPON_MANAGE | none | Core/RewardPledge.swift:277/:960; App/RewardPledgeViews.swift:677 |
| 32 | G10* | GET | /api/reward-pledge/review | ApiRewardPledgeG19Controller.java:45 | token + BASIC_READ (+policy REVIEWER) | none | Core/RewardPledge.swift:280/:963; App/RewardPledgeViews.swift:715 |
| 33 | G10* | GET | /api/reward-pledge/review/{versionId} | ApiRewardPledgeG19Controller.java:52 | token + BASIC_READ (+policy REVIEWER) | path | Core/RewardPledge.swift:283/:966; App/RewardPledgeViews.swift:729 |
| 34 | G10* | GET | /api/reward-pledge/ops/{op}/{key} | ApiRewardPledgeG19Controller.java:59 | token + COUPON_MANAGE | path | Core/RewardPledge.swift:409/:999; App/RewardPledgeViews.swift:698,704,755,768,792 |
| 35 | G10* | POST | /api/reward-pledge/versions/{versionId}/hold | ApiRewardPledgeG19Controller.java:67 | token + COUPON_MANAGE (+policy STORE_HOLD) | none | Core/RewardPledge.swift:426/:1005; App/RewardPledgeViews.swift:753 |
| 36 | G10* | POST | /api/reward-pledge/versions/{versionId}/withdraw | ApiRewardPledgeG19Controller.java:74 | token + COUPON_MANAGE | none | Core/RewardPledge.swift:429/:1008; App/RewardPledgeViews.swift:766 |

`G10*` = lives in `ApiRewardPledgeG19Controller` (same `/api/reward-pledge` prefix, same flag), counted in the G10 route family because iOS calls it under the G10 prefix and the G10 controller's comment (line 47) says these live only in G19.
Bare prefixes `/api/reward-pledge`, `/api/reward-pledge/awards`, `/api/friend/`: no route of their own. Spring literal-over-variable precedence resolves `GET /pledges` and `GET /review` against `GET /{pledgeId}` (resolution not run).

---

# G08 route details (service: `chengyinhub-system/.../service/impl/FriendG08ServiceImpl.java`, hashes: `.../support/FriendG08Hashes.java`)

### 1. GET /api/friend/list
- Controller: ApiFriendG08Controller.java:15-18 -> `FriendG08ServiceImpl.list` (:105)
- Auth: token required; viewer = token member.
- Encoding: query. `cursor` long, optional, default 0 (must be >= 0; it is an edge id: "friends with edge id > cursor"); `limit` int, optional, default 50, must be 1..100 else 400 (effective page size is min(limit, 50)).
- Success `data`: `{viewer_id:long, incoming:[], outgoing:[] (always empty), friends:[Item], has_more:bool, next_cursor:long|null (last edge_id of page when has_more), groups:{viewer_id, list:[Group]}}`. `Item` = `{peer_id:long, nickname:string, state:1, version:long (edge version), msg:"", expires_at_ms:0, friend_remark:string|null, group_id:long|null, starred:0|1}`. `Group` = `{id:long (0 = default "未分组"), name, position:int, version:long, is_default:0|1, friend_count:long}`.
- Errors: 400 `FRIEND_INVALID_REQUEST` (cursor<0, limit out of 1..100).
- Idempotency: read-only. Headers: Authorization only. Flag: none.
- iOS caller: Core/NativeFriendService.swift:53 (`read(requests ? "requests" : "list", cursor, limit=50)`).
- Example (SYNTHETIC) request: `GET /api/friend/list?cursor=0&limit=50` -> 
```json
{"code":200,"msg":"操作成功","data":{"viewer_id":101,"incoming":[],"outgoing":[],"friends":[{"peer_id":202,"nickname":"A","state":1,"version":3,"msg":"","expires_at_ms":0,"friend_remark":null,"group_id":null,"starred":0}],"has_more":false,"next_cursor":null,"groups":{"viewer_id":101,"list":[{"id":0,"name":"未分组","position":0,"version":0,"is_default":1,"friend_count":1}]}}}
```
- Note: `nickname` is built with `String.valueOf(r.get("nickname"))`, so a NULL nickname serializes as the string "null".

### 2. POST /api/friend/accept  and 3. POST /api/friend/cancel
- Controller: ApiFriendG08Controller.java:19-20 / :21-22 -> `transition(viewer, body, action)` (:129). Both `@Transactional`.
- Auth: token; viewer = token member. accept: viewer must be the TARGET of a PENDING request from `peer_id`; cancel: viewer must be the REQUESTER of a pending request to `peer_id`.
- Encoding: JSON body (raw string). Required keys: `peer_id` (integer >0, != viewer), `request_id` (UUID string, 36 chars), `msg` (string, must be exactly `""`), `expected_version` (integer >0). Optional: `review_id` (integer >0, only legal for cancel). Any other key -> 400.
- Success `data` (and stored receipt): `{viewer_id, peer_id, action:"accept"|"cancel", request_id, outcome:"APPLIED", payload_hash:<64 hex, "friend-command-v1" length-prefixed SHA-256 over peer, action, "", expected_version, review_id>, relationship:{viewer_id, peer_id, state:1|0, version:long, conversation_id:null}, review:null}`. accept -> relationship.state 1 with edge version; cancel -> state 0 with request version.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 404 `FRIEND_REQUEST_NOT_FOUND` (no pending request), `FRIEND_REVIEW_NOT_FOUND` (any `review_id` given, always, this backend has no review stage), `FRIEND_NOT_FOUND` (accept: viewer's member row missing); 409 `FRIEND_VERSION_CONFLICT` (expected_version != request version, or CAS close failed), `FRIEND_REQUEST_EXPIRED` (accept only; request is closed EXPIRED... note: that close is inside a transaction that then throws, so it is probably rolled back; UNKNOWN), `REQUEST_ID_CONFLICT` (same id, different hash); 500 `FRIEND_RECEIPT_CORRUPT`/`FRIEND_RECEIPT_FAILED`.
- Idempotency: `request_id` in body, checked FIRST via `replay` (receipt by viewer+action+request_id) before any state read. Headers: Authorization only. Flag: none.
- iOS caller: Core/NativeFriendService.swift:97 (`exchange(command.action.rawValue, body)`, POST JSON; suffix is the action name). The same write path also serves `request`/`reject`; iOS adds `source_type/source_id/source_generation` only when `command.source` is set (would be 400 here for accept/cancel).
- Example (SYNTHETIC): request `POST /api/friend/accept` `{"peer_id":202,"request_id":"2f6b0c1e-5a3d-4c11-9a43-0d1c2b3a4e5f","msg":"","expected_version":1}` -> 
```json
{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"action":"accept","request_id":"2f6b0c1e-5a3d-4c11-9a43-0d1c2b3a4e5f","outcome":"APPLIED","payload_hash":"<64 hex>","relationship":{"viewer_id":101,"peer_id":202,"state":1,"version":1,"conversation_id":null},"review":null}}
```

### 4. GET /api/friend/directory
- Controller: ApiFriendG08Controller.java:24-29 -> `directory` (:170).
- Auth: token.
- Encoding: query. `section` string REQUIRED, one of `together|recent|all`; `starred` boolean optional default false; `limit` int optional default 50 and MUST equal 50 else 400; `group_id` long optional (>=0; 0 = ungrouped; >0 must exist in viewer's groups else 404); `cursor` string optional (`[A-Za-z0-9_-]+`, <=128 chars; format `<first 32 hex of revision>_<edge_id>`).
- Success `data`: `{viewer_id, section, group_id:long|null, starred_only:bool, revision:<64 hex>, groups:{viewer_id,list:[Group]}, counts:{all,recent,together:int}, total:int, items:[Item], has_more:bool, next_cursor:string|null}`. `together` is always 0 and its rows empty; `recent` = befriended within 30 days; page size 50 (Item/Group shapes as in route 1).
- Errors: 400 `FRIEND_INVALID_REQUEST` (bad section/limit/group_id<0/cursor malformed); 404 `DIRECTORY_GROUP_NOT_FOUND`; 409 `DIRECTORY_CHANGED` (cursor revision prefix is well-formed 32-hex but != current); 503 `FRIEND_DIRECTORY_BOUND_EXCEEDED` (viewer has >500 friends).
- Idempotency: none (read). Flag: none.
- iOS caller: Core/NativeFriendDirectoryService.swift:43.
- Example (SYNTHETIC): `GET /api/friend/directory?section=all&starred=false&limit=50` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"section":"all","group_id":null,"starred_only":false,"revision":"<64 hex>","groups":{"viewer_id":101,"list":[...]},"counts":{"all":1,"recent":1,"together":0},"total":1,"items":[{"peer_id":202,"nickname":"A","state":1,"version":3,"msg":"","expires_at_ms":0,"friend_remark":null,"group_id":null,"starred":0}],"has_more":false,"next_cursor":null}}`

### 5. GET /api/friend/directory/detail
- Controller: ApiFriendG08Controller.java:30-33 -> `directoryDetail` (:221).
- Encoding: query `peer_id` long REQUIRED (>0, != viewer).
- Success `data`: `{viewer_id, item:Item, conversation_id:null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 404 `FRIEND_NOT_FOUND` (not an active friend).
- Idempotency: none. Flag: none. iOS caller: Core/NativeFriendDirectoryService.swift:63.
- Example (SYNTHETIC): `GET /api/friend/directory/detail?peer_id=202` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"item":{"peer_id":202,"nickname":"A","state":1,"version":3,"msg":"","expires_at_ms":0,"friend_remark":"Ann","group_id":7,"starred":1},"conversation_id":null}}`

### 6. GET /api/friend/group/list
- Controller: ApiFriendG08Controller.java:35-36 -> `groupList` (:232). No params.
- Success `data`: `{viewer_id, list:[Group]}` (index 0 is the synthetic default group `id:0,name:"未分组",position:0,version:0,is_default:1`; custom groups follow, `is_default:0`).
- Errors: none from service beyond generic. Idempotency: none. Flag: none.
- iOS caller: Core/NativeFriendMetadataService.swift:62.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"list":[{"id":0,"name":"未分组","position":0,"version":0,"is_default":1,"friend_count":0},{"id":7,"name":"同学","position":1,"version":2,"is_default":0,"friend_count":3}]}}`

### 7. POST /api/friend/group/save
- Controller: ApiFriendG08Controller.java:37-38 -> `groupSave` (:248), `@Transactional`.
- Encoding: JSON. Required keys (all must be present): `id` (integer>0 to update, or JSON `null` to create), `name` (string; trimmed, NFC; 1..12 code points; no ISO control chars), `position` (integer >=0), `expected_version` (integer; must be 0 when `id` is null, >0 when `id` given), `request_id` (UUID). No optional keys.
- Success `data` (receipt, always HTTP/envelope 200 even for domain rejection): `{viewer_id, request_id, action:"group_save", target_id:long (0 for create), outcome:"APPLIED"|"REJECTED", reason:string|null, payload_hash:<64 hex, "friend-metadata-v1" fingerprint of the body>, current:null, groups:{viewer_id,list:[Group]}|null (only when APPLIED)}`. `reason` in {`GROUP_LIMIT` (19 custom groups max), `GROUP_NAME_TAKEN`, `GROUP_NOT_FOUND`, `VERSION_CONFLICT`}.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT`; 500 `FRIEND_RECEIPT_FAILED`. Rejections are stored as receipts (replayed on same request_id).
- Idempotency: `request_id` in body (replay checked before write). Flag: none.
- iOS caller: Core/NativeFriendMetadataService.swift:69 (path from Core/NativeFriendMetadataContracts.swift:46).
- Example (SYNTHETIC): `{"id":null,"name":"同学","position":1,"expected_version":0,"request_id":"6b1f5d0a-7c2e-4a1b-8d3e-9f0a1b2c3d4e"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"request_id":"6b1f5d0a-7c2e-4a1b-8d3e-9f0a1b2c3d4e","action":"group_save","target_id":0,"outcome":"APPLIED","reason":null,"payload_hash":"<64 hex>","current":null,"groups":{"viewer_id":101,"list":[...]}}}`

### 8. POST /api/friend/group/delete
- Controller: ApiFriendG08Controller.java:39-40 -> `groupDelete` (:284), `@Transactional`.
- Encoding: JSON. Required keys: `id` (integer>0), `move_to_group_id` (integer>0 or `null`; must differ from `id`), `expected_version` (integer>0), `request_id` (UUID).
- Success `data`: same receipt shape as route 7 with `action:"group_delete"`, `target_id:id`; `reason` in {`GROUP_NOT_FOUND`, `VERSION_CONFLICT`, `MOVE_TARGET_NOT_FOUND`}.
- Errors / idempotency / flag: as route 7. iOS caller: Core/NativeFriendMetadataService.swift:69.
- Example (SYNTHETIC): `{"id":7,"move_to_group_id":null,"expected_version":2,"request_id":"0a9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"request_id":"0a9e8d7c-...","action":"group_delete","target_id":7,"outcome":"APPLIED","reason":null,"payload_hash":"<64 hex>","current":null,"groups":{...}}}`

---

# G09 route details (service: `.../service/impl/FriendG09ServiceImpl.java`, hashes `.../support/FriendG09Hashes.java`)

### 9. GET /api/friend/relationship
- Controller: ApiFriendG09Controller.java:15-18 -> `relationship` (:87).
- Encoding: query `peer_id` long REQUIRED (>0, != viewer).
- Success `data`: `{viewer_id, peer_id, state:0|1|2|3 (0 none/removed/blocked-projected, 1 friend, 2 viewer sent pending, 3 viewer received pending), version:long (edge or request version; 0 if no edge), conversation_id:null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`. Idempotency: none. Flag: none.
- iOS caller: Core/NativeFriendService.swift:81; Core/NativeFriendRemovalService.swift:48.
- Example (SYNTHETIC): `GET /api/friend/relationship?peer_id=202` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"state":1,"version":3,"conversation_id":null}}`

### 10. GET /api/friend/receipt
- Controller: ApiFriendG09Controller.java:19-23 -> `receipt` (:101).
- Encoding: query: `peer_id` long REQUIRED (>0,!=viewer); `action` string REQUIRED in {`request`,`accept`,`reject`,`cancel`}; `request_id` string REQUIRED (UUID).
- Success `data`: the stored receipt of that action (shape as routes 2/3/11), or when none stored `{viewer_id, peer_id, action, request_id, outcome:"UNKNOWN", payload_hash:null, relationship:null, review:null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT` (stored receipt's peer_id differs).
- Idempotency: reads receipts by (viewer, action, request_id). Flag: none. iOS caller: Core/NativeFriendService.swift:102.
- Example (SYNTHETIC): `GET /api/friend/receipt?peer_id=202&action=accept&request_id=2f6b0c1e-5a3d-4c11-9a43-0d1c2b3a4e5f` -> unknown case `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"action":"accept","request_id":"2f6b0c1e-...","outcome":"UNKNOWN","payload_hash":null,"relationship":null,"review":null}}`

### 11. POST /api/friend/reject
- Controller: ApiFriendG09Controller.java:24-25 -> `reject` (:118), `@Transactional`.
- Encoding: JSON; required exactly `peer_id` (int>0,!=viewer), `request_id` (UUID), `msg` (must be `""`), `expected_version` (int>0); no optional keys. (Note: `review_id` is NOT accepted here, unlike accept/cancel.)
- Success `data`: `{viewer_id, peer_id, action:"reject", request_id, outcome:"APPLIED", payload_hash:<"friend-command-v1" hash>, relationship:{viewer_id,peer_id,state:0,version:<request version>,conversation_id:null}, review:null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 404 `FRIEND_REQUEST_NOT_FOUND` (only the target of a PENDING request from `peer_id` can reject); 409 `FRIEND_VERSION_CONFLICT`, `REQUEST_ID_CONFLICT`.
- Idempotency: `request_id` in body (replay first). Flag: none. iOS caller: Core/NativeFriendService.swift:97.
- Example (SYNTHETIC): `{"peer_id":202,"request_id":"3c2b1a09-8f7e-4d6c-9b5a-4e3d2c1b0a9f","msg":"","expected_version":1}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"action":"reject","request_id":"3c2b1a09-...","outcome":"APPLIED","payload_hash":"<64 hex>","relationship":{"viewer_id":101,"peer_id":202,"state":0,"version":2,"conversation_id":null},"review":null}}`

### 12. GET /api/friend/metadata
- Controller: ApiFriendG09Controller.java:27-30 -> `metadata` (:162).
- Encoding: query `peer_id` long REQUIRED.
- Success `data`: `{viewer_id, peer_id, friend_version:long (edge version), version:long (meta version, 0 if no row), remark:string|null, group_id:long|null, starred:0|1, notification_effect:"NOT_CONNECTED", progress_scope:0|1|null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 404 `FRIEND_NOT_FOUND` (not an active friend). Idempotency: none. Flag: none.
- iOS caller: Core/NativeFriendMetadataService.swift:57.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"friend_version":3,"version":2,"remark":"Ann","group_id":7,"starred":1,"notification_effect":"NOT_CONNECTED","progress_scope":1}}`

### 13. POST /api/friend/remark
- Controller: ApiFriendG09Controller.java:31-32 -> `remark` (:183), `@Transactional`.
- Encoding: JSON. Required: `peer_id` (int>0,!=viewer), `request_id` (UUID), `expected_version` (int>=0, meta version), `expected_friend_version` (int>0). Optional (at least one MUST be present): `remark` (string 1..30 code points after trim/NFC, no ISO control; or null to clear), `starred` (0|1), `group_id` (int>0 or null), `progress_scope` (0|1 or null). Only keys present are changed.
- Success `data` (receipt, envelope 200 even if REJECTED): `{viewer_id, request_id, action:"remark", target_id:peer_id, outcome:"APPLIED"|"REJECTED", reason:string|null, payload_hash:<"friend-metadata-v1" fingerprint>, current:<route-12 shape>|null (APPLIED only), groups:null}`. `reason` in {`FRIEND_NOT_FOUND`, `STALE_FRIEND_VERSION`, `VERSION_CONFLICT`, `GROUP_NOT_FOUND`, `STAR_LIMIT_REACHED` (20 starred)}. Rejections are stored as receipts.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT`.
- Idempotency: `request_id` in body; replay first. Flag: none. iOS caller: Core/NativeFriendMetadataService.swift:69 (path `api/friend/remark` at NativeFriendMetadataContracts.swift:46).
- Example (SYNTHETIC): `{"peer_id":202,"request_id":"7d6c5b4a-3e2f-4a1b-9c8d-7e6f5a4b3c2d","expected_version":0,"expected_friend_version":3,"remark":"Ann","starred":1}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"request_id":"7d6c5b4a-...","action":"remark","target_id":202,"outcome":"APPLIED","reason":null,"payload_hash":"<64 hex>","current":{"viewer_id":101,"peer_id":202,"friend_version":3,"version":1,"remark":"Ann","group_id":null,"starred":1,"notification_effect":"NOT_CONNECTED","progress_scope":null},"groups":null}}`

### 14. GET /api/friend/metadata/receipt
- Controller: ApiFriendG09Controller.java:33-37 -> `metadataReceipt` (:234).
- Encoding: query: `action` REQUIRED in {`remark`,`group_save`,`group_delete`}; `target_id` long REQUIRED (>=0; 0 only allowed for `group_save`; for `remark` != viewer); `request_id` REQUIRED (UUID).
- Success `data`: stored receipt (shape as routes 7/8/13) or UNKNOWN `{viewer_id, request_id, action, target_id, outcome:"UNKNOWN", reason:null, payload_hash:null, current:null, groups:null}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT` (stored target differs). Idempotency: read of receipts. Flag: none. iOS caller: Core/NativeFriendMetadataService.swift:74.
- Example (SYNTHETIC): `GET /api/friend/metadata/receipt?action=remark&target_id=202&request_id=7d6c5b4a-3e2f-4a1b-9c8d-7e6f5a4b3c2d` -> replay of route-13 body.

### 15. POST /api/friend/metadata/settle
- Controller: ApiFriendG09Controller.java:38-39 -> `metadataSettle` (:257), `@Transactional`.
- Encoding: JSON; required exactly `action` (string in remark|group_save|group_delete), `target_id` (int>=0; 0 only for group_save; remark requires >0 and != viewer), `request_id` (UUID), `payload_hash` (string `^[a-f0-9]{64}$`).
- Behaviour/success `data`: returns the original stored receipt if one exists; otherwise inserts a tombstone receipt `{outcome:"REJECTED", reason:"SETTLED_NOT_APPLIED", ...}` (insert-ignore) so a late arrival cannot apply, and returns it (same shape as route 13 receipt).
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT` (hash or target mismatch); 500 `FRIEND_RECEIPT_FAILED`. Idempotency: request_id in body. Flag: none.
- iOS caller: NONE (constant `settlePath` at Core/NativeFriendMetadataService.swift:17 and a stub `settle()` at :77 that throws `notSent`).
- Example (SYNTHETIC): `{"action":"remark","target_id":202,"request_id":"7d6c5b4a-3e2f-4a1b-9c8d-7e6f5a4b3c2d","payload_hash":"<64 hex>"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"request_id":"7d6c5b4a-...","action":"remark","target_id":202,"outcome":"REJECTED","reason":"SETTLED_NOT_APPLIED","payload_hash":"<64 hex>","current":null,"groups":null}}`

### 16. GET /api/friend/removal/receipt
- Controller: ApiFriendG09Controller.java:41-45 -> `removalReceipt` (:293).
- Encoding: query: `peer_id` long REQUIRED (>0,!=viewer), `expected_version` long REQUIRED (>0, < Long.MAX), `request_id` REQUIRED (UUID).
- Success `data`: `{viewer_id, peer_id, expected_version, request_id, action:"remove", payload_hash:<"friend-removal-v1" hash of peer, expected_version>, outcome:"UNKNOWN"|stored outcome ("APPLIED"|"REJECTED"), reason:string|null, removed_version:long|null, current_relationship:<route-9 shape>}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT` (stored hash/viewer/peer/version mismatch); 503 `RECEIPT_UNAVAILABLE` (APPLIED but removed_version != expected+1).
- Note: nothing on this branch's G08/G09 writes a `remove` receipt; `/api/friend/remove` belongs to `ApiFriendG22Controller` (out of my scope; whether it writes `friend_receipt_g08` action `remove`: UNKNOWN, not read). So this normally returns `UNKNOWN`.
- Idempotency: read. Flag: none. iOS caller: Core/NativeFriendRemovalService.swift:66.
- Example (SYNTHETIC): `GET /api/friend/removal/receipt?peer_id=202&expected_version=3&request_id=9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"expected_version":3,"request_id":"9e8d7c6b-...","action":"remove","payload_hash":"<64 hex>","outcome":"UNKNOWN","reason":null,"removed_version":null,"current_relationship":{"viewer_id":101,"peer_id":202,"state":1,"version":3,"conversation_id":null}}}`

### 17. POST /api/friend/removal/settle
- Controller: ApiFriendG09Controller.java:46-47 -> `removalSettle` (:313), `@Transactional`.
- Encoding: JSON; required exactly `peer_id` (int>0,!=viewer), `expected_version` (int>0), `request_id` (UUID).
- Success `data`: stored removal receipt (shape of route 16) or a tombstone `{outcome:"REJECTED", reason:"RELATIONSHIP_UNAVAILABLE", removed_version:null, ...}`.
- Errors: 400 `FRIEND_INVALID_REQUEST`; 409 `REQUEST_ID_CONFLICT`; 500 `FRIEND_RECEIPT_FAILED`; 503 `RECEIPT_UNAVAILABLE`. Idempotency: request_id in body. Flag: none.
- iOS caller: NONE (constant `settlePath` Core/NativeFriendRemovalService.swift:14; stub `settle()` :57 throws notSent).
- Example (SYNTHETIC): `{"peer_id":202,"expected_version":3,"request_id":"9e8d7c6b-5a4f-4e3d-8c2b-1a0f9e8d7c6b"}` -> route-16 shape with `"outcome":"REJECTED","reason":"RELATIONSHIP_UNAVAILABLE","removed_version":null`.

### 18. GET /api/friend/progress
- Controller: ApiFriendG09Controller.java:49-52 -> `progress` (:336).
- Encoding: query `peer_id` long REQUIRED (>0,!=viewer), `expected_friend_version` long REQUIRED (>0).
- Success `data`: hidden (default): `{viewer_id, peer_id, friend_version, visible:false}`. Visible only when the PEER stored `progress_scope=1` toward the viewer: `{..., visible:true, items:[{id:"t<topic>-a<activity>", title, topicID:long, activityID:long, meter:{visible:true, subjectId:peer, topicId, activityId, required:long, done:long, percent:int, completed:bool, asOf:ISO-8601 instant string, revision:<64 hex>, visibility:{aggregate:"FRIEND", detail:"SELF"}}}]}` (max 50 items, aggregate only).
- Errors: 400 `FRIEND_INVALID_REQUEST`; 404 `FRIEND_NOT_FOUND`; 409 `FRIEND_VERSION_CONFLICT`. Idempotency: none. Flag: none.
- iOS caller: Core/NativeFriendProgressService.swift:55 (request built at :55-60).
- Example (SYNTHETIC): `GET /api/friend/progress?peer_id=202&expected_friend_version=3` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":101,"peer_id":202,"friend_version":3,"visible":false}}`

---

# G10 route details (service: `chengyinhub-system/.../service/rewardpledge/RewardPledgeService.java`; row classes `.../domain/rewardpledge/RewardPledgeRows.java`)

Shared JSON views produced by the service (public-field Jackson serialization, field names as in code):
- **Pledge view** `viewPledge(id)` (:1020): `{pledge:Pledge, version:Version(latest), stock:Stock|null, conserved:bool, guaranteed:false}`. `Pledge` = `{pledgeId, supplyRef, terms, state, storeId, merchantMemberId, couponId, serviceStart, serviceEnd, redeemStart, redeemEnd, createdAt, quantity, minorRestricted}`. `Version` = `{versionId, pledgeId, payloadHash, ruleVersion, state, merchantHash, reviewerHash, terms, versionNo, quantity, minorRestricted, serviceStart, serviceEnd, redeemStart, redeemEnd, merchantMemberId, merchantConfirmedAt, reviewerMemberId, frozenAt}`.
- **Receipt attach** `attach(body,row)`: adds `receipt:{op, key, state ("APPLIED"|"REJECTED"), payloadHash, errorCode, pledgeId, versionId, awardId}` to the body.
- **Award view** `awardView` (:999): `{awardId, requestId, state, historyId, factRef, terms, termsHash, ruleVersion, redeemStart, redeemEnd, serviceEnd, guaranteed:false, blocked:"W06_RESERVATION_ABSENT", useStatus:int (only if historyId != null)}`.
- Time fields are epoch milliseconds (compared with `Date.getTime()` of the coupon).
- Rejection codes seen in the service: `INVALID_INPUT`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `VERSION_CHANGED`, `POLICY_CLOSED`, `CASH_CLOSED`, `COUPON_WINDOW_MISMATCH`, `WINDOW_CLOSED`, `ALREADY_USED`, `PLEDGE_V1_DISABLED`, `SUBJECT_*` (not used by these routes). Only some are persisted for replay (`persistable`: CONFLICT, CASH_CLOSED, COUPON_WINDOW_MISMATCH, INVALID_INPUT, NOT_FOUND).
- **Retry semantics of op routes:** for submit/confirm/hold/withdraw/expire/return-to-pool a SECOND call with an already-APPLIED op row goes through `decided(..., replay=false)` and throws `CONFLICT` (-> envelope 409). Only `drafts` replays an APPLIED result with `replay=true`. The client therefore resolves uncertainty via `GET /ops/{op}/{key}` (route 34).

### 19. POST /api/reward-pledge/drafts
- Controller: ApiRewardPledgeG10Controller.java:50-58 -> `RewardPledgeService.draft` (:122).
- Auth: token + merchant permission `merchant:coupon:manage`; store = `ctx.getMerchantId()`, owner = `ctx.getOwnerMemberId()`, principal = `ctx.getPrincipalMemberId()` (server overrides any body value).
- Encoding: JSON `@RequestBody Draft`. Fields: `requestId` string (optional; if present must match `[A-Za-z0-9_-]{1,64}` and BECOMES the pledgeId; absent -> server UUID), `couponId` long, `supplyRef` string (non-blank, <=128), `terms` string (non-blank, <=128 per `requireText`), `quantity` int (>0), `serviceStart`/`serviceEnd`/`redeemStart`/`redeemEnd` long epoch ms (>0, end > start), `minorRestricted` boolean (optional), `rewardKind` string MUST be `"NON_CASH"`. `storeId`, `merchantMemberId`, `principalMemberId` are overwritten. Redeem window must equal the coupon's start/end time exactly; coupon must belong to this store and owner.
- Success `data`: Pledge view (above) with `receipt` (op `draft`, key = pledgeId, state `APPLIED`, versionId of the new DRAFT v1). Stock null on first draft.
- Errors (envelope code / msg): 400 `INVALID_INPUT`; 403 `FORBIDDEN` (non-owner/other store/ missing principal -> the missing-principal case is 500 `FORBIDDEN` because thrown outside run), also 403 merchant-access failure; 404 `NOT_FOUND` (coupon missing or not this store/owner); 409 `CASH_CLOSED`, `COUPON_WINDOW_MISMATCH`, `CONFLICT` (same requestId, different payload hash); 500 on uncaught.
- Idempotency: `requestId` in body = pledge key; same requestId + same payload returns the existing pledge view with receipt (`replay=true`); op row `draft`/pledgeId. No header.
- Flag: chengyin.pledge-v1.enabled (default false => route absent).
- iOS caller: Core/RewardPledge.swift:383 (builder `RewardPledgeRequests.draft`), :987 (send); App/RewardPledgeViews.swift:646. iOS sends `requestId, couponId, supplyRef, terms, quantity, serviceStart/End, redeemStart/End (same values), rewardKind:"NON_CASH"`.
- Example (SYNTHETIC): `{"requestId":"pl_0001","couponId":55,"supplyRef":"coupon-55","terms":"Free tea","quantity":10,"serviceStart":1790000000000,"serviceEnd":1790864000000,"redeemStart":1790000000000,"redeemEnd":1790864000000,"rewardKind":"NON_CASH"}` -> `{"code":200,"msg":"操作成功","data":{"pledge":{"pledgeId":"pl_0001","state":"DRAFT","storeId":9,"merchantMemberId":101,"couponId":55,"quantity":10,"...":"..."},"version":{"versionId":"<uuid>","pledgeId":"pl_0001","versionNo":1,"state":"DRAFT","payloadHash":"<64 hex>","...":"..."},"stock":null,"conserved":true,"guaranteed":false,"receipt":{"op":"draft","key":"pl_0001","state":"APPLIED","payloadHash":"<64 hex>","errorCode":null,"pledgeId":"pl_0001","versionId":"<uuid>","awardId":null}}}`

### 20. POST /api/reward-pledge/{pledgeId}/submit
- Controller: ApiRewardPledgeG10Controller.java:60-65 -> `submit(owner, pledgeId, principal, store)` (:166 -> :171 with versionId/hash = null).
- Auth: token + `merchant:coupon:manage`; caller must be the pledge's owner (`merchantMemberId == ownerMemberId`) and pledge store == ctx store.
- Encoding: path variable `pledgeId` string; NO body, no query.
- Behaviour: DRAFT -> SUBMITTED (inserts next version row, pledge state SUBMITTED). Uses the latest version ("legacy direct source": no versionId/payloadHash pinning).
- Success `data`: Pledge view (post-change) + `receipt{op:"submit", key:<versionId>, state:"APPLIED", ...}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`; 409 `CONFLICT` (latest version not DRAFT, or repeat of an applied submit); 409 `VERSION_CHANGED` only when versionId passed (not by this route).
- Idempotency: op row (`submit`, versionId); second call => 409 CONFLICT. No header/body key.
- Flag: pledge-v1 (default off). iOS caller: Core/RewardPledge.swift:412 (builder), :990 (send); App/RewardPledgeViews.swift:656.
- Example (SYNTHETIC): `POST /api/reward-pledge/pl_0001/submit` -> `{"code":200,"msg":"操作成功","data":{"pledge":{"pledgeId":"pl_0001","state":"SUBMITTED"},"version":{"versionNo":2,"state":"SUBMITTED"},"stock":null,"conserved":true,"guaranteed":false,"receipt":{"op":"submit","key":"<versionId of v1>","state":"APPLIED","errorCode":null,"pledgeId":"pl_0001","versionId":"<versionId of v1>","awardId":null,"payloadHash":"<64 hex>"}}}`

### 21. POST /api/reward-pledge/{pledgeId}/confirm
- Controller: ApiRewardPledgeG10Controller.java:67-72 -> `confirm(owner, pledgeId, principal, store)` (:202 -> :207).
- Auth/encoding: as route 20 (no body).
- Behaviour: CAS `SUBMITTED -> CONFIRMED` (SQL `WHERE state='SUBMITTED'`), records merchant hash/member id; pledge state CONFIRMED.
- Success `data`: Pledge view + `receipt{op:"confirm", key:<versionId>}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`; 409 `CONFLICT` (not in SUBMITTED, or repeat). Idempotency: op row (`confirm`, versionId). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:415/:993; App/RewardPledgeViews.swift:662.
- Example (SYNTHETIC): `POST /api/reward-pledge/pl_0001/confirm` -> same shape as route 20 with `"state":"CONFIRMED"` and `receipt.op:"confirm"`.

### 22. POST /api/reward-pledge/{pledgeId}/freeze
- Controller: ApiRewardPledgeG10Controller.java:74-80 -> `freeze(principal, pledgeId, ruleVersion, store)` (:241 -> :246).
- Auth: token + `merchant:basic:read`; reviewer = principal member. Also requires policy rows `REVIEWER` (with `actorMemberId` equal to the reviewer) and `RULE`(ruleVersion) both `OPEN`, else 409 `POLICY_CLOSED`.
- Encoding: JSON body `{"ruleVersion": string}` (`Map<String,String>`); blank -> envelope 400 `INVALID_INPUT` (checked before access). Service also requires non-blank, <=128.
- Behaviour: CAS `CONFIRMED -> FROZEN`; reviewer must differ from the confirming merchant member (else 403 `FORBIDDEN`); creates a stock row (`quantity`, `available=quantity`); pledge state FROZEN.
- Success `data`: Pledge view (now including `stock`) + `receipt{op:"freeze", key:<versionId>}`.
- Errors: 400 `INVALID_INPUT`; 403 `FORBIDDEN` (store mismatch / self-review) and merchant-access 403; 404 `NOT_FOUND`; 409 `POLICY_CLOSED`, `CONFLICT`.
- Idempotency: op row (`freeze`, versionId); repeat => 409 `CONFLICT` via `decided`. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:423 (builder), :1002; App/RewardPledgeViews.swift:728, 742.
- Example (SYNTHETIC): `{"ruleVersion":"rule-2026-11"}` -> `{"code":200,"msg":"操作成功","data":{"pledge":{"pledgeId":"pl_0001","state":"FROZEN"},"version":{"state":"FROZEN","ruleVersion":"rule-2026-11"},"stock":{"quantity":10,"available":10,"reserved":0,"awardedUnredeemed":0,"redeemed":0,"expired":0,"frozenUnits":0,"withdrawn":0,"versionNo":1,"versionId":"<uuid>"},"conserved":true,"guaranteed":false,"receipt":{"op":"freeze","state":"APPLIED"}}}`

### 23. GET /api/reward-pledge/{pledgeId}
- Controller: ApiRewardPledgeG10Controller.java:82-87 -> `readPledge(store, owner, pledgeId)` (:629).
- Auth: token + `merchant:coupon:manage`; pledge must be in ctx store AND owned by ctx owner.
- Encoding: path only.
- Success `data`: Pledge view (no `receipt`).
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`. Idempotency: none (read). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:418/:996; App/RewardPledgeViews.swift:668.
- Example (SYNTHETIC): `GET /api/reward-pledge/pl_0001` -> `{"code":200,"msg":"操作成功","data":{"pledge":{...},"version":{...},"stock":null,"conserved":true,"guaranteed":false}}`

### 24. GET /api/reward-pledge/{pledgeId}/stats
- Controller: ApiRewardPledgeG10Controller.java:89-94 -> `stats(store, owner, pledgeId)` (:718 -> `statsFor` :724).
- Auth: token + `merchant:coupon:manage`; same store/owner scoping as route 23.
- Success `data`: `{pledgeId, versionId, versionNo:long|null (stock row's versionNo), asOf:long epoch ms (server clock), awardCount:int, stock:Stock|null, conserved:bool (stock != null && sum == quantity)}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`. Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:447/:1023; App/RewardPledgeViews.swift:777.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"pledgeId":"pl_0001","versionId":"<uuid>","versionNo":1,"asOf":1790000123456,"awardCount":3,"stock":{"quantity":10,"available":7,"awardedUnredeemed":3,"reserved":0,"redeemed":0,"expired":0,"frozenUnits":0,"withdrawn":0},"conserved":true}}`

### 25. POST /api/reward-pledge/awards/{awardId}/return-to-pool
- Controller: ApiRewardPledgeG10Controller.java:96-101 -> `returnToPool(owner, awardId, System.currentTimeMillis())` (:468).
- Auth: token + `merchant:coupon:manage`; policy `RETURN_TO_POOL` must be OPEN else 409 `POLICY_CLOSED` (default closed); pledge owner must equal ctx owner.
- Encoding: path only (no body). `now` is the server clock.
- Behaviour: version FROZEN, now inside [serviceStart, serviceEnd), coupon history unused (useStatus 2), no frozen units; marks award RETURNED and returns stock to pool.
- Success `data`: `{awardId, state:"RETURNED", historyStillPresent:bool, stock:Stock, receipt:{op:"return", key:<awardId>, ...}}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`; 409 `POLICY_CLOSED`, `CONFLICT`, `WINDOW_CLOSED`, `ALREADY_USED`. Idempotency: op row (`return`, awardId); repeat => 409 CONFLICT. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:435/:1014; App/RewardPledgeViews.swift:802.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"awardId":"aw_1","state":"RETURNED","historyStillPresent":true,"stock":{"quantity":10,"available":8},"receipt":{"op":"return","key":"aw_1","state":"APPLIED","awardId":"aw_1"}}}`

### 26. GET /api/reward-pledge/fulfilment/awards
- Controller: ApiRewardPledgeG10Controller.java:105-110 -> `listStore(ctx store)` (:749).
- Auth: token + merchant permission `merchant:verify`; store from session.
- Encoding: none.
- Success `data`: JSON ARRAY of raw `Award` rows (not awardView): `[{awardId, versionId, ruleVersion, rewardScope, factRef, state, requestId, beneficiaryId, createdAt, historyId}]`.
- Errors: merchant-access 403 only (plus generic). Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:336 (builder), :951 (decodes list via `RewardPledgeAwardRow.decodeList`); App/RewardPledgeViews.swift:266. (G10 report: "iOS `RewardPledgeAwardRow` decoding was not checked against the maps"; I did not check it either: UNKNOWN.)
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":[{"awardId":"aw_1","versionId":"<uuid>","ruleVersion":"rule-2026-11","rewardScope":"THEME","factRef":"...","state":"AWARDED","requestId":"rq_1","beneficiaryId":303,"createdAt":1790000100000,"historyId":9001}]}`

### 27. POST /api/reward-pledge/fulfilment/resolve
- Controller: ApiRewardPledgeG10Controller.java:112-123 -> `coupons.verifyCouponQrToken(code.trim())` then `previewByHistory(store, historyId)` (:755).
- Auth: token + `merchant:verify`.
- Encoding: JSON `{"code": string}` (non-blank, <=512 else envelope 400 `INVALID_INPUT`, checked before access check).
- Success `data`: Award view + `previewOnly:true`, `storeId:long`. 
- Errors: 400 `INVALID_INPUT`; 404 `NOT_FOUND` (token does not verify, or history maps to != 1 award, or award missing); 403 `FORBIDDEN` (award's pledge belongs to another store); exceptions from `verifyCouponQrToken` for bad/expired tokens: UNKNOWN (not read). Idempotency: none (preview only). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:349/:954; App/RewardPledgeViews.swift:287.
- Example (SYNTHETIC): `{"code":"<coupon dynamic code>"}` -> `{"code":200,"msg":"操作成功","data":{"awardId":"aw_1","requestId":"rq_1","state":"AWARDED","historyId":9001,"factRef":"...","terms":"Free tea","termsHash":"<64 hex>","ruleVersion":"rule-2026-11","redeemStart":1790000000000,"redeemEnd":1790864000000,"serviceEnd":1790864000000,"guaranteed":false,"blocked":"W06_RESERVATION_ABSENT","useStatus":2,"previewOnly":true,"storeId":9}}`

### 28. POST /api/reward-pledge/fulfilment/preview
- Controller: ApiRewardPledgeG10Controller.java:125-132 -> `preview(store, awardId)` (:409).
- Auth: token + `merchant:verify`. Encoding: JSON `{"awardId": string}` (blank -> 400 `INVALID_INPUT`).
- Success `data`: same as route 27 (`previewOnly:true`, `storeId`).
- Errors: 400 `INVALID_INPUT`; 404 `NOT_FOUND` (award missing or no historyId); 403 `FORBIDDEN` (other store). Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:303/:981; App/RewardPledgeViews.swift:276, 430.
- Example (SYNTHETIC): `{"awardId":"aw_1"}` -> route-27 response shape.

### 29. POST /api/reward-pledge/fulfilment/redeem
- Controller: ApiRewardPledgeG10Controller.java:135-143 -> `fulfil(store, principal, role, awardId)` (:414).
- Auth: token + `merchant:verify`; needs non-blank `ctx.getRoleCode()` else 403 `FORBIDDEN`.
- Encoding: JSON `Map<String,Object>`: `awardId` string (non-blank, else 400 `INVALID_INPUT`), `confirm` must stringify to `"true"` (JSON `true` or `"true"`; iOS sends the string `"true"`) else 400 `NOT_CONFIRM`.
- Behaviour: calls `coupons.redeem(historyId, ownerMember, store, actor, role)` (money-free coupon redeem). `REDEEMED` -> marks version redeemed + intent REDEEMED; `EXPIRED` -> marks expired; `ALREADY_USED` is returned as success; any other enum name is thrown as `PledgeRejection(<name>)` -> envelope 409 with that name (enum values: UNKNOWN, not read).
- Success `data`: Award view + `previewOnly:false`, `storeId`, `redemption:"REDEEMED"|"EXPIRED"|"ALREADY_USED"`, `stock:Stock`, `useStatus:int`.
- Errors: 400 `INVALID_INPUT`/`NOT_CONFIRM`; 403 `FORBIDDEN`; 404 `NOT_FOUND`; 409 other redemption results.
- Idempotency: none by key; the award is single-use through the coupon CAS (`ALREADY_USED` on repeat). No requestId in body. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:308/:984; App/RewardPledgeViews.swift:443.
- Example (SYNTHETIC): `{"awardId":"aw_1","confirm":"true"}` -> route-27 shape with `"previewOnly":false,"redemption":"REDEEMED","stock":{"quantity":10,"redeemed":1,"...":"..."},"useStatus":1`.

### 30. POST /api/reward-pledge/fulfilment/expire
- Controller: ApiRewardPledgeG10Controller.java:145-152 -> `expire(store, principal, awardId, now)` (:436).
- Auth: token + `merchant:verify`. Encoding: JSON `{"awardId": string}` (blank -> 400).
- Behaviour: `coupons.expireUnused(historyId, now)`; if moved, marks version expired.
- Success `data`: `{awardId, expiredNow:bool, useStatus:int, stock:Stock, receipt:{op:"expire", key:<awardId>, ...}}`.
- Errors: 400 `INVALID_INPUT`; 403 `FORBIDDEN` (pledge store != ctx store); 404 `NOT_FOUND`; 409 `CONFLICT` (repeat: op row exists).
- Idempotency: op row (`expire`, awardId). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:432/:1011; App/RewardPledgeViews.swift:790.
- Example (SYNTHETIC): `{"awardId":"aw_1"}` -> `{"code":200,"msg":"操作成功","data":{"awardId":"aw_1","expiredNow":true,"useStatus":3,"stock":{"expired":1},"receipt":{"op":"expire","key":"aw_1","state":"APPLIED"}}}` (`useStatus` value semantic: UNKNOWN beyond 1=used, 2=unused seen in code).

### 31. GET /api/reward-pledge/pledges  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:38-43 -> `listOwned(store, owner)` (:640).
- Auth: token + `merchant:coupon:manage`. Encoding: none; store and owner are not client-named.
- Success `data`: `{pledges:[{pledge:Pledge, versions:[Version]}]}`.
- Errors: 403 `FORBIDDEN`. Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:277/:960; App/RewardPledgeViews.swift:677.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"pledges":[{"pledge":{"pledgeId":"pl_0001","state":"FROZEN"},"versions":[{"versionNo":1,"state":"DRAFT"},{"versionNo":2,"state":"FROZEN"}]}]}}`

### 32. GET /api/reward-pledge/review  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:45-50 -> `reviewQueue(store, principal)` (:658).
- Auth: token + `merchant:basic:read`; policy `REVIEWER` row must be OPEN for this principal else 409 `POLICY_CLOSED`.
- Success `data`: `{store:long, items:[{pledgeId, versionId, payloadHash, state, store}]}` (CONFIRMED versions in the store excluding the caller's own confirmations).
- Errors: 403 `FORBIDDEN`; 409 `POLICY_CLOSED`. Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:280/:963; App/RewardPledgeViews.swift:715.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"store":9,"items":[{"pledgeId":"pl_0001","versionId":"<uuid>","payloadHash":"<64 hex>","state":"CONFIRMED","store":9}]}}`

### 33. GET /api/reward-pledge/review/{versionId}  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:52-57 -> `reviewVersion(store, principal, versionId)` (:681).
- Auth: token + `merchant:basic:read`; policy `REVIEWER` OPEN; reviewer must not be the version's merchant member.
- Success `data`: `{pledgeId, versionId, payloadHash, state, ruleVersion, version:Version, owner:long, reviewer:long, reviewerHash, frozenAt:long|null, store:long}`.
- Errors: 400 `INVALID_INPUT`; 403 `FORBIDDEN`; 404 `NOT_FOUND`; 409 `POLICY_CLOSED`. Idempotency: none. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:283/:966; App/RewardPledgeViews.swift:729.
- Example (SYNTHETIC): `{"code":200,"msg":"操作成功","data":{"pledgeId":"pl_0001","versionId":"<uuid>","payloadHash":"<64 hex>","state":"FROZEN","ruleVersion":"rule-2026-11","version":{...},"owner":101,"reviewer":102,"reviewerHash":"<64 hex>","frozenAt":1790000200000,"store":9}}`

### 34. GET /api/reward-pledge/ops/{op}/{key}  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:59-65 -> `readOp(store, owner, principal, op, key)` (:1165).
- Auth: token + `merchant:coupon:manage`. `op` must be one of `draft|submit|confirm|hold|withdraw|expire|return` else envelope 404 `NOT_FOUND` (checked before access). `key` = business key (draft: pledgeId; submit/confirm/hold/withdraw: versionId; expire/return: awardId); non-blank, <=128.
- Success `data`: `{receipt:{op, key, state ("APPLIED"|"REJECTED"), payloadHash, errorCode, pledgeId, versionId, awardId}}`. Only the original store+owner+principal can read it; otherwise 404 `NOT_FOUND`.
- Errors: 400 `INVALID_INPUT`; 403 `FORBIDDEN`; 404 `NOT_FOUND`. Idempotency: this IS the receipt read. Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:409/:999; App/RewardPledgeViews.swift:698, 704, 755, 768, 792.
- Example (SYNTHETIC): `GET /api/reward-pledge/ops/hold/<versionId>` -> `{"code":200,"msg":"操作成功","data":{"receipt":{"op":"hold","key":"<versionId>","state":"APPLIED","payloadHash":"<64 hex>","errorCode":null,"pledgeId":"pl_0001","versionId":"<versionId>","awardId":null}}}`

### 35. POST /api/reward-pledge/versions/{versionId}/hold  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:67-72 -> `hold(owner, versionId, principal, store)` (:339).
- Auth: token + `merchant:coupon:manage`; policy `STORE_HOLD` must be OPEN else 409 `POLICY_CLOSED`; caller must own the pledge; pledge store == ctx store. Encoding: path only.
- Behaviour: version must be FROZEN with a stock row; `holdAvailable` CAS moves available stock to frozenUnits (exact stock effect per mapper SQL: not read).
- Success `data`: Pledge view + `receipt{op:"hold", key:<versionId>}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`; 409 `POLICY_CLOSED`, `CONFLICT` (not FROZEN / CAS failed / repeat). Idempotency: op row (`hold`, versionId). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:426/:1005; App/RewardPledgeViews.swift:753.
- Example (SYNTHETIC): `POST /api/reward-pledge/versions/<versionId>/hold` -> Pledge view with `receipt.op:"hold"`.

### 36. POST /api/reward-pledge/versions/{versionId}/withdraw  (G19 controller)
- Controller: ApiRewardPledgeG19Controller.java:74-79 -> `withdraw(owner, versionId, principal, store)` (:281).
- Auth: token + `merchant:coupon:manage`; owner-scoped as route 35; no policy gate. Encoding: path only.
- Behaviour: version FROZEN -> WITHDRAWN, available stock -> withdrawn, pledge state WITHDRAWN.
- Success `data`: Pledge view + `receipt{op:"withdraw", key:<versionId>}`.
- Errors: 404 `NOT_FOUND`; 403 `FORBIDDEN`; 409 `CONFLICT`. Idempotency: op row (`withdraw`, versionId). Flag: pledge-v1.
- iOS caller: Core/RewardPledge.swift:429/:1008; App/RewardPledgeViews.swift:766.
- Example (SYNTHETIC): `POST /api/reward-pledge/versions/<versionId>/withdraw` -> Pledge view with `pledge.state:"WITHDRAWN"`, `receipt.op:"withdraw"`.

---

## Discrepancies vs the reports (be-g08/09/10-report.md)

1. **G10 report location error.** Report says `{id}`, `{id}/submit|confirm|freeze|stats`, `pledges`, `review`, `review/{v}`, `ops/{op}/{key}`, `versions/{v}/hold|withdraw` are "same adapter" (G10 controller, "10 group paths"). Code: G10 controller has 12 routes (drafts, {id}/submit, {id}/confirm, {id}/freeze, {id}, {id}/stats, awards/{id}/return-to-pool, fulfilment/awards|resolve|preview|redeem|expire); `pledges`, `review`, `review/{versionId}`, `ops/{op}/{key}`, `versions/{versionId}/hold|withdraw` are in `ApiRewardPledgeG19Controller` (G10 controller line 47 comment says so). Total under the prefix = 18, not 10.
2. **G10 report: freeze/hold/withdraw/submit/confirm "use service overloads that pick the current version".** Confirmed (null versionId/hash). Additional finding the report omits: hold/return/freeze/review depend on policy rows (`STORE_HOLD`, `RETURN_TO_POOL`, `REVIEWER`, `RULE`) that default to closed (409 `POLICY_CLOSED`); and repeat calls of op routes return 409 `CONFLICT` rather than a replay. Report says `chengyin.pledge-v1.enabled` gate: confirmed, default false (routes absent).
3. **G08/G09 "no `/api/friend/*` route exists on any other branch"** is stale on this branch: `ApiFriendG22Controller` (same `/api/friend` prefix: request, requests, remove, team-invite/*) exists. Out of my groups, but it is the `/remove` and `/request` producer the G09 report says is missing, so `removal/receipt` may no longer always be UNKNOWN (G22 writing `friend_receipt_g08` action `remove`: UNKNOWN, not read).
4. G09 report says `metadata/settle` and `removal/settle` have no iOS caller yet: confirmed (stubs throw `notSent`). G08 report claims `accept/cancel` accept `review_id`: code accepts it only for cancel and always returns 404 `FRIEND_REVIEW_NOT_FOUND` when present; `reject` (G09) does not accept `review_id` at all.
5. Request-body strictness not stated in reports: unknown keys on every G08/G09 POST give 400 (iOS adds `source_*` keys for sourced commands, which would be rejected on accept/cancel/reject).
6. Not verified anywhere (reports say NOT COMPILED too): nothing here was compiled or executed; HTTP status for business errors is inferred (200 envelope) not observed.

---

# Route table: G11 (workshop owned / creator) + G12 (topic cover / attribute-author)

Source: /home/user/chengyin @ cloud/rt-01 (= origin/claude/be-v2-fixes), static read only. iOS: /home/user/ios-w5 (origin/wip/wave5-build).
Controller dir `C` = `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`; service dir `S` = `chengyinhub-system/src/main/java/com/chengyinhub/business/service/support/`.

## Global facts (apply to every route below unless overridden)

- **Auth / guest**: none of these paths are in any `permitAll` list in `chengyinhub-framework/.../SecurityConfig.java` (anyRequest().authenticated(), lines ~127-166). Paths start with `/api/` so `JwtAuthenticationTokenFilter` (lines 52-67) reads the app token (`Authorization` header, set raw by iOS `AuthRequestBuilder.swift:22-36`) via `AppTokenService`. Guests are NOT allowed. Exact body of the Spring Security 401 for an unauthenticated caller is UNKNOWN (entry point not read). Member id comes from `getAppUserId()` only, never from request params.
- **G11 envelope** (`C/ApiWorkshopG11Base.java:47-70`): EVERY response, success or failure, is **HTTP 200** with `Cache-Control: no-store`. Success: `{"code":200,"msg":"操作成功","data":{...}}`. Failure: `{"code":<n>,"msg":"<ERROR_CODE>","errorCode":"<ERROR_CODE>"}` (HTTP stays 200; `code` is the business status). Unauthenticated-in-body: `code 401 / AUTH_REQUIRED`. Unexpected exception: `code 500 / OPERATION_FAILED`. Business errors are `ServiceException(errorCode, httpLikeCode)`. Rate-limit rejection body: UNKNOWN (aspect not read).
- **G12 cover envelope** (`C/ApiTopicCoverG12Controller.java:194-201`): success HTTP 200 `{"code":200,"msg":"操作成功","data":{...}}`; failure uses a REAL HTTP status = ServiceException code (clamped to 400-599, else 500) with body `{"code":<n>,"msg":"<Chinese message>"}` (no `errorCode` field). Note the cover controller does not catch non-ServiceException (e.g. Spring/DB exceptions fall to global handler: UNKNOWN).
- **Idempotency header**: none of the G11/G12-cover routes use a header; requestId travels in the JSON body. Only attribute-author uses headers.
- **Feature flags**: G11 `workshop.g11.owned-read-enabled` (default false) and `workshop.g11.creator-enabled` (default false); both read via `@Value` defaults in code, and NOT set in `chengyinhub-admin/src/main/resources/*.yml` (grep: no hits). G12 cover: no flag in code. Attribute-author: `equipment.dynamic-author.http-enabled` (default absent = off), see routes 15/16.
- **Compile status** of branch: reports say NOT COMPILED (offline BOM). I did not compile either.

## Route table (16 routes)

| # | Group | Method | Full path | Controller:line | Auth | Encoding | Flag (default) | iOS caller |
|---|---|---|---|---|---|---|---|---|
| 1 | G11 | POST | /api/workshop/owned/list | C/ApiWorkshopOwnedG11Controller.java:88 | token | none (empty form body) | owned-read-enabled (off -> 200 NOT_ENABLED) | Core/WorkshopOwnedService.swift:69,81 |
| 2 | G11 | POST | /api/workshop/owned/detail | ...OwnedG11Controller.java:93 | token | form-urlencoded | same | Core/WorkshopOwnedService.swift:73,81 |
| 3 | G11 | POST | /api/workshop/owned/package | ...OwnedG11Controller.java:98 | token | form-urlencoded | same | Core/WorkshopOwnedPackageService.swift:57,63 |
| 4 | G11 | POST | /api/workshop/creator/pending-packages/author | C/ApiWorkshopCreatorPendingG11Controller.java:20 | token | JSON | creator-enabled (off -> code 503) | Core/WorkshopCreatorPendingService.swift:154 (make) |
| 5 | G11 | POST | /api/workshop/creator/pending-packages/list | ...PendingG11Controller.java:25 | token | JSON | same | Core/WorkshopCreatorPendingService.swift:154 |
| 6 | G11 | POST | /api/workshop/creator/pending-packages/detail | ...PendingG11Controller.java:30 | token | JSON | same | Core/WorkshopCreatorPendingService.swift:154 |
| 7 | G11 | POST | /api/workshop/creator/public-theme-use/preview | C/ApiWorkshopPublicThemeUseG11Controller.java:121 | token | JSON | creator-enabled | Core/WorkshopCreatorConsentService.swift:140 |
| 8 | G11 | POST | /api/workshop/creator/public-theme-use/status | ...PublicThemeUseG11Controller.java:126 | token | JSON | same | Core/WorkshopCreatorConsentService.swift:140 |
| 9 | G11 | POST | /api/workshop/creator/public-theme-use/declare | ...PublicThemeUseG11Controller.java:131 | token | JSON | same | Core/WorkshopCreatorConsentService.swift:140 |
| 10 | G12 | GET | /api/topic/cover/selection/current | C/ApiTopicCoverG12Controller.java:159 | token | query | none | Core/OwnedTopicCoverClient.swift:99 |
| 11 | G12 | POST | /api/topic/cover/upload | ...CoverG12Controller.java:164-165 | token | multipart | none | Core/OwnedTopicCoverClient.swift:109 |
| 12 | G12 | POST | /api/topic/cover/selection | ...CoverG12Controller.java:173 | token | JSON | none | Core/OwnedTopicCoverClient.swift:122 |
| 13 | G12 | POST | /api/topic/cover/selection/status | ...CoverG12Controller.java:178 | token | JSON | none | Core/OwnedTopicCoverClient.swift:122 |
| 14 | G12 | GET | /api/topic/cover/{assetId}/content | ...CoverG12Controller.java:183 | token | path+query, binary JPEG out | none | Core/OwnedTopicCoverClient.swift:131 |
| 15 | G12 | POST | /api/topic/attribute-author | C/CanonicalEquipmentDynamicAuthorController.java:222 | token | JSON raw + 4 headers | http-enabled (off) + non-bean dependency | Core/NativeAttributeAuthorService.swift:128-137 (path Core/NativeAttributeAuthorExtendedContract.swift:254) |
| 16 | G12 | GET | /api/topic/attribute-author/request | ...DynamicAuthorController.java:230 | token | query | same | Core/NativeAttributeAuthorService.swift:128 (path Core/NativeAttributeAuthorExtendedContract.swift:187) |

### No-route table (no invention)

| Path | Why no route | iOS caller exists? |
|---|---|---|
| GET /api/topic/attribute-author (definitions/inspect) | No `@GetMapping` on the class root; controller has only POST save + GET /request (`C/CanonicalEquipmentDynamicAuthorController.java:222,230`). Javadoc: "No fallback unjournaled save or DELETE endpoint". | Yes: Core/NativeAttributeAuthorHostTransport.swift:15, RuntimeConfiguration.swift:20 |
| DELETE /api/topic/attribute-author | No mapping | Yes: NativeAttributeAuthorExtendedContract.swift:218 |
| GET /api/topic/attribute-author/references | No mapping | Yes: ExtendedContract.swift:213 |
| POST /api/topic/attribute-author/validate | No mapping | Yes: ExtendedContract.swift:254 |
| /api/workshop/purchased/** (detail, install/{targets,history,status,submit}, installed-text/detail, professional-targets/{list,detail}, professional-operations/{submit,status,cancel}) | `grep -rn "workshop/purchased" --include=*.java /home/user/chengyin` returns nothing; no ApiWorkshopPurchased*/PaidInstall* class on this branch. | Yes: Core/WorkshopPurchasedService.swift:85, WorkshopPaidInstallService.swift:129,171, WorkshopPaidInstalledTextService.swift:93, WorkshopPaidProfessionalService.swift:202-206 |

---

## Per-route detail

Common G11 request note: iOS owned calls send `Content-Type: application/x-www-form-urlencoded; charset=utf-8`, creator calls send `application/json; charset=utf-8`, plus `Cache-Control: no-store`, `Pragma: no-cache`, `Authorization: <token>`. Backend does not require the Cache-Control/Pragma headers.

### 1. POST /api/workshop/owned/list  (G11)
- Controller: `C/ApiWorkshopOwnedG11Controller.java:88` -> `S/WorkshopOwnedG11Service.list` (line 33). Class mapping `/api/workshop/owned` (line 83) + `/list`.
- Auth: token required, no guests. Encoding: `consumes` form-urlencoded or `*/*`; no parameters.
- Params: none.
- Success `data` (LinkedHashMap, service lines 33-45, 83-92): `schema` "workshop-owned-v1"; `scope` "FREE_INDIVIDUAL_ONLY"; `availability` "FREE_CLAIMS_ONLY" | "NOT_ENABLED"; `purchasedLibraryStatus` "NOT_AVAILABLE"; `contentUseStatus` "UNAVAILABLE"; `checkedAt` string (micros UTC, `yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'`); `items` array; `hasMore` bool. Item (lines 96-110): `claimId` string, `acquisition` "FREE", `buyerKind` "INDIVIDUAL", `acquiredAt`, `validUntil` (instant strings), `storedStatus` string (from DB), `status` (UNAVAILABLE if publication EMERGENCY_BLOCKED/UNAVAILABLE; EXPIRED if stored ACTIVE and past validUntil; else storedStatus), `publicationStatus` string. Max 50 items, no cursor.
- Errors: 401 AUTH_REQUIRED; 500 OPERATION_FAILED (IllegalStateException "bad timestamp" etc.). Flag off is NOT an error (200, empty items).
- Idempotency: read-only; none. Headers: none required.
- Flag: `workshop.g11.owned-read-enabled` default false.
- iOS caller: Core/WorkshopOwnedService.swift:69 (`list`) building request at :81 (path "api/workshop/owned/" + "list"). Wired in App/WorkshopOwnedComposition.swift:16.
- Example (SYNTHETIC, derived from code, flag off):
  - Request: `POST /api/workshop/owned/list` (empty body)
  - Response: `{"code":200,"msg":"操作成功","data":{"schema":"workshop-owned-v1","scope":"FREE_INDIVIDUAL_ONLY","availability":"NOT_ENABLED","purchasedLibraryStatus":"NOT_AVAILABLE","contentUseStatus":"UNAVAILABLE","checkedAt":"2026-11-08T00:00:00.000000Z","items":[],"hasMore":false}}`

### 2. POST /api/workshop/owned/detail  (G11)
- Controller: `...OwnedG11Controller.java:93` -> `WorkshopOwnedG11Service.detail` (line 47).
- Params: `claim_id` (form, String, required; must match `[A-Za-z0-9:_-]{1,128}`, `WorkshopG11Support.isId`). `consumes` form-urlencoded only (JSON would 415 from Spring, outside the G11 envelope).
- Success `data`: same metadata keys as list (schema, scope, availability, purchasedLibraryStatus, contentUseStatus, checkedAt) + `item` (object as list item, or `null` when flag off).
- Errors (all inside HTTP 200 body `code`): 400 INVALID_REQUEST (bad claim_id); 404 CLAIM_NOT_FOUND; 401 AUTH_REQUIRED; 500 OPERATION_FAILED. Missing `claim_id` param: Spring MissingServletRequestParameter, outside envelope (HTTP 400, body UNKNOWN).
- Idempotency: read-only. Flag: owned-read-enabled (off -> `item:null`, availability NOT_ENABLED; note the id validity check still runs first).
- iOS caller: Core/WorkshopOwnedService.swift:73 (body `claim_id=<id>`), request built :81.
- Example (SYNTHETIC): request body `claim_id=claim-001`; response `{"code":200,"msg":"操作成功","data":{"schema":"workshop-owned-v1","scope":"FREE_INDIVIDUAL_ONLY","availability":"FREE_CLAIMS_ONLY","purchasedLibraryStatus":"NOT_AVAILABLE","contentUseStatus":"UNAVAILABLE","checkedAt":"2026-11-08T00:00:00.000000Z","item":{"claimId":"claim-001","acquisition":"FREE","buyerKind":"INDIVIDUAL","acquiredAt":"2026-11-01T00:00:00.000000Z","validUntil":"2027-11-01T00:00:00.000000Z","storedStatus":"ACTIVE","status":"ACTIVE","publicationStatus":"PUBLISHED"}}}`

### 3. POST /api/workshop/owned/package  (G11)
- Controller: `...OwnedG11Controller.java:98` -> `WorkshopOwnedG11Service.packageInfo` (line 57). Params: `claim_id` as route 2.
- Success `data` (lines 57-77): `schema` "workshop-package-v1"; `scope` "FREE_INDIVIDUAL_ONLY"; `claimId`; `checkedAt`; `purchasedLibraryStatus` "NOT_AVAILABLE"; `contentUseStatus` "UNAVAILABLE"; `manifestStatus` "NOT_AVAILABLE"; `editorStatus` "POST_INSTALL_POLICY_UNAVAILABLE"; `availability` ("NOT_ENABLED" | "UNAVAILABLE" | "PACKAGE_METADATA_ONLY"); `packageInfo` (null, or map with exactly keys versionLabel, validUntil, schemaVersion, contentHash, termsVersion, termsHash, commercialUse, adaptation, translation, updates, redistribution, allowedRegions, themeLimit, merchantLimit, runLimit, requiredBindingCount; `redistribution` forced "PROHIBITED", `updates` forced "EXACT_PURCHASED_VERSION"; value types are whatever stored JSON holds -> element types UNKNOWN). packageInfo is null when stored JSON is missing/has a different key set/non-hex contentHash or termsHash, or publication is blocked.
- Errors: 400 INVALID_REQUEST; 404 CLAIM_NOT_FOUND (only when flag on); 401; 500.
- Idempotency: read-only. Flag: owned-read-enabled.
- iOS caller: Core/WorkshopOwnedPackageService.swift:57 (body) / :63 (path "api/workshop/owned/package").
- Example (SYNTHETIC, flag off): `{"code":200,"msg":"操作成功","data":{"schema":"workshop-package-v1","scope":"FREE_INDIVIDUAL_ONLY","claimId":"claim-001","checkedAt":"2026-11-08T00:00:00.000000Z","purchasedLibraryStatus":"NOT_AVAILABLE","contentUseStatus":"UNAVAILABLE","manifestStatus":"NOT_AVAILABLE","editorStatus":"POST_INSTALL_POLICY_UNAVAILABLE","packageInfo":null,"availability":"NOT_ENABLED"}}`

### 4. POST /api/workshop/creator/pending-packages/author  (G11)
- Controller: `C/ApiWorkshopCreatorPendingG11Controller.java:20-21` (class `/api/workshop/creator/pending-packages` line 14) -> `S/WorkshopCreatorG11Service.author` (line 199). `@RateLimiter(time=60,count=20,limitType=MEMBER)`. `@Transactional`.
- Encoding: `consumes application/json`, body bound as raw String, parsed by `parseExactObject` (duplicate keys rejected, trailing tokens rejected, exact key set, <=131072 bytes). Unknown/missing key => 400 INVALID_REQUEST.
- Params (all required; service lines 28-30, 201-215): `requestId` string lowercase UUID; `sourceTemplateId` integer (>0 via source lookup); `expectedTemplateHash` and `expectedPackageContentHash` 64-hex lowercase; `termsDocument` string (non-blank, <=65536 bytes, no control chars except \t\n\r); `commercialUse` "ALLOWED"|"PROHIBITED"; `adaptation` "BIND_RESOURCES_ONLY"|"LOCAL_ADAPTATION"; `translation` "ALLOWED"|"PROHIBITED"; `allowedRegions` comma-string (1-32 unique `[A-Z0-9_-]{1,32}`, <=2048 B); `buyerKinds` comma-string (1-3 unique of INDIVIDUAL,ORGANIZATION,MERCHANT); `themeLimit`,`merchantLimit`,`runLimit` integers >= -1 (-1 = unlimited); `priceMinor` integer > 0; `currency` `[A-Z]{3}`; `expiresAt` RFC3339 instant (<=6 fractional digits; must be future and <= now+30 days else 400 INVALID_EXPIRY); `useDuration` must equal "PERPETUAL_PURCHASED_VERSION"; `updates` "EXACT_PURCHASED_VERSION"; `redistribution` "PROHIBITED"; `copyrightOwnership` "RETAINED_BY_CREATOR"; `acquisition` "PAID".
- Success `data` = `metadata(row)` (lines 243-266): `schema` "w18-creator-pending-package-v1"; `targetId` (deterministic UUID); `revision` (64-hex); `sourceTemplateId` number; `templateHash`; `packageContentHash`; `moduleId` "member-template:<id>"; `versionId` "creator-package:<targetId>:<revision>"; `offerVersion` "creator-offer:<targetId>:<revision>"; `termsVersion` "creator-terms:<targetId>"; `termsDocumentHash`; `expiresAt`; `createdAt`; `state` "UNREVIEWED_AUTHOR_PROPOSAL"; `packageReviewed` false; `listed` false; `licenseIssued` false; `copyrightOwnership` "RETAINED_BY_CREATOR".
- Error codes (body `errorCode`/`msg`, `code`): 400 INVALID_REQUEST, 400 INVALID_EXPIRY; 404 TEMPLATE_NOT_FOUND; 409 TEMPLATE_NOT_ELIGIBLE (blank title, description > 30 chars, package JSON > 262144 B), 409 SOURCE_CHANGED (hash mismatch), 409 REQUEST_CONFLICT (same requestId, different body); 503 WORKSHOP_CREATOR_NOT_ENABLED; 401; 500.
- Idempotency: `requestId` in body, PK (member, requestId) in `workshop_creator_pending_g11`; same body replays the stored result (line 218-219), changed body -> 409 REQUEST_CONFLICT. No header.
- Flag: `workshop.g11.creator-enabled` default false -> code 503 WORKSHOP_CREATOR_NOT_ENABLED (HTTP 200).
- iOS caller: Core/WorkshopCreatorPendingService.swift:154 (`make(.author, body:)`), validated in App/AppCompositionRoot.swift:1880.
- Example (SYNTHETIC): request `{"requestId":"11111111-1111-4111-8111-111111111111","sourceTemplateId":42,"expectedTemplateHash":"<64 hex>","expectedPackageContentHash":"<64 hex>","termsDocument":"terms text","commercialUse":"ALLOWED","adaptation":"BIND_RESOURCES_ONLY","translation":"PROHIBITED","allowedRegions":"CN,US","buyerKinds":"INDIVIDUAL","themeLimit":3,"merchantLimit":1,"runLimit":-1,"priceMinor":990,"currency":"CNY","expiresAt":"2026-12-01T00:00:00Z","useDuration":"PERPETUAL_PURCHASED_VERSION","updates":"EXACT_PURCHASED_VERSION","redistribution":"PROHIBITED","copyrightOwnership":"RETAINED_BY_CREATOR","acquisition":"PAID"}`; response `{"code":200,"msg":"操作成功","data":{"schema":"w18-creator-pending-package-v1","targetId":"<uuid>","revision":"<64 hex>","sourceTemplateId":42,"templateHash":"<64 hex>","packageContentHash":"<64 hex>","moduleId":"member-template:42","versionId":"creator-package:<uuid>:<rev>","offerVersion":"creator-offer:<uuid>:<rev>","termsVersion":"creator-terms:<uuid>","termsDocumentHash":"<64 hex>","expiresAt":"2026-12-01T00:00:00.000000Z","createdAt":"2026-11-08T00:00:00.000000Z","state":"UNREVIEWED_AUTHOR_PROPOSAL","packageReviewed":false,"listed":false,"licenseIssued":false,"copyrightOwnership":"RETAINED_BY_CREATOR"}}`

### 5. POST /api/workshop/creator/pending-packages/list  (G11)
- Controller: `...PendingG11Controller.java:25` -> `WorkshopCreatorG11Service.list` (line 268). No rate limiter. JSON.
- Params: `sourceTemplateId` integer required (>0); `afterTargetId` string lowercase UUID, optional (null allowed). Other keys -> 400.
- Success `data` (lines 278-284): `schema` "w18-creator-pending-package-list-v1"; `sourceTemplateId`; `items` array of the route-4 metadata objects (max 20, only non-expired per mapper query - mapper XML not read); `hasMore` bool; `nextCursor` (targetId of last item) or null.
- Errors: 400 INVALID_REQUEST; 503 WORKSHOP_CREATOR_NOT_ENABLED; 401; 500.
- Idempotency: read-only. Flag: creator-enabled.
- iOS caller: Core/WorkshopCreatorPendingService.swift:154 (body built by `listBody`, :176-179).
- Example (SYNTHETIC): request `{"sourceTemplateId":42,"afterTargetId":null}` -> `{"code":200,"msg":"操作成功","data":{"schema":"w18-creator-pending-package-list-v1","sourceTemplateId":42,"items":[],"hasMore":false,"nextCursor":null}}`

### 6. POST /api/workshop/creator/pending-packages/detail  (G11)
- Controller: `...PendingG11Controller.java:30` -> `WorkshopCreatorG11Service.detail` (line 287). JSON.
- Params (all required): `sourceTemplateId` integer >0; `targetId` lowercase UUID; `expectedRevision` 64-hex.
- Success `data`: route-4 metadata fields plus `termsDocument` (string), `packageSourceJson` (string), `omittedPlanningMetadata` (string array), `proposedOffer` (object: `offerId` "creator-offer:<target>", `offerVersion`, `moduleId`, `seller{kind:"INDIVIDUAL",entityId:<memberId>}`, `buyerKinds` string[], `acquisition` "PAID", `priceMinor` number, `currency`, `terms{useDuration, termsVersion, termsHash, termsDocumentHash, termsDocumentReference "creator-pending:<target>", commercialUse, adaptation, translation, updates, redistribution, allowedRegions string[], themeLimit/merchantLimit/runLimit {unlimited:bool, maximum:number}}`), `disclosureVersion`, `disclosureHash`, `disclosureText`.
- Errors: 400 INVALID_REQUEST; 404 PENDING_PACKAGE_NOT_FOUND; 409 REVISION_MISMATCH; 409 PENDING_PACKAGE_EXPIRED; 503 not enabled; 401; 500.
- Idempotency: read-only. Flag: creator-enabled.
- iOS caller: Core/WorkshopCreatorPendingService.swift:154 (`detailBody` :180-183).
- Example (SYNTHETIC): request `{"sourceTemplateId":42,"targetId":"<uuid>","expectedRevision":"<64 hex>"}`; response shape = route-4 data + the extra fields listed above.

### 7. POST /api/workshop/creator/public-theme-use/preview  (G11)
- Controller: `C/ApiWorkshopPublicThemeUseG11Controller.java:121` (class `/api/workshop/creator/public-theme-use` line 116) -> `WorkshopCreatorG11Service.preview` (line 84). JSON; no rate limiter.
- Params: `sourceTemplateId` integer required (>0).
- Success `data` (lines 91-101): `schema` "w18-creator-public-use-preview-v1"; `sourceTemplateId`; `templateHash`; `packageContentHash`; `packageSourceJson` string; `omittedPlanningMetadata` string[]; `disclosureVersion` "w18-creator-public-theme-use-disclosure-v1"; `disclosureHash` (sha256 of fixed Chinese disclosure text); `disclosureText`; `state` "EXPLICIT_CREATOR_CONFIRMATION_REQUIRED"; `packageReviewed` false.
- Errors: 400 INVALID_REQUEST; 404 TEMPLATE_NOT_FOUND; 409 TEMPLATE_NOT_ELIGIBLE; 503 not enabled; 401; 500.
- Idempotency: read-only. Flag: creator-enabled.
- iOS caller: Core/WorkshopCreatorConsentService.swift:140 (`previewBody` :163).
- Example (SYNTHETIC): request `{"sourceTemplateId":42}`; response `data` keys as above.

### 8. POST /api/workshop/creator/public-theme-use/status  (G11)
- Controller: `...PublicThemeUseG11Controller.java:126` -> `WorkshopCreatorG11Service.declarationStatus` (line 105). JSON.
- Params: `requestId` lowercase UUID, required.
- Success `data`: if no declaration: `{schema:"w18-creator-public-use-declaration-status-v1", state:"NOT_FOUND", requestId}`; else the receipt (see route 9).
- Errors: 400 INVALID_REQUEST; 503 not enabled; 401; 500.
- Idempotency: this is the recovery read for route 9 by requestId.
- Flag: creator-enabled. iOS caller: Core/WorkshopCreatorConsentService.swift:140 (`statusBody` :164).
- Example (SYNTHETIC): request `{"requestId":"22222222-2222-4222-8222-222222222222"}` -> `{"code":200,"msg":"操作成功","data":{"schema":"w18-creator-public-use-declaration-status-v1","state":"NOT_FOUND","requestId":"22222222-2222-4222-8222-222222222222"}}`

### 9. POST /api/workshop/creator/public-theme-use/declare  (G11)
- Controller: `...PublicThemeUseG11Controller.java:131-132`, `@RateLimiter(60s,20,MEMBER)` -> `WorkshopCreatorG11Service.declare` (line 122, `@Transactional`). JSON, exact key set.
- Params (all required, lines 31-33, 125-132): `requestId` lowercase UUID; `sourceTemplateId` integer; `expectedTemplateHash`, `expectedPackageContentHash` 64-hex; `moduleId` ("member-template:<id>"), `versionId` ("creator-package:<uuid>:<64hex>"), `offerVersion` ("creator-offer:<uuid>:<64hex>"), `termsVersion` ("creator-terms:<uuid>") all matching `[A-Za-z0-9:_-]{1,128}`; `termsDocumentHash` 64-hex; `displayedScopeHash` must equal sha256(disclosure text); `acknowledgeExactTextPackage`, `allowUseInBuyersOwnPublishedThemes`, `prohibitPackageResaleAndRedistribution` booleans, all must be true.
- Success `data` (receipt, lines 169-194): `schema` "w18-creator-public-use-declaration-receipt-v1"; `state` "CREATOR_DECLARED_PENDING_PACKAGE_REVIEW"; `consentReference{scope:"BUYER_OWN_PUBLISHED_THEMES", consentId, creatorMemberId, moduleId, versionId, contentHash, termsDocumentHash, recordHash}`; `sourceTemplateId`; `templateHash`; `offerVersion`; `termsVersion`; `declaredAt`; `disclosureVersion`; `disclosureHash`; `packageReviewed` false; `listed` false; `licenseIssued` false.
- Errors: 400 INVALID_REQUEST; 404 TEMPLATE_NOT_FOUND / PENDING_PACKAGE_NOT_FOUND; 409 SOURCE_CHANGED, TEMPLATE_NOT_ELIGIBLE, PENDING_PACKAGE_EXPIRED, PENDING_PACKAGE_MISMATCH, CONSENT_ALREADY_DECLARED (same versionId already declared by another request), REQUEST_CONFLICT (same requestId, different body); 503 not enabled; 401; 500.
- Idempotency: `requestId` in body; replay of identical body returns same receipt (lines 134-135), `requestHash`=sha256 of canonical body+memberId. No header.
- Flag: creator-enabled (default off -> code 503).
- iOS caller: Core/WorkshopCreatorConsentService.swift:140; gate at :65.
- Example (SYNTHETIC): request keys as above; response `{"code":200,"msg":"操作成功","data":{"schema":"w18-creator-public-use-declaration-receipt-v1","state":"CREATOR_DECLARED_PENDING_PACKAGE_REVIEW","consentReference":{"scope":"BUYER_OWN_PUBLISHED_THEMES","consentId":"<uuid>","creatorMemberId":1001,"moduleId":"member-template:42","versionId":"creator-package:<uuid>:<hex>","contentHash":"<hex>","termsDocumentHash":"<hex>","recordHash":"<hex>"},"sourceTemplateId":42,"templateHash":"<hex>","offerVersion":"creator-offer:<uuid>:<hex>","termsVersion":"creator-terms:<uuid>","declaredAt":"2026-11-08T00:00:00.000000Z","disclosureVersion":"w18-creator-public-theme-use-disclosure-v1","disclosureHash":"<hex>","packageReviewed":false,"listed":false,"licenseIssued":false}}`

### 10. GET /api/topic/cover/selection/current  (G12)
- Controller: `C/ApiTopicCoverG12Controller.java:159-162` (class `/api/topic/cover` line 154) -> `S/TopicCoverG12Service.current` (line 62).
- Auth: token required. Encoding: query. Params: `topicId` Long, required (missing -> Spring 400, body UNKNOWN; non-positive/NULL is passed as 0 -> 404 "主题不存在").
- Success `data` (lines 71-85): `topicId`; `topicConfigVersion` (cms_topic.config_version, null->0); `selectionVersion` (0 if none); `contentSlotId` (= topicId); `selectedAtConfigVersion` (number|null); `selectionState` "NONE"|"CURRENT"|"STALE"; `assetAvailability` "NONE"|"AVAILABLE"|"UNAVAILABLE"; `display` null or `{assetReference{kind:"OWNED_TOPIC_COVER_V1", id, assetId, sourceVersion, contentHash, owner, ownerMemberId, policyVersion:"OWNED_TOPIC_COVER_V1"}, displayReference{kind:"OWNED_TOPIC_COVER_AUTHENTICATED_CONTENT_V1", audience:"AUTHOR_ONLY", path:"/api/topic/cover/<assetId>/content?sourceVersion=<v>&contentHash=<h>", contentHash}}`.
- Errors (real HTTP status): 404 "主题不存在" (unknown or del_flag != '0'); 403 "仅作者可操作封面" (not cms_topic.member_id).
- Idempotency: read-only. Flag: none.
- iOS caller: Core/OwnedTopicCoverClient.swift:99 (decode :64-72; requires envelope code 200).
- Example (SYNTHETIC): `GET /api/topic/cover/selection/current?topicId=7` -> `{"code":200,"msg":"操作成功","data":{"topicId":7,"topicConfigVersion":3,"selectionVersion":0,"contentSlotId":7,"selectedAtConfigVersion":null,"selectionState":"NONE","assetAvailability":"NONE","display":null}}`

### 11. POST /api/topic/cover/upload  (G12)
- Controller: `...CoverG12Controller.java:164-171` -> `TopicCoverG12Service.upload` (line 36). `@RateLimiter(60s, 10, MEMBER)`.
- Encoding: multipart/form-data, part `file` (MultipartFile, required). Spring multipart limits 10MB/file, 20MB/request (`application.yml:77-79`); service cap 10 MiB.
- Validation: >=4 bytes, <=10 MiB, JPEG magic FF D8 FF, decodable, <=16,000,000 pixels; re-encoded to JPEG server-side; sha256 computed server-side; stored in DB (`topic_cover_asset_g12`). Max 30 assets per member after pruning unselected assets older than 1 day.
- Success `data` = assetRef: `kind` "OWNED_TOPIC_COVER_V1", `id`, `assetId` (UUID), `sourceVersion` (UUID), `contentHash` (hex sha256 of re-encoded bytes), `owner`, `ownerMemberId` (number), `policyVersion` "OWNED_TOPIC_COVER_V1".
- Errors (real HTTP status): 400 "封面图片大小无效" / "封面必须是 JPEG" / "封面图片无法识别" / "封面图片处理失败" / "封面读取失败"; 429 "封面上传过多，请稍后再试"; rate-limit rejection UNKNOWN.
- Idempotency: none (each call creates a new asset with random ids). No requestId. Flag: none.
- iOS caller: Core/OwnedTopicCoverClient.swift:109 (field name "file", filename cover.jpg, `Authorization` header :113). Upload errors map non-2xx to outcomeUnknown (:62-63).
- Example (SYNTHETIC): multipart `file=<jpeg bytes>` -> `{"code":200,"msg":"操作成功","data":{"kind":"OWNED_TOPIC_COVER_V1","id":"<uuid>","assetId":"<uuid>","sourceVersion":"<uuid>","contentHash":"<64 hex>","owner":1001,"ownerMemberId":1001,"policyVersion":"OWNED_TOPIC_COVER_V1"}}`

### 12. POST /api/topic/cover/selection  (G12)
- Controller: `...CoverG12Controller.java:173-176` -> `TopicCoverG12Service.select` (line 99, `@Transactional`).
- Encoding: JSON body bound into `TopicCoverG12Service.Command` (public fields; unknown-property policy UNKNOWN - global Jackson config not read). No `consumes` restriction.
- Params (all required; lines 90-91, 170-174): `topicId` long >0; `expectedConfigVersion` long >=0; `expectedSelectionVersion` long >=0; `expectedContentSlotId` long >0 (must equal topicId); `requestId` UUID string (any case accepted); `assetId` lowercase UUID; `sourceVersion` lowercase UUID; `contentHash` 64-hex lowercase. Omitted numerics default 0, which fails validation for topicId/slot.
- Success `data` (receipt lines 158-163): `topicId`; `topicConfigVersion` (= expected+1); `selectionVersion` (= expected+1); `contentSlotId`; `cover` (assetRef as route 11, using the caller's asset id/version/hash).
- Effects: bumps `cms_topic.config_version` by 1 (UPDATE via JdbcTemplate), writes selection + request rows.
- Errors (real HTTP status, body `{code,msg}`): 400 "封面选择参数无效"; 404 "主题不存在"; 403 "仅作者可操作封面" (topic not owned) or "封面资源不属于当前作者" (asset missing/foreign/version-hash mismatch); 409 "封面槽位已变化", "主题配置版本已变化", "封面选择版本已变化", "请求编号冲突", "请求编号已用于不同内容".
- Idempotency: `requestId` in body; table `topic_cover_request_g12` keyed (request_id, member). Identical payload replays the stored receipt; same requestId with different payload -> 409. No header.
- Flag: none. Auth: token; member from token.
- iOS caller: Core/OwnedTopicCoverClient.swift:122 (`OperationAdapterHTTP.json`, body <=2048 B, sorted keys). 409 -> outcomeUnknown (:61).
- Example (SYNTHETIC): request `{"topicId":7,"expectedConfigVersion":3,"expectedSelectionVersion":0,"expectedContentSlotId":7,"requestId":"33333333-3333-4333-8333-333333333333","assetId":"<uuid>","sourceVersion":"<uuid>","contentHash":"<64 hex>"}`; response `{"code":200,"msg":"操作成功","data":{"topicId":7,"topicConfigVersion":4,"selectionVersion":1,"contentSlotId":7,"cover":{"kind":"OWNED_TOPIC_COVER_V1","id":"<uuid>","assetId":"<uuid>","sourceVersion":"<uuid>","contentHash":"<hex>","owner":1001,"ownerMemberId":1001,"policyVersion":"OWNED_TOPIC_COVER_V1"}}}`

### 13. POST /api/topic/cover/selection/status  (G12)
- Controller: `...CoverG12Controller.java:178-181` -> `TopicCoverG12Service.status` (line 135). Same Command body as route 12 (same validation).
- Success `data`: identical receipt shape to route 12, built from the stored request row (config/selection version from storage).
- Errors: 400 "封面选择参数无效"; 404 "未找到该封面选择请求" (no committed request for (requestId, member)); 409 "请求编号已用于不同内容".
- Idempotency: read-only recovery for route 12. Flag: none.
- iOS caller: Core/OwnedTopicCoverClient.swift:122 (path chosen at :122 when operation == .status).
- Example (SYNTHETIC): same request body as route 12 -> same receipt, or HTTP 404 `{"code":404,"msg":"未找到该封面选择请求"}`.

### 14. GET /api/topic/cover/{assetId}/content  (G12)
- Controller: `...CoverG12Controller.java:183-192` -> `TopicCoverG12Service.content` (line 143).
- Params: path `assetId` (lowercase UUID); query `sourceVersion` (lowercase UUID, required), `contentHash` (64-hex, required). Missing query -> Spring 400.
- Success: HTTP 200, `Content-Type: image/jpeg`, `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, body = raw JPEG bytes (NOT an AjaxResult).
- Errors: empty-body HTTP 400 (bad params), 404 (asset missing), 403 (asset owned by another member), 409 (sourceVersion/contentHash changed). Only ServiceException is caught.
- Idempotency: read-only. Flag: none.
- iOS caller: Core/OwnedTopicCoverClient.swift:131 (path from `OwnedTopicCoverContracts.swift:22`; client verifies sha256 of bytes == contentHash :136).
- Example (SYNTHETIC): `GET /api/topic/cover/<uuid>/content?sourceVersion=<uuid>&contentHash=<64 hex>` -> 200 image/jpeg bytes.

### 15. POST /api/topic/attribute-author  (G12, EXISTS but effectively not live)
- Controller: `C/CanonicalEquipmentDynamicAuthorController.java:222-228`; class `@RequestMapping("/api/topic/attribute-author")` line 217, `@ConditionalOnProperty(equipment.dynamic-author.http-enabled=true, matchIfMissing=false)` line 218. Delegates to `S/CanonicalEquipmentDynamicAuthorRequests.save` (line 40).
- Gate / registration status: controller is only created when `equipment.dynamic-author.http-enabled=true`. Its constructor needs a `CanonicalEquipmentDynamicAuthorRequests` bean, but that class is a non-bean ("Nonbean original POST journal owner", `Requests.java:15`; no `@Component`/`@Bean` anywhere in main sources - grep of all `chengyinhub-*/src/main` finds only the controller referencing it). So setting the flag true would fail context startup (no bean) unless something external registers it. Even if constructed, the 6-arg constructor sets read/write enabled = false (lines 23-26), and `Access.requireEnabled` throws 503 "原属性作者入口未启用" when its own flag is off. Property key for the flag is not in any checked-in yml.
- Auth: token (via `Access.principal()`: 401 "请先登录" if missing); owner/merchant scope checks in Access.
- Encoding: raw JSON body (String) + headers. Body keys allowed: `topicId` long, `expectedConfigVersion` long >=0, `scope` string (optional), `keys` array (1-32). Unknown field -> IllegalArgument -> 400.
- Required headers: `X-Attribute-Request-Id` (lowercase UUID), `X-Attribute-Request-Protocol` ("original-attribute-author-request-v1"), `X-Attribute-Request-SHA256` (sha256 of "POST\napi/topic/attribute-author\n"+raw body), `X-Attribute-Session-Epoch` (Long). Missing header -> Spring 400.
- Success: HTTP 200 AjaxResult with `data` (= compiled `{definitions[], warnings[], keys[]}`; each definition has stateKey, keyType, scope(run|party|deployment), label, display(bar|number|icon|hidden), persistScope(run|topic), initialValue, minValue, maxValue, sortOrder, visible, rules[]) plus top-level extra fields `topicId`, `configVersion` (= expected+1) and `requestReceipt{protocolVersion, requestId, payloadSHA256, method:"POST", topicId, expectedConfigVersion, state:"COMMITTED"}`.
- Errors: ServiceException passes its code as real HTTP status (401 请先登录, 403 授权/归属/商家权限, 404 主题不存在, 400 content-review denial, 409 compiled-definition mismatch, 503 entry disabled); IllegalArgumentException -> 400 "原属性请求参数不合规"; any other RuntimeException (incl. IllegalStateException from `require`) -> 503 "原属性请求结果未确认，请保留原请求信息".
- Idempotency: `X-Attribute-Request-Id` + payload hash + session epoch; journal table `project_edit_request` (actor_id, request_id) with RUNNING/COMMITTED state; replay returns the committed result; existing RUNNING returns UNKNOWN receipt (never re-runs the writer).
- Flag: `equipment.dynamic-author.http-enabled` default off (plus nested non-bean flags; see above).
- iOS caller: request builder Core/NativeAttributeAuthorService.swift:128-137 (sets the 4 headers; path `Core/NativeAttributeAuthorRuntimeConfiguration.swift:20`, body built `NativeAttributeAuthorExtendedContract.swift:254`).
- Example (SYNTHETIC; shape from code, definition fields abbreviated): request headers `X-Attribute-Request-Id: 44444444-4444-4444-8444-444444444444`, `X-Attribute-Request-Protocol: original-attribute-author-request-v1`, `X-Attribute-Request-SHA256: <64 hex>`, `X-Attribute-Session-Epoch: 5`; body `{"topicId":7,"expectedConfigVersion":3,"scope":"","keys":[{"stateKey":"hp.main", ...}]}`; response `{"code":200,"msg":"操作成功","data":{"definitions":[...],"warnings":[],"keys":[...]},"topicId":7,"configVersion":4,"requestReceipt":{"protocolVersion":"original-attribute-author-request-v1","requestId":"4444...","payloadSHA256":"<hex>","method":"POST","topicId":7,"expectedConfigVersion":3,"state":"COMMITTED"}}`. Inner `keys` element schema: UNKNOWN (defined in Writer/Host, not read).

### 16. GET /api/topic/attribute-author/request  (G12, EXISTS but effectively not live)
- Controller: `...DynamicAuthorController.java:230-237` -> `Requests.read` (line 75). Same class gate/registration caveats as route 15.
- Query params (all required except `scope`): `topicId` Long; `expectedConfigVersion` Long; `scope` String (optional); `requestId` lowercase UUID; `protocolVersion` "original-attribute-author-request-v1"; `sessionEpoch` Long; `method` must be exactly "POST" (else IllegalArgument -> 400); `payloadSHA256` 64-hex.
- Success: HTTP 200 AjaxResult. If original committed: `data` = saved definitions payload, `configVersion` = expected+1, `requestReceipt.state` "COMMITTED". If no journal row: `data` = `{}`, `configVersion` = expected, `requestReceipt.state` "NOT_FOUND"; if row exists but not COMMITTED: state "UNKNOWN". Extra top-level `topicId`, `configVersion`, `requestReceipt` as route 15.
- Errors: same mapping as route 15; additionally read disabled (`readEnabled` false by default) -> IllegalStateException -> 503 "原属性请求结果未确认，请保留原请求信息".
- Idempotency: read-only recovery. Headers: none (Authorization only).
- Flag: same as route 15.
- iOS caller: Core/NativeAttributeAuthorService.swift:128 builds the request; path/query constructed at Core/NativeAttributeAuthorExtendedContract.swift:187.
- Example (SYNTHETIC): `GET /api/topic/attribute-author/request?topicId=7&expectedConfigVersion=3&scope=&requestId=4444...&protocolVersion=original-attribute-author-request-v1&sessionEpoch=5&method=POST&payloadSHA256=<hex>` -> `{"code":200,"msg":"操作成功","data":{},"topicId":7,"configVersion":3,"requestReceipt":{"protocolVersion":"original-attribute-author-request-v1","requestId":"4444...","payloadSHA256":"<hex>","method":"POST","topicId":7,"expectedConfigVersion":3,"state":"NOT_FOUND"}}`

---

## Discrepancies vs reports (be-g11-report.md / be-g12-report.md)

1. **G11 purchased**: report says EXISTS on side branch; confirmed ABSENT on this branch (no `workshop/purchased` string in any .java). iOS calls them (see no-route table).
2. **G11 report error semantics**: report lists HTTP-style codes (404/409/503) "503 for creator disabled"; code returns HTTP 200 for all G11 outcomes with the status only in body `code` (`ApiWorkshopG11Base.reply` always `ResponseEntity.ok()`).
3. **G11 report iOS file** "WorkshopOwnedReadRoute.swift" does not exist in ios-w5; real callers are WorkshopOwnedService.swift and WorkshopOwnedPackageService.swift.
4. **G12 attribute-author**: report says EXISTS/off by default; additionally the controller cannot start when the flag is turned on because its `Requests` dependency has no bean, and Requests' read/write flags default false. Treat as not live. Report also says "4 BLOCKED" - confirmed 4 missing (GET, DELETE, references, validate).
5. G12 cover: report says errors are 400/403/404/409 - code also returns 429 on upload when >=30 assets; and cover errors have no `errorCode` field (unlike G11).
6. Not verified (static only): rate-limit rejection body, global Jackson unknown-field policy, Spring Security 401 body, mapper XML (`WorkshopG11Mapper`) behaviors.
