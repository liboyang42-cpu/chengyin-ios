# Route table rt-03 (groups G26-G36)

Static contract read from code on `origin/claude/be-v2-fixes` (not run against a live server). iOS callers searched on `origin/wip/wave5-build` of chengyin-app. UNKNOWN = not determinable from code. All JSON examples are SYNTHETIC, derived from code, not captured traffic.

<!-- part-A: G26-G29. Static read of origin/claude/be-v2-fixes; iOS = origin/wip/wave5-build. All examples are SYNTHETIC. -->

### Conventions for G26-G29 (apply to every row unless a row says otherwise)
- **Envelope**: controllers return `AjaxResult` = flat JSON map `{code:int, msg:string, data?:...}`, HTTP status 200 even for business errors (`AjaxResult.java:42,55`; global `ServiceException` handler returns the same shape, `GlobalExceptionHandler.java:130-142`). Success = `{code:200,msg:"操作成功",data}` (`AjaxResult.java:78`). For non-200 codes `msg` goes through `UserSafeMessage.of` (`AjaxResult.java:206`), so the literal Chinese text may be rewritten: UNKNOWN exact wire text. Only the audio route (G29) returns a real non-2xx HTTP status.
- **Auth**: `SecurityConfig.java:166` `anyRequest().authenticated()`; permitAll paths are an explicit list (`SecurityConfig.java:115-163`) plus `@Anonymous` methods; none of the paths below is on that list and none of these controllers uses `@Anonymous` => **token required, guests refused** (HTTP/auth failure shape produced by the filter chain: UNKNOWN, not read). Header: iOS sends raw token in `Authorization` (e.g. `NativePlatformService.swift:68`, `CityOrientationTaskOriginalSource.swift:172`); no `Bearer ` prefix on those calls.
- **Rate limit**: only where `@RateLimiter` is noted. No other custom headers are required by the controllers (no `Idempotency-Key` header anywhere); idempotency is body/query `requestId` where noted. `RequestIdFilter` (framework/web/trace) exists but its header contract was not read: UNKNOWN.
- `getAppUserId()` = member id from token; `BaseController` is the base of all controllers here.
- Line refs: `API/` = `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/`.

## G26

### GET /api/play/advanced/time-window
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiPlayG26Controller.java:30-45` (class map `:21`) |
| auth | token required, no guest |
| encoding | query string (no body) |
| params | `activityId` Long (optional per signature, null allowed; service treats null as 0 in output), `topicId` Long (required in practice: projection needs it; exact null handling inside `requireInput` UNKNOWN), `nodeId` Long (same) |
| success `data` | `enabled:true, notificationProvider:"LOCAL_ONLY", timeZone:string(zone id), serverNow:long(epoch ms), openNow:bool, nextOpenAt:long, nextCloseAt:long, windowVersion:string, activityId:long(0 if null), topicId:long, nodeId:long` (`TimeWindowCalcG26.java:37-47`) |
| errors | 400 `msg` from IllegalArgumentException/IllegalStateException (e.g. "该玩法未开启时段限定", "时段限定配置无效，请商家修正开放时段后再试"); 409 + `data:{reasonCode:"TIME_WINDOW_OPENING_REQUIRED"}` when message contains "开局流程" (`:36-41`); other access errors from `requireInput`: UNKNOWN |
| idempotency / headers | read-only; `@RateLimiter 120/10s per member` |
| iOS caller | `Core/NativePlatformService.swift:62-70` (path const `:31`, GET, query activityId/nodeId/topicId) |

SYNTHETIC request: `GET /api/play/advanced/time-window?activityId=0&topicId=12&nodeId=345`
SYNTHETIC response:
```json
{"code":200,"msg":"操作成功","data":{"enabled":true,"notificationProvider":"LOCAL_ONLY","timeZone":"Asia/Shanghai","serverNow":1793000000000,"openNow":true,"nextOpenAt":1793059200000,"nextCloseAt":1793002800000,"windowVersion":"<hash>","activityId":0,"topicId":12,"nodeId":345}}
```

### GET /api/play/route-action
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiPlayG26Controller.java:47-53` |
| auth | token required |
| encoding | query |
| params | `sessionId` Long, `memberId` Long (must equal token member else 404), `actionId` String (1-128 chars after trim); all effectively required (null => 404) |
| success `data` | `sessionId, memberId, actionId, responseJson` (`RouteActionReadG26Service.java:24-28`; `responseJson` type = whatever `TopicRouteAction.getResponseJson()` is, String presumed: UNKNOWN) |
| errors | 404 `路线动作不存在` (absent, bad args, memberId mismatch; no distinction) |
| idempotency / headers | read-only, never inserts; `@RateLimiter 120/10s` |
| iOS caller | `App/PlayRouteMapView.swift:271-281` (URL build `:272-`, query sessionId/memberId/actionId) |

SYNTHETIC request: `GET /api/play/route-action?sessionId=9001&memberId=77&actionId=a-1`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"sessionId":9001,"memberId":77,"actionId":"a-1","responseJson":"{\"ok\":true}"}}`

### POST /api/play/city-orientation/answer
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiPlayG26Controller.java:55-67` |
| auth | token required |
| encoding | JSON body (`@RequestBody Map`) |
| params | `sessionId` number required; `nodeId` number required; `requestId` string, canonical lowercase-or-any UUID (36 chars) required; `expectedVersion` integer >=0 required; `answer` string 1..300 required; `longitude`,`latitude`,`accuracy` optional number-or-string forwarded to fence check |
| success `data` | receipt: `contract:"CITY_ORIENTATION_ANSWER_V1", sessionId, nodeId, requestId, payloadHash(sha256 hex), configVersion:long, revision:int, outcome:"APPLIED"|"FAILED", response:{code,msg,data:{...delegate data; nodeId added when applied}}` (`CityOrientationG26Service.java:127-139`). Delegate `data` keys (e.g. xp/puzzleScore): UNKNOWN (PlayBasicCommandApplication not read) |
| errors | 400 `参数有误`; 401 `请先登录`; 403 `无权访问该局`; 409 `requestId 已用于不同的作答`; delegate code >=500 passed through un-recorded (outcome unknown, retry same requestId); 500 `回执序列化失败`/`回执不可读`. Delegate non-200 <500 => stored as `outcome:"FAILED"` inside a 200 envelope |
| idempotency / headers | `requestId` (UUID) per (member,session): same id+same payload hash => stored receipt replayed; same id+different payload => 409. `@RateLimiter 120/10s` |
| iOS caller | `Core/CityOrientationTaskOriginalTransport.swift:52` (matches the answer URL); request built by `Core/CityOrientationTaskOriginalSource.swift:167-170` (sets GET; the answer POST override is done by the transport: line of override not confirmed => UNKNOWN) |

SYNTHETIC request:
```json
POST /api/play/city-orientation/answer
{"sessionId":9001,"nodeId":345,"requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","expectedVersion":3,"answer":"鼓楼","longitude":"118.79","latitude":"32.05","accuracy":"12"}
```
SYNTHETIC response:
```json
{"code":200,"msg":"操作成功","data":{"contract":"CITY_ORIENTATION_ANSWER_V1","sessionId":9001,"nodeId":345,"requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","payloadHash":"<sha256>","configVersion":5,"revision":4,"outcome":"APPLIED","response":{"code":200,"msg":"ok","data":{"nodeId":345}}}}
```

### GET /api/play/city-orientation/receipt
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiPlayG26Controller.java:69-78` |
| auth | token required |
| encoding | query |
| params | `sessionId` Long, `nodeId` Long, `requestId` String (UUID); all required |
| success `data` | stored receipt (same shape as answer) or pending marker `{outcome:"PENDING", sessionId, nodeId, requestId}` when nothing recorded or nodeId differs (`CityOrientationG26Service.java:99-112`) |
| errors | 400 `参数有误`; 401 `请先登录`; 409 `requestId 已用于不同的作答` (stored hash mismatch is impossible here: replay uses stored hash), 500 `回执不可读` |
| idempotency / headers | read-only; `@RateLimiter 120/10s` |
| iOS caller | `Core/CityOrientationTaskOriginalTransport.swift:43`; `Core/CityOrientationTaskOriginalSource.swift:169-170` (GET) |

SYNTHETIC request: `GET /api/play/city-orientation/receipt?sessionId=9001&nodeId=345&requestId=3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f`
SYNTHETIC response (nothing recorded): `{"code":200,"msg":"操作成功","data":{"outcome":"PENDING","sessionId":9001,"nodeId":345,"requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f"}}`

### GET /api/progress/meter
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiProgressG26Controller.java:26-37` (class map `:19`) |
| auth | token required |
| encoding | query (snake_case names) |
| params | `channel_id` Long required (accepted, not used for authorization); `topic_id` Long required; `activity_id` Long optional default 0; `subject_type` String required (must be `MEMBER`); `subject_id` Long required |
| success `data` | if subject != caller or topic has no nodes: `{visible:false}`. Else `visible:true, subjectId, topicId, activityId, required:int, done:int, percent:int, completed:bool, revision:"p<rev>-<done>", visibility:{aggregate:"SELF",detail:"SELF"}, currentNodeId:long|null, completedNodeIds:[long]` (`ProgressMeterG26Service.java:64-79`) |
| errors | 400 `参数有误` (IllegalArgumentException); missing/invalid-typed required params => Spring MVC 400 handling: shape UNKNOWN |
| idempotency / headers | read-only; `@RateLimiter 120/10s` |
| iOS caller | `Core/NativeChannelProgressService.swift:48` |

SYNTHETIC request: `GET /api/progress/meter?channel_id=5&topic_id=12&activity_id=0&subject_type=MEMBER&subject_id=77`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"visible":true,"subjectId":77,"topicId":12,"activityId":0,"required":5,"done":2,"percent":40,"completed":false,"revision":"p3-2","visibility":{"aggregate":"SELF","detail":"SELF"},"currentNodeId":903,"completedNodeIds":[901,902]}}`

### GET /api/progress/requests/{requestId}
| field | value |
|---|---|
| group | G26 |
| controller | `API/ApiProgressG26Controller.java:39-46` |
| auth | token required |
| encoding | path variable |
| params | `requestId` String matching `^[A-Za-z0-9_-]{16,64}$` |
| success `data` | row from `progress_request_receipt_g26` (column names come from mapper XML, not read: UNKNOWN) plus `replayed:true, outcomeKnown:true, outcomeConfirmed:true, effective:{aggregateScope, detailScope}` (`ProgressRequestReadG26Service.java:106-113`). Known keys used: `aggregateScope`, `detailScope` |
| errors | 400 `requestId 无效`; 404 `未找到该请求` + top-level `errorCode:"PROGRESS_REQUEST_NOT_FOUND"` |
| idempotency / headers | read-only; `@RateLimiter 120/10s`. NOTE report: nothing writes this table yet, so every read is 404 until the privacy writer (other group) inserts |
| iOS caller | `Core/NativeChannelProgressService.swift:68` (also `Core/NativeChannelProgressFinalForward.swift:100-111`) |

SYNTHETIC request: `GET /api/progress/requests/3f2b8c1e5a4d4c7e9b1a0a1b2c3d4e5f`
SYNTHETIC response (not found): `{"code":404,"msg":"未找到该请求","errorCode":"PROGRESS_REQUEST_NOT_FOUND"}`

## G27

### POST /api/merchant/poi/detail
| field | value |
|---|---|
| group | G27 |
| controller | `API/ApiMerchantTopicAliasG27Controller.java:34-38`; delegates to `ApiMerchantController.publicDetail` (`API/ApiMerchantController.java:444-459`) |
| auth | token required. Legacy `/api/merchant/public-detail` is permitAll (`SecurityConfig.java:155`) but this alias path is NOT => guests refused (matches report) |
| encoding | JSON body bound to `MmsMerchant` |
| params | body `id` Long required (other MmsMerchant fields ignored) |
| success | `{code:200,msg,data:<PublicMerchantDiscoveryVO>}` plus top-level `officialActivities` (list) and optional top-level `featured`. VO own fields: `chargeType, coopOpen, serviceTag, serviceText, distance, sysCategoryList` + inherited `PublicMerchantVO` fields (not read: UNKNOWN) |
| errors | code 500 (AjaxResult.error default) `缺少商家ID`; `商家不存在或未开放` (default error code presumed 500: `AjaxResult.error(String)` body not read => UNKNOWN code) |
| idempotency / headers | read-only; none |
| iOS caller | `Core/Adapt2MerchantTopicRoutes.swift:37` (route map to `.merchantPublicDetail`); constants `Core/MerchantAndPublishAuthoringAudit.swift:115`, `App/MerchantDecorAndShopApplyWizardSectionView.swift:51`. Live send site UNKNOWN (report says App constants only) |

SYNTHETIC request: `POST /api/merchant/poi/detail` body `{"id":88}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"id":88,"name":"示例咖啡","chargeType":0,"coopOpen":1,"distance":null},"officialActivities":[]}` (fields beyond VO's own are guesses of the parent class: SYNTHETIC)

### POST /api/merchant/shop/apply
| field | value |
|---|---|
| group | G27 |
| controller | `API/ApiMerchantTopicAliasG27Controller.java:40-44`; delegates to `ApiMerchantController.merchantRegistration` (`API/ApiMerchantController.java:2007-2090`) |
| auth | token required (explicit login check inside: error `请先登录`) |
| encoding | JSON body `MerchantRegistrationDTO` (`@Validated`) |
| params | `id` Long (non-null => update path), `categoryId` Integer, `name`, `logo`, `description`, `derivatives`, `website`, `preference`, `phone`, `address` (Strings), `locationLat`,`locationLng` Double, `businessTime`, `businessLicense`, `wechat` (Strings). Required-ness: constraint annotations were not found by grep (`@NotBlank` for name is commented out) => effectively all optional at bean-validation level; `checkRegistered` identity gate applies on new applications |
| success | `{code:200,msg:"更新成功"}` (no `data`) |
| errors | `请先登录`; `当前会员不可用`; `您已加入商家经营团队，不能再申请自己的商家`; identity message from `memberIdentityService.checkRegistered`; `已提交过商家入驻申请，请勿重复提交`; update path: `商家信息不存在`, `无权修改该商家信息`, `该商家账号已停用或不可用，无法修改入驻申请`, `已审核商家请使用店铺资料编辑，不能重新打开入驻申请`; `更新失败`. Numeric code of each = `AjaxResult.error(String)` default (UNKNOWN) |
| idempotency / headers | dedupe by existing merchant row per member (no requestId); `@Transactional`; `@Log` |
| iOS caller | `Core/Adapt2MerchantTopicRoutes.swift:38`; constants `Core/MerchantAndPublishAuthoringAudit.swift:117`, `Core/MerchantDecorAndShopApplyWizardAudit.swift:118`. Live send: UNKNOWN |

SYNTHETIC request: `POST /api/merchant/shop/apply` `{"categoryId":3,"name":"示例咖啡","phone":"13800000000","address":"南京市鼓楼区","locationLat":32.05,"locationLng":118.79}`
SYNTHETIC response: `{"code":200,"msg":"更新成功"}`

### POST /api/topic/detail
| field | value |
|---|---|
| group | G27 |
| controller | `API/ApiMerchantTopicAliasG27Controller.java:46-50`; delegates to `ApiTopicController.topicInfo` (`API/ApiTopicController.java:2055`) |
| auth | token required for the alias (legacy method carries `@Anonymous` at `:2054`, but that annotation is on the other path; alias not whitelisted) |
| encoding | form/query parameter (`String id`); a JSON body is NOT bound |
| params | `id` String (numeric, >0) required |
| success `data` | `TopicInfoVO` (`chengyinhub-system/.../domain/vo/TopicInfoVO.java`): `id, memberId, clubId, topicType, productType, circleThemeCode, name, subtitle, description, addressName, totalTime, totalMileage, locationCount, templateCount, startDate, endDate, merchantSignUpStartDate, merchantSignUpEndDate, imgUrl, imgArr, categoryIds, status, delFlag, userStatus, merchantStatus, openClubPool, publishMode, betaFlag, audioUrl, audioDuration, selfPlay, selfPlayPrice, selfPlayQuota, xpBudget, finishMedalName, finishMedalImg, completeRewardCouponId, recruitDeadline, lifecycle, contentPublisherType, contentPublisherName, remainingMerchantCount, umsMember, sysCategoryList, ratingDistribution, chaptersList, commentList, memberTemplateList, collaboratorsList, omsTicketList, activityList, clubName, rejectReason, perkSellableCapacity, perkCoverageStatus, journeyRules` + setters seen in controller: `canResubmitSupplyReview, merchantClosed, totalChapterCount, unlockedChapterCount, storyLocked, playerCount, registrationMerchantCount`. Types of fields not shown (e.g. Date format, lines 35-120 partially grepped): UNKNOWN beyond Java types listed in VO |
| errors | `参数不合规` (id not positive); not-found / invisible branch text: UNKNOWN (tail of method not read) |
| idempotency / headers | read-only |
| iOS caller | `Core/Adapt2MerchantTopicRoutes.swift:39` (maps to `.topicInfoToUser`); constant `App/PublishTopicAndCommentModerationSectionView.swift:78`. Live send: UNKNOWN |

SYNTHETIC request: `POST /api/topic/detail` form `id=12`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"id":12,"name":"示例主题","status":1,"chaptersList":[],"totalChapterCount":3,"unlockedChapterCount":1,"storyLocked":true,"playerCount":0}}`

### GET /api/merchant/offer-withdrawal/request/current
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/MerchantOfferWithdrawalRequestController.java:15-17` (class map `:8`) |
| auth | token required + merchant `COOP_MANAGE` permission (`MerchantOfferWithdrawalRequestService.authorize`) |
| encoding | query |
| params | `merchantId` Long required, `offerId` Long required |
| success `data` | snapshot: `receiptVersion:1, actorId, merchantId, ownerId, offerId, requestId:null, topicId, chapterId, status, validEndEpoch, termsMode, quotaTotal, quotaUsed, perkId, perHeadFee(string), withdrawReason, withdrawRequired, updatedAtEpoch, chapterRequired, requiredByOriginalRule, topicLifecycle, topicUserStatus, isOrdinary:bool, canWithdraw:bool, snapshotSHA256` (`MerchantOfferWithdrawalRequestService.java` snapshot()) |
| errors | ServiceException message strings with code: `OFFER_WITHDRAWAL_WRITE_NOT_ENABLED` 403 (flag `merchant.offer-withdrawal.original-request.enabled`, default false => all three routes 403), `OFFER_WITHDRAWAL_SCOPE_INVALID` 400, `OFFER_WITHDRAWAL_FORBIDDEN` 403, `OFFER_WITHDRAWAL_OFFER_INVALID` 400, `OFFER_WITHDRAWAL_OFFER_FORBIDDEN` 403, `OFFER_WITHDRAWAL_OWNER_CHANGED` 403, `OFFER_WITHDRAWAL_ACCESS_CHANGED` 403. Delivered as `{code,msg}` where msg = that string (possibly rewritten by UserSafeMessage) |
| idempotency / headers | read-only; response header `Cache-Control: no-store` |
| iOS caller | `Core/MerchantOfferWithdrawalOriginalFlow.swift:115` (base `:24`; GET, query count 2) |

SYNTHETIC request: `GET /api/merchant/offer-withdrawal/request/current?merchantId=88&offerId=501`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"receiptVersion":1,"actorId":77,"merchantId":88,"ownerId":77,"offerId":501,"requestId":null,"status":1,"canWithdraw":true,"isOrdinary":true,"snapshotSHA256":"<sha256>"}}`

### GET /api/merchant/offer-withdrawal/request/result
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/MerchantOfferWithdrawalRequestController.java:18-20` |
| auth | token + merchant COOP_MANAGE |
| encoding | query |
| params | `merchantId` Long, `offerId` Long, `requestId` String (lowercase UUID `[0-9a-f]{8}-...`) all required |
| success `data` | `receiptVersion, actorId, merchantId, ownerId, offerId, requestId` + `outcome:"UNKNOWN"` if no receipt, else stored receipt keys: `intentSHA256, receivedSHA256, expectedSHA256, reasonSHA256, receivedReasonSHA256, outcome (WITHDRAWN|REJECTED_CHANGED|REJECTED_STATE|REJECTED_INPUT), topicId, chapterId, statusAtWrite, requiredAtWrite, userStatusAtWrite, offerUpdatedAt, completedAt` |
| errors | as above plus `OFFER_WITHDRAWAL_REQUEST_INVALID` 400, `OFFER_WITHDRAWAL_REQUEST_CONFLICT` 409 |
| idempotency / headers | read-only; `Cache-Control: no-store` |
| iOS caller | `Core/MerchantOfferWithdrawalOriginalFlow.swift:129` |

SYNTHETIC request: `GET /api/merchant/offer-withdrawal/request/result?merchantId=88&offerId=501&requestId=3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"receiptVersion":1,"actorId":77,"merchantId":88,"ownerId":77,"offerId":501,"requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","outcome":"UNKNOWN"}}`

### POST /api/merchant/offer-withdrawal/request/withdraw
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/MerchantOfferWithdrawalRequestController.java:21-23` |
| auth | token + merchant COOP_MANAGE |
| encoding | JSON body `Withdrawal` |
| params | `merchantId` Long, `offerId` Long, `requestId` UUID string, `intentSHA256` 64-hex, `expectedSHA256` 64-hex, `reasonSHA256` 64-hex, `reason` String (trimmed, 1..500, sha256(trimmed) must equal reasonSHA256) all required; null body => `{code:400,msg:"原退出请求无效"}` |
| success `data` | receipt: identity keys + `intentSHA256, receivedSHA256, expectedSHA256, reasonSHA256, receivedReasonSHA256, outcome, completedAt` (+ `topicId, chapterId, statusAtWrite, requiredAtWrite, userStatusAtWrite, offerUpdatedAt` when WITHDRAWN). Business rejections are `outcome:"REJECTED_*"` inside a 200 |
| errors | 403 `OFFER_WITHDRAWAL_WRITE_NOT_ENABLED` (default); 400 `OFFER_WITHDRAWAL_REQUEST_INVALID`; 409 `OFFER_WITHDRAWAL_PAYLOAD_CONFLICT` / `OFFER_WITHDRAWAL_REQUEST_CONFLICT`; 403 `OFFER_WITHDRAWAL_CHAPTER_CHANGED`/`GRAPH_CHANGED`/`OWNER_CHANGED`/`FORBIDDEN`; 503 `OFFER_WITHDRAWAL_RESULT_UNCONFIRMED` / `OFFER_WITHDRAWAL_RECEIPT_UNCONFIRMED` (outcome unknown, read /result) |
| idempotency / headers | `requestId` (UUID) + three hashes; replay with identical hashes returns stored receipt, mismatch 409. iOS sends `Content-Type: application/json`, body <=16384 bytes |
| iOS caller | `Core/MerchantOfferWithdrawalOriginalFlow.swift:43,184` |

SYNTHETIC request: `POST /api/merchant/offer-withdrawal/request/withdraw` `{"merchantId":88,"offerId":501,"requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","intentSHA256":"<64hex>","expectedSHA256":"<64hex>","reasonSHA256":"<64hex>","reason":"活动结束"}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"receiptVersion":1,"actorId":77,"merchantId":88,"ownerId":77,"offerId":501,"requestId":"3f2b8c1e-...","outcome":"WITHDRAWN","statusAtWrite":0,"completedAt":1793000000000}}`

### POST /api/topic/edit-requests/submit
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/ApiTopicController.java:105-137` (class map `:90`) |
| auth | token required; additionally re-validates session epoch/expiry (`originalProjectRequestContext` `:160-181`) and resolves publisher owner (scope ""|"MERCHANT") |
| encoding | raw JSON string body (`@RequestBody String`), strict parse (no unknown fields, no duplicates) |
| params | envelope fields exactly: `protocolVersion:"original-project-edit-request-v1"`, `requestId`, `originalPath` in {`api/topic/create`,`api/topic/update`,`api/topic/v2/create`,`api/topic/v2/update`}, `payloadSHA256` 64-hex, `payloadBase64Chunks` [base64 strings] (decoded payload 1..2097152 bytes; payload JSON must not contain `requestId`; update must have `id`, create must not; `scope` in payload "" or "MERCHANT"). requestId format: UNKNOWN (not read) |
| success `data` | receipt: `protocolVersion, requestId, originalPath, payloadSHA256, state:"COMMITTED"|"REJECTED"|"UNKNOWN"(NOT_FOUND/UNKNOWN), postProcessing:"UNAVAILABLE", originalResult:{topicId, reviewState(DRAFT|NOT_REQUIRED|PENDING|ESCALATED), published:bool, bundledTemplateIds:[long], auditTaskId?}` (`OriginalProjectEditRequestCodec.java:121-124,106-114`) ; v1 (non-v2) `originalResult` shape: UNKNOWN |
| errors | 503 `原项目请求入口未启用` (bean absent: needs `native.project-edit-requests.enabled=true`; write requires `write-enabled`); 503 `原项目请求结果暂不能确认，请保留原请求`; 400 `原项目编辑参数不合规`/`原项目创建参数不合规` (turned into a REJECTED receipt inside a 200 by `finish`); 401 `原登录会话不可用`; 403 `原发布主体不可用` |
| idempotency / headers | `requestId` + payload hash per actor; conflict (different owner/path/body) => 503 `Original request owner/path/body conflict`. `@RateLimiter 10/60s` |
| iOS caller | constant only: `Core/ProjectEditRequestContract.swift:8` (non-test send site UNKNOWN) |

SYNTHETIC request: `POST /api/topic/edit-requests/submit` `{"protocolVersion":"original-project-edit-request-v1","requestId":"<id>","originalPath":"api/topic/v2/create","payloadSHA256":"<64hex>","payloadBase64Chunks":["eyJuYW1lIjoi..."]}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"protocolVersion":"original-project-edit-request-v1","requestId":"<id>","originalPath":"api/topic/v2/create","payloadSHA256":"<64hex>","state":"COMMITTED","postProcessing":"UNAVAILABLE","originalResult":{"topicId":12,"reviewState":"PENDING","published":false,"bundledTemplateIds":[],"auditTaskId":3}}}`

### POST /api/topic/edit-requests/read
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/ApiTopicController.java:139-143` + `originalProjectRequestRead :149-158` |
| auth | token (same session checks) |
| encoding | raw JSON string |
| params | exactly `protocolVersion, requestId, originalPath, payloadSHA256, scope` (`scope` "" or "MERCHANT") |
| success `data` | same receipt object as submit; `state:"NOT_FOUND"` or `"UNKNOWN"` via `unknown(...)` when no/unreadable row (extra keys of `unknown`: UNKNOWN) |
| errors | 503 `原项目请求恢复未启用` (bean absent); 503 `原项目请求结果暂不能确认，请保留原请求` (any RuntimeException incl. read-disabled `native.project-edit-requests.read-enabled=false`) |
| idempotency / headers | read-only; `@RateLimiter 60/60s` |
| iOS caller | constant only: `Core/ProjectEditRequestContract.swift:9` |

SYNTHETIC request: `{"protocolVersion":"original-project-edit-request-v1","requestId":"<id>","originalPath":"api/topic/v2/create","payloadSHA256":"<64hex>","scope":""}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"requestId":"<id>","state":"NOT_FOUND"}}`

### POST /api/topic/edit-requests/resume-post-processing
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/ApiTopicController.java:145-147` |
| auth | token (same) |
| encoding | raw JSON string (same body as read) |
| params | same as read |
| success `data` | same as read (service just calls `read`; post-processing stays `UNAVAILABLE`) |
| errors | 503 as read; additionally flag `resume-enabled` false => 503 `Original project post-processing recovery disabled` collapsed to `原项目请求结果暂不能确认，请保留原请求` |
| idempotency / headers | `@RateLimiter 30/60s` |
| iOS caller | constant only: `Core/ProjectEditRequestContract.swift:10` |

SYNTHETIC: request/response as read.

### GET /api/topic/module-preflight
| field | value |
|---|---|
| group | G27 (EXISTS) |
| controller | `API/ApiTopicStateKeyController.java:256-268` (class map `:48`) |
| auth | token required; topic owner or merchant PROJECT_MANAGE owner (`editableDenial :278-298`) |
| encoding | query |
| params | `topicId` Long required >0; `expectedConfigVersion` Long required >=0; `scope` String optional ("MERCHANT" for merchant ownership) |
| success `data` | `ModuleValidationReport`: `topicId:long, configVersion:long, ready:bool, issues:[{level, code, field, message, nodeId?}]` (getters `ModuleValidationReport.java:77-83`; Issue extra getter names UNKNOWN beyond level/code/field/message) |
| errors | `参数不合规`; `请先登录`; `主题不存在`; `无权操作该主题`; merchant permission message; ServiceException with code => `{code,msg,errorCode?}` via `coded` (`:179`). Plain `error(...)` numeric code = AjaxResult default (UNKNOWN) |
| idempotency / headers | read-only (no publish, no session) |
| iOS caller | `Core/NativeAttributeAuthorService.swift:27` (query topicId/scope/expectedConfigVersion); `Core/NativeAttributeAuthorHostTransport.swift:26` |

SYNTHETIC request: `GET /api/topic/module-preflight?topicId=12&expectedConfigVersion=4&scope=`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"topicId":12,"configVersion":4,"ready":true,"issues":[]}}`

### POST /api/merchant/npc/voice/script, /api/merchant/npc/voice/revoke (ApiMerchantNpcController)
| field | value |
|---|---|
| group | G27 (report: EXISTS on side branch `feature/shop-npc-p2-0905`) |
| controller | **NOT ON THIS BRANCH**: `ApiMerchantNpcController.java` absent from `origin/claude/be-v2-fixes` (grep of `npc/voice/(script|revoke|reset)` finds only `/npc/voice/reset` at `API/ApiMerchantController.java:1027` and `API/ApiChapterMerchantNodeController.java:335`) |
| auth / encoding / params / success / errors | UNKNOWN (code not on branch) |
| idempotency / headers | UNKNOWN (iOS sends `requestId` on revoke per report) |
| iOS caller | `Core/MerchantNPCHTTP.swift:26-28` (script, enroll, revoke; `post` at `:75`) |

SYNTHETIC: none (cannot derive from code).

## G28

Common (G28 channel routes): `ApiChannelProgressG28Controller.run` wraps `ChannelG28Exception`: response `{code:<http-like>, msg:<errorCode>, errorCode:<errorCode>}` (`API/ApiChannelProgressG28Controller.java:18-25`; `msg` may be rewritten by UserSafeMessage for non-200). Every route requires an active `club_member` row for `channelId` (= `club.id`): else 400 `INVALID_CHANNEL` (channelId null/<=0) or 403 `CHANNEL_MEMBER_REQUIRED` (`ChannelProgressG28Service.java:20-24`). `channelId` is a path Long (non-numeric => Spring 400, shape UNKNOWN). No `@RateLimiter` on G28 controllers. Success JSON uses **snake_case** keys.

### GET /api/channel/{channelId}/board
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:27-28` (class map `:14`) |
| auth | token + active channel member |
| encoding | path |
| params | `channelId` Long |
| success `data` | `{visible:false}` if board disabled or aggregate scope SELF, else `{visible:true, list:[{board_key,title,metric,period,scope,subject_type,team_rollup,row_limit(1..50),visible:true,revision,topic_id,activity_id,filter_schema_json:{completed?:"boolean",team_id?:"int"}}]}` (`:39-63`) |
| errors | 400 INVALID_CHANNEL; 403 CHANNEL_MEMBER_REQUIRED |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelProgressService.swift:12` |

SYNTHETIC request: `GET /api/channel/5/board`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"visible":true,"list":[{"board_key":"main","title":"总榜","metric":"done","period":"ALL","scope":"CHANNEL","subject_type":"MEMBER","team_rollup":"SUM","row_limit":50,"visible":true,"revision":1,"topic_id":12,"activity_id":0,"filter_schema_json":{"completed":"boolean"}}]}}`

### GET /api/channel/{channelId}/board/{key}/top
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:30-34` |
| auth | token + member |
| encoding | path + query |
| params | `key` String `^[a-z][a-z0-9_]{0,31}$`; `period` required in {ALL,TOPIC,WEEK,MONTH}; `limit` Integer optional 1..50 (default 30, capped by board row_limit); `cursor` String optional |
| success `data` | if hidden: `{visible:false, revision}`. Else `{visible:true, revision:"<boardRev>.<maxFactRev>", as_of, board_key, period_key, list:[Row], me:Row|null, has_more:bool, next_cursor:string|null}`; Row = `{subject_type, subject_id, topic_id, activity_id, fact_source:"CHANNEL_PROGRESS_FACT", unit, required, done, completed:bool, percent(0..100), revision:string, as_of, display_name, metric, metric_value:long, rank:int, rank_known:true, visible:true}` (`:93-176`) |
| errors | 400 INVALID_BOARD_KEY / INVALID_PERIOD / INVALID_LIMIT / INVALID_CURSOR; 404 BOARD_NOT_FOUND; 409 BOARD_CURSOR_STALE; 403 CHANNEL_MEMBER_REQUIRED. Missing `period` => Spring 400 (shape UNKNOWN) |
| idempotency / headers | read-only; cursor = base64url(`<revision>|<offset>`) bound to board revision |
| iOS caller | `Core/NativeChannelProgressService.swift:30` (+ `boardPath :74`) |

SYNTHETIC request: `GET /api/channel/5/board/main/top?period=ALL&limit=10`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"visible":true,"revision":"1.7","as_of":"2026-11-08T10:00:00.000000Z","board_key":"main","period_key":"ALL","list":[{"subject_type":"MEMBER","subject_id":77,"topic_id":12,"activity_id":0,"fact_source":"CHANNEL_PROGRESS_FACT","unit":"node","required":5,"done":2,"completed":false,"percent":40,"revision":"7","as_of":"2026-11-08T10:00:00.000000Z","display_name":"甲","metric":"done","metric_value":2,"rank":1,"rank_known":true,"visible":true}],"me":null,"has_more":false,"next_cursor":null}}`

### GET /api/channel/{channelId}/board/{key}/detail
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:36-42` |
| auth | token + member |
| encoding | path + query |
| params | as `top` plus `filter[completed]` Boolean optional, `filter[team_id]` Long optional (>0) |
| success `data` | same page shape as `top` but gated by `detail_scope` privacy and filtered |
| errors | as `top` plus 400 FILTER_NOT_SUPPORTED (board lacks filter support) |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelProgressService.swift:30` (`"/detail"`, filters `:71-72`) |

SYNTHETIC request: `GET /api/channel/5/board/main/detail?period=ALL&limit=20&filter[completed]=true`
SYNTHETIC response: same shape as top (SYNTHETIC).

### GET /api/channel/{channelId}/board/{key}/version
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:44-45` |
| auth | token + member |
| encoding | path |
| params | `key` |
| success `data` | `{visible:bool, revision:"<boardRev>.<maxFactRev>"}` |
| errors | 400 INVALID_BOARD_KEY; 404 BOARD_NOT_FOUND; 403 |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelProgressService.swift:44` |

SYNTHETIC request: `GET /api/channel/5/board/main/version` ; response `{"code":200,"msg":"操作成功","data":{"visible":true,"revision":"1.7"}}`

### GET /api/channel/{channelId}/board/{key}/me/best
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:47-50` |
| auth | token + member |
| encoding | path + query |
| params | `key`, `period` required |
| success `data` | Row (as above) for caller, or `{state:"NO_COMPLETED_EFFORT", rank_known:false, reason:"NO_FACT_FOR_PERIOD"}` |
| errors | 400 INVALID_BOARD_KEY/INVALID_PERIOD; 404 BOARD_NOT_FOUND; 403 |
| idempotency / headers | read-only. NOTE: does not apply privacy gating (unlike top/detail) |
| iOS caller | `Core/NativeChannelProgressService.swift:34` |

SYNTHETIC request: `GET /api/channel/5/board/main/me/best?period=ALL` ; response `{"code":200,"msg":"操作成功","data":{"state":"NO_COMPLETED_EFFORT","rank_known":false,"reason":"NO_FACT_FOR_PERIOD"}}`

### GET /api/channel/{channelId}/board/{key}/me/recent
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:52-56` |
| auth | token + member |
| encoding | path + query |
| params | `key`; `period` required; `limit` 1..50 default 30; `cursor` optional |
| success `data` | `{visible:true, revision, board_key, period_key, list:[Row], has_more, next_cursor}` |
| errors | as top (INVALID_LIMIT/INVALID_CURSOR/BOARD_CURSOR_STALE etc.) |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelProgressService.swift:40` |

SYNTHETIC request: `GET /api/channel/5/board/main/me/recent?period=WEEK&limit=10` ; response shape per above.

### GET /api/channel/{channelId}/progress/overview
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:58-59` |
| auth | token + member |
| encoding | path |
| params | `channelId` |
| success `data` | `{visible:false}` if no boards/disabled/SELF; else `{visible:true, channel_id, topic_id, activity_id, revision, as_of:null, members:{total,total_capped,completed,avg_percent|null}, teams:[{team_id,rollup,required,done,completed}]}` (`:179-207`) |
| errors | 400 INVALID_CHANNEL; 403 CHANNEL_MEMBER_REQUIRED |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelProgressService.swift:19` |

SYNTHETIC request: `GET /api/channel/5/progress/overview`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"visible":true,"channel_id":5,"topic_id":12,"activity_id":0,"revision":"1.7","as_of":null,"members":{"total":10,"total_capped":false,"completed":3,"avg_percent":42},"teams":[]}}`

### GET /api/channel/{channelId}/progress/privacy
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:61-62` |
| auth | token + member (manager not required to read) |
| encoding | path |
| params | `channelId` |
| success `data` | `{actor_id, scope_type:"CHANNEL", scope_id, aggregate_scope, detail_scope, photo_scope:null, leaderboard_scope:null, board_enabled:0|1, revision, updated_at|null, verified_at:null, is_default:bool, applies_to:"ALL", editable_fields:["aggregate_scope"], can_write:bool, aggregate_verified:false}` (`:210-226`); defaults PUBLIC/CHANNEL/1/rev 0 |
| errors | 400 INVALID_CHANNEL; 403 CHANNEL_MEMBER_REQUIRED |
| idempotency / headers | read-only |
| iOS caller | path built `Core/NativeProgressPrivacyContracts.swift:17`; GET at `Core/NativeProgressPrivacyService.swift:34` |

SYNTHETIC request: `GET /api/channel/5/progress/privacy`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"actor_id":77,"scope_type":"CHANNEL","scope_id":5,"aggregate_scope":"PUBLIC","detail_scope":"CHANNEL","photo_scope":null,"leaderboard_scope":null,"board_enabled":1,"revision":0,"updated_at":null,"verified_at":null,"is_default":true,"applies_to":"ALL","editable_fields":["aggregate_scope"],"can_write":false,"aggregate_verified":false}}`

### POST /api/channel/{channelId}/progress/privacy
| field | value |
|---|---|
| group | G28 |
| controller | `API/ApiChannelProgressG28Controller.java:64-67` |
| auth | token + active member with `club_member.role >= 1` (unverified meaning of role, per report) |
| encoding | JSON body |
| params | body keys must be EXACTLY `request_id` (UUID string), `aggregate_scope` in {SELF,TEAM,CHANNEL,PUBLIC}, `expected_revision` (integer 0..Integer.MAX-1); extra/missing key => 400 |
| success `data` | `{actor_id, request_id(lowercased), scope_type:"CHANNEL", scope_id, payload_hash, outcome:"APPLIED", reason:null, applied_updated_at, applied_revision}` or, on stale revision, `outcome:"REJECTED", reason:"REVISION_CONFLICT", applied_updated_at:null, applied_revision:null` (not recorded; HTTP envelope still code 200) |
| errors | 403 CHANNEL_MANAGER_REQUIRED; 400 INVALID_BODY / INVALID_REQUEST_ID / INVALID_SCOPE / INVALID_REVISION; 409 REQUEST_ID_REUSED; 500 RECEIPT_CORRUPT |
| idempotency / headers | `request_id` per (member,family PROGRESS_PRIVACY): same id+same hash returns stored result; different hash 409. Transactional |
| iOS caller | `Core/NativeProgressPrivacyService.swift:39` (POST, path `Core/NativeProgressPrivacyContracts.swift:17`) |

SYNTHETIC request: `POST /api/channel/5/progress/privacy` `{"request_id":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","aggregate_scope":"CHANNEL","expected_revision":0}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"actor_id":77,"request_id":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","scope_type":"CHANNEL","scope_id":5,"payload_hash":"<sha256>","outcome":"APPLIED","reason":null,"applied_updated_at":"2026-11-08 10:00:00.000000","applied_revision":1}}`

### GET /api/channel-platform/{family}/requests/{requestId}  (5 routes)
Routes (controller `API/ApiChannelPlatformReceiptG28Controller.java`, class map `:11`):
1. `GET /api/channel-platform/admission/requests/{requestId}` `:18-19` family ADMISSION; iOS `Core/NativeChannelOnboarding.swift:14`, `Core/ChannelAdmissionGovernanceClient.swift:16`
2. `GET /api/channel-platform/governance/moderation/requests/{requestId}` `:20-21` MODERATION; iOS `Core/NativeChannelModerationFlow.swift:230`
3. `GET /api/channel-platform/governance/reports/requests/{requestId}` `:22-23` REPORT; iOS `Core/NativeChannelReportFlow.swift:166`
4. `GET /api/channel-platform/governance/requests/{requestId}` `:24-25` GOVERNANCE; iOS `Core/NativeChannelRoleFlow.swift:312`, `Core/NativeChannelManagementIntent.swift:74`
5. `GET /api/channel-platform/requests/{requestId}` `:26-27` METADATA; iOS `Core/NativeChannelManagementIntent.swift:74`

| field | value |
|---|---|
| group | G28 |
| auth | token required (no channel-membership check; receipts scoped by member id) |
| encoding | path |
| params | `requestId` String `^[A-Za-z0-9_-]{8,64}$` |
| success `data` | not found: `{request_id, state:"NOT_FOUND", retry_with_original_request:true}`; found: `{request_id, state:"APPLIED", operation, guild_kind, guild_id:string|null, object_id, request_hash, result:<stored JSON object>}` (`ChannelReceiptG28Service.java:26-39`). `result` shape depends on writer: UNKNOWN. NOTE: no writer exists on this branch for these families (report), so the answer is always NOT_FOUND |
| errors | 400 INVALID_REQUEST_ID; 500 RECEIPT_CORRUPT. `ApiChannelProgressG28Controller.run` envelope (`code`,`msg`,`errorCode`) |
| idempotency / headers | read-only |

SYNTHETIC request: `GET /api/channel-platform/admission/requests/req_12345678`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"request_id":"req_12345678","state":"NOT_FOUND","retry_with_original_request":true}}`

## G29

Common: errors are `{code, msg, errorCode?}` from `ServiceException` (`biz()` in both controllers); unexpected exceptions => `{code:500,msg:"操作失败，请稍后重试"}`. `errorCode` is `ServiceException.getDetailMessage()`. Member from token only (`getAppUserId`); 401 `请先登录` if absent.

### GET /api/im/channel/checkin-status
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImChannelCheckinG29Controller.java:29-35` (class map `:23`) |
| auth | token + active member of an `im_conversation` of type 4, status 0 |
| encoding | query |
| params | `channel_id` String canonical numeric id (required in practice; null => 400 INVALID_CHANNEL) |
| success `data` | `source:"original-channel-checkin-v1", actorId:str, channelId:str, timezone:"Asia/Shanghai", checkinDate:"yyyy-MM-dd", serverTime:long, nextDayAt:long, checked:bool, canCheckin:bool, makeupSelfService:false, rewardPolicyConfigured:false, fact:Fact|null, streak:int, streakThrough:str|null, history:[{checkinDate,kind:"CHECKIN"}], makeupPolicy:{configured:false,enabled:false,timezone}`; Fact = `{id:str,channelId:str,memberId:str,checkinDate,source,streak:int,checkedAt:long}` (`ImChannelCheckinG29ServiceImpl.java` status/factView). Exact key set of `history` items beyond `checkinDate`,`kind`: UNKNOWN |
| errors | 400 INVALID_CHANNEL; 404 CHANNEL_NOT_FOUND; 403 NOT_CHANNEL_MEMBER; 409 CHANNEL_CLOSED; 401 |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelCheckin.swift:200` (allow-list `Core/BusinessRuntimeConfiguration.swift:228`) |

SYNTHETIC request: `GET /api/im/channel/checkin-status?channel_id=4001`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-channel-checkin-v1","actorId":"77","channelId":"4001","timezone":"Asia/Shanghai","checkinDate":"2026-11-08","serverTime":1793000000000,"nextDayAt":1793030400000,"checked":false,"canCheckin":true,"makeupSelfService":false,"rewardPolicyConfigured":false,"fact":null,"streak":0,"streakThrough":null,"history":[],"makeupPolicy":{"configured":false,"enabled":false,"timezone":"Asia/Shanghai"}}}`

### GET /api/im/channel/checkin-rank
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImChannelCheckinG29Controller.java:37-45` |
| auth | token + channel member |
| encoding | query |
| params | `channel_id` String; `days` int default 30 (must be 30); `limit` int default 10 (must be 10 or 50) |
| success `data` | `source, actorId, channelId, timezone, checkinDate, serverTime, nextDayAt, periodDays:30, limit, list:[RankRow], me:RankRow, othersVisible:true, hasMore:bool`; RankRow = `{memberId:str, rank:int|null, days:int, makeupDays:0, streak:int, nickname, avatar}` (`rankRow` ~`:160-175`) |
| errors | 400 INVALID_RANK_QUERY / INVALID_CHANNEL; 403 NOT_CHANNEL_MEMBER; 404 CHANNEL_NOT_FOUND; 409 CHANNEL_CLOSED |
| idempotency / headers | read-only |
| iOS caller | `Core/NativeChannelCheckin.swift:205` (sends days=30, limit) |

SYNTHETIC request: `GET /api/im/channel/checkin-rank?channel_id=4001&days=30&limit=10`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-channel-checkin-v1","actorId":"77","channelId":"4001","timezone":"Asia/Shanghai","checkinDate":"2026-11-08","serverTime":1793000000000,"nextDayAt":1793030400000,"periodDays":30,"limit":10,"list":[{"memberId":"77","rank":1,"days":3,"makeupDays":0,"streak":3,"nickname":"甲","avatar":null}],"me":{"memberId":"77","rank":1,"days":3,"makeupDays":0,"streak":3,"nickname":"甲","avatar":null},"othersVisible":true,"hasMore":false}}`

### GET /api/im/channel/checkin-request
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImChannelCheckinG29Controller.java:47-55` |
| auth | token + channel member |
| encoding | query |
| params | `channel_id` String; `request_id` String canonical UUID; `checkin_date` String `yyyy-MM-dd`; all required (else 400 INVALID_REQUEST) |
| success `data` | `{source:"original-channel-checkin-request-v1", actorId, channelId, requestId, state:"APPLIED"|"NOT_FOUND", requestHash, checkinDate, unappliedFinal?:bool (NOT_FOUND only; true if date != today), resultRedacted:false, result:Fact+{resultCode:"CHECKED"|"ALREADY_CHECKED", rewardIssued:false}}` (result keys only when APPLIED). `resultCode` values per report; code constants not re-grepped |
| errors | 400 INVALID_REQUEST; 409 REQUEST_ID_REUSED; plus channel errors as above |
| idempotency / headers | read-only; hash = sha256 of length-prefixed ["checkin-v1",channelId,date] |
| iOS caller | `Core/NativeChannelCheckin.swift:209` |

SYNTHETIC request: `GET /api/im/channel/checkin-request?channel_id=4001&request_id=3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f&checkin_date=2026-11-08`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-channel-checkin-request-v1","actorId":"77","channelId":"4001","requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","state":"NOT_FOUND","requestHash":"<sha256>","checkinDate":"2026-11-08","unappliedFinal":false}}`

### POST /api/im/channel/checkin
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImChannelCheckinG29Controller.java:57-67` |
| auth | token + channel member |
| encoding | JSON body (`Map`; non-string values coerced to null) |
| params | `channelId` string, `requestId` string UUID, `checkinDate` string `yyyy-MM-dd` (must equal server date Asia/Shanghai) |
| success `data` | same receipt shape as checkin-request, `state:"APPLIED"`, `result` with `resultCode`, `rewardIssued:false` |
| errors | 400 INVALID_REQUEST; 409 CHECKIN_DATE_MISMATCH; 409 REQUEST_ID_REUSED; 409 CHANNEL_CLOSED; 403 NOT_CHANNEL_MEMBER; 404 CHANNEL_NOT_FOUND; 500 `打卡结果待确认` (no errorCode; outcome unknown, read /checkin-request) |
| idempotency / headers | `requestId` UUID per (channel, member); replay returns stored receipt |
| iOS caller | `Core/NativeChannelCheckin.swift:213` (allow `Core/BusinessRuntimeConfiguration.swift:229`) |

SYNTHETIC request: `POST /api/im/channel/checkin` `{"channelId":"4001","requestId":"3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f","checkinDate":"2026-11-08"}`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-channel-checkin-request-v1","actorId":"77","channelId":"4001","requestId":"3f2b8c1e-...","state":"APPLIED","requestHash":"<sha256>","checkinDate":"2026-11-08","resultRedacted":false,"result":{"id":"1","channelId":"4001","memberId":"77","checkinDate":"2026-11-08","source":"CHANNEL","streak":1,"checkedAt":1793000000000,"resultCode":"CHECKED","rewardIssued":false}}}`

### POST /api/im/voice/upload
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImVoiceG29Controller.java:114-131` (class map `:108`) |
| auth | token + active member of non-system conversation (type != 2) with status 0 |
| encoding | multipart/form-data |
| params | `conversation_id` String numeric `[1-9][0-9]{0,17}`; `upload_request_id` canonical UUID; `source_sha256` 64 lowercase hex (sha256 of file bytes); `file` MultipartFile audio/mp4 (ftyp box), 1..2097152 bytes; `duration_ms` Integer optional (else parsed from mvhd; 1..60000); `waveform` String optional (base64 <=256 bytes; default flat) |
| success `data` | `{source:"original-im-voice-upload-v1", state:"UPLOADED", upload_request_id, source_sha256, conversation_id:str, owner_member_id:str, asset_id:str, review_state:"HOLD"(until reviewed), duration_ms:int, size:int, waveform:str, asr_state:str}` |
| errors | 400 INVALID_CONVERSATION_ID / INVALID_UPLOAD_REQUEST_ID / INVALID_SOURCE_SHA256 / INVALID_AUDIO_SIZE / INVALID_AUDIO_FORMAT / SOURCE_HASH_MISMATCH / INVALID_AUDIO_DURATION / INVALID_WAVEFORM; 403 NOT_CONVERSATION_MEMBER / VOICE_NOT_ALLOWED; 404 CONVERSATION_NOT_FOUND; 409 UPLOAD_REQUEST_REUSED / IM_CONVERSATION_CLOSED; 429 UPLOAD_QUOTA_EXCEEDED (100/24h); 500 `上传结果待确认`. Oversized multipart => container error, shape UNKNOWN (limits not verified, per report) |
| idempotency / headers | `upload_request_id` per (conversation, owner); same id+same sha => stored receipt; different sha 409. `@RateLimiter 10/60s per member` |
| iOS caller | `Core/IMVoiceService.swift:36` (form request; iOS does not send duration_ms/waveform per report) |

SYNTHETIC request: `POST /api/im/voice/upload` multipart: `conversation_id=4001`, `upload_request_id=3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f`, `source_sha256=<64hex>`, `file=@voice.m4a`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-im-voice-upload-v1","state":"UPLOADED","upload_request_id":"3f2b8c1e-...","source_sha256":"<64hex>","conversation_id":"4001","owner_member_id":"77","asset_id":"55","review_state":"HOLD","duration_ms":3200,"size":48211,"waveform":"<base64>","asr_state":"TEXT_APPROVED"}}`

### GET /api/im/voice/receipt
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImVoiceG29Controller.java:133-141` |
| auth | token + conversation member |
| encoding | query |
| params | `conversation_id`, `upload_request_id`, `source_sha256` (formats as upload) |
| success `data` | same as upload; if none: `{source, state:"NOT_FOUND", upload_request_id, source_sha256, conversation_id, owner_member_id}` |
| errors | 400 INVALID_*; 403/404/409 as upload (409 UPLOAD_REQUEST_REUSED if sha differs) |
| idempotency / headers | read-only |
| iOS caller | `Core/IMVoiceService.swift:48` |

SYNTHETIC request: `GET /api/im/voice/receipt?conversation_id=4001&upload_request_id=3f2b8c1e-5a4d-4c7e-9b1a-0a1b2c3d4e5f&source_sha256=<64hex>`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-im-voice-upload-v1","state":"NOT_FOUND","upload_request_id":"3f2b8c1e-...","source_sha256":"<64hex>","conversation_id":"4001","owner_member_id":"77"}}`

### GET /api/im/voice/message/{messageId}
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImVoiceG29Controller.java:151-175` |
| auth | token + current conversation member |
| encoding | path |
| params | `messageId` Long |
| success | **not an envelope**: HTTP 200, `Content-Type: audio/mp4`, `Cache-Control: private, no-store`, raw bytes |
| errors | real HTTP status 400/401/403/404/409 (others => 500) with JSON body `{"code":N,"msg":"...","errorCode":"..."}`: INVALID_MESSAGE_ID 400, MESSAGE_NOT_FOUND 404, VOICE_NOT_AVAILABLE 404, VOICE_NOT_APPROVED 403 (asset must be review_state APPROVED), NOT_CONVERSATION_MEMBER 403, IM_CONVERSATION_CLOSED 409; unexpected => 500 empty body. Auth failure status/shape from the filter chain: UNKNOWN |
| idempotency / headers | read-only; iOS sends `Accept: audio/mp4` |
| iOS caller | `Core/IMVoiceService.swift:58-59` (GET) |

SYNTHETIC request: `GET /api/im/voice/message/9001` ; response: binary mp4 bytes (200) or `{"code":403,"msg":"语音未通过审核","errorCode":"VOICE_NOT_APPROVED"}` with HTTP 403.

### GET /api/im/voice/message/{messageId}/authorization
| field | value |
|---|---|
| group | G29 |
| controller | `API/ApiImVoiceG29Controller.java:143-149` |
| auth | token + conversation member |
| encoding | path |
| params | `messageId` Long |
| success `data` | `{source:"original-im-voice-authorization-v1", message:{...all stored im_message columns (names from mapper XML: UNKNOWN), content:"[语音]", extraJson:"{\"source\":\"original-im-voice-v1\",\"mime\":\"audio/mp4\",\"assetId\":\"<id>\",\"uploadRequestId\":\"<uuid>\",\"durationSec\":<double>,\"size\":<int>,\"waveform\":\"<b64>\"}"}}` (`safeMessage`) |
| errors | same set as audio, but delivered in the 200 envelope `{code,msg,errorCode}` |
| idempotency / headers | read-only |
| iOS caller | `Core/IMVoiceService.swift:66-67` (GET) |

SYNTHETIC request: `GET /api/im/voice/message/9001/authorization`
SYNTHETIC response: `{"code":200,"msg":"操作成功","data":{"source":"original-im-voice-authorization-v1","message":{"id":9001,"conversationId":4001,"msgType":10,"content":"[语音]","extraJson":"{\"source\":\"original-im-voice-v1\",\"mime\":\"audio/mp4\",\"assetId\":\"55\",\"uploadRequestId\":\"3f2b8c1e-...\",\"durationSec\":3.2,\"size\":48211,\"waveform\":\"<b64>\"}"}}}`

---
Route count in this part: G26 = 6; G27 = 10 on branch (3 aliases, 3 offer-withdrawal, 3 edit-requests, 1 module-preflight) + 2 NOT ON THIS BRANCH (npc/voice/script, revoke); G28 = 14 (9 channel + 5 receipt); G29 = 8. Total 38 (36 on branch).

<!-- Part B: G30, G31, G32. Static read of origin/claude/be-v2-fixes; iOS = origin/wip/wave5-build. All examples are SYNTHETIC. -->
Conventions (apply to every row): Controller dir = `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/` (abbrev `C/`). `AjaxResult` envelope = `{code, msg, data?}` and business errors are returned as `AjaxResult.error(code,msg)`; whether HTTP status equals `code` is UNKNOWN for AjaxResult routes (only the `ResponseEntity` routes set HTTP status explicitly). Auth "token" = JWT app-user; `SecurityConfig.java` (chengyinhub-framework/.../config/SecurityConfig.java:153,163) ends with `anyRequest().authenticated()`; no matcher in it names the G30–G32 paths except `/api/common/**` (line 153). G31 controllers extend `ApiG31Support` (`C/ApiG31Support.java`): member id from token only; missing login -> `G31Exception(401,"LOGIN_REQUIRED")`; errors are `{code, msg, errorCode, businessCode}` (errorCode==businessCode). Header requirements: no controller in this part reads a custom header (only the standard token header; its exact name is UNKNOWN here).

## G30

### POST /api/project/state-requests/context
- group: G30 | controller: `C/ApiProjectStateRequestG30Controller.java:73` (class mapping :28)
- auth: token required (no guest). Controller also returns 401 `请先登录` if no actor. RateLimiter 60/60s per member.
- encoding: JSON. params: `kind` string required (`template|topic|activity`), `resourceId` number >0 required.
- success: `{code:200, data:{protocolVersion:"original-project-state-request-v1", kind:string, resourceId:number, title:string, online:boolean, baselineHash:string(sha256 hex)}}`
- errors: 401 请先登录; 400 参数不合规; 404 项目不存在 (also when not owner).
- idempotency: none (read). iOS caller: `Core/ProjectStateRequestContract.swift:5` (path constant; transport call site UNKNOWN)
- SYNTHETIC req: `{"kind":"topic","resourceId":123}` -> `{"code":200,"data":{"protocolVersion":"original-project-state-request-v1","kind":"topic","resourceId":123,"title":"Demo","online":true,"baselineHash":"<64 hex>"}}`

### POST /api/project/state-requests/submit
- controller: `C/ApiProjectStateRequestG30Controller.java:105`; auth token; RateLimiter 30/60s per member.
- encoding: JSON. params: `protocolVersion` string req (must equal `original-project-state-request-v1`), `requestId` string req (lower-case UUID), `payloadSHA256` string req (64 hex), `payloadBase64Chunks` string[] req (<=86 chunks, each <=32768 chars, decoded <=2,097,152 bytes, sha256 must match). Decoded payload is JSON `{originalPath, resourceId, baselineHash, expectedOnline}`; `originalPath` in `api/template/delete|api/template/updateLibraryStatus|api/topic/delete|api/topic/update_user_status|api/activity/delete|api/activity/update_publish_status`.
- success: `{code:200,data:{protocolVersion, requestId, payloadSHA256, originalPath, kind, resourceId, state:string("NOT_FOUND" or ledger state; COMMITTED/REJECTED set by this controller; other values UNKNOWN), originalResult:object|null ({applied:boolean,code:number,msg:string})}}`
- errors: 401; 400 请求无效/请求内容无效/请求内容校验失败; 409 原请求号对应的内容不一致 (same requestId, different payload hash); 500 请求处理失败，请稍后用同一请求号查询. A stale baseline/owner/online state returns success with state REJECTED and originalResult.code 409 (项目状态已变化，请刷新后重试).
- idempotency: `requestId` (+ payloadSHA256), ledger keyed (actor, protocol, requestId); replay returns stored receipt.
- iOS caller: `Core/ProjectStateRequestContract.swift:6`
- SYNTHETIC req: `{"protocolVersion":"original-project-state-request-v1","requestId":"0b8f3c2e-1111-4222-8333-444455556666","payloadSHA256":"<64 hex>","payloadBase64Chunks":["<base64>"]}` -> `{"code":200,"data":{"protocolVersion":"original-project-state-request-v1","requestId":"0b8f3c2e-...","payloadSHA256":"<64 hex>","originalPath":"api/topic/delete","kind":"topic","resourceId":123,"state":"COMMITTED","originalResult":{"applied":true,"code":200,"msg":"..."}}}`

### POST /api/project/state-requests/read
- controller: `C/ApiProjectStateRequestG30Controller.java:164`; auth token; RateLimiter 120/60s.
- encoding JSON. params: `protocolVersion` req, `requestId` req (lower UUID), `payloadSHA256` req (64 hex), `originalPath` string (used only when no ledger row; must be one of the six paths), `resourceId` number, `baselineHash` string, `expectedOnline` boolean (last three are declared but not otherwise used by the code).
- success: same receipt shape as submit (state `NOT_FOUND` when absent).
- errors: 401; 400 请求无效; 409 原请求号对应的内容不一致.
- idempotency: read-only keyed by requestId. iOS: `Core/ProjectStateRequestContract.swift:7`
- SYNTHETIC req: `{"protocolVersion":"original-project-state-request-v1","requestId":"0b8f3c2e-1111-4222-8333-444455556666","payloadSHA256":"<64 hex>","originalPath":"api/topic/delete","resourceId":123}` -> `{"code":200,"data":{...receipt as above, "state":"NOT_FOUND","originalResult":null}}`

### POST /api/template/author-requests/submit
- controller: `C/ApiTemplateAuthorRequestG30Controller.java:53` (class mapping :28); auth token; RateLimiter 20/60s.
- encoding JSON: `protocolVersion` (`original-template-author-request-v1`), `requestId` (lower UUID), `payloadSHA256`, `payloadBase64Chunks[]` (same limits as above). Decoded payload: exactly two keys `{originalPath:"api/template/draft"|"api/template/publish", fields:{...CmsTemplatePublishRequest}}`; embedded `requestId` must be absent or equal; `scope` must be empty; publish also bean-validated.
- success: `{code:200,data:{protocolVersion, requestId, payloadSHA256, state, originalResult:{memberTemplateId:number}|{code,msg}|null, postProcessing:null, processing:null, auditState:null, auditActions:null}}` (the four trailing fields are always null in code).
- errors: 401; 400 请求无效/请求内容无效; 409 原请求号对应的内容不一致; 500 请求处理失败，请稍后用同一请求号查询. Delegate failure => state REJECTED with originalResult {code,msg}.
- idempotency: requestId + payload hash. iOS: `Core/TemplateAuthoringRequestReceipt.swift:8`
- SYNTHETIC: req `{"protocolVersion":"original-template-author-request-v1","requestId":"<uuid>","payloadSHA256":"<64 hex>","payloadBase64Chunks":["<base64 of {\"originalPath\":\"api/template/draft\",\"fields\":{...}}>"]}` -> `{"code":200,"data":{"protocolVersion":"original-template-author-request-v1","requestId":"<uuid>","payloadSHA256":"<64 hex>","state":"COMMITTED","originalResult":{"memberTemplateId":77},"postProcessing":null,"processing":null,"auditState":null,"auditActions":null}}`

### POST /api/template/author-requests/read
- controller: `C/ApiTemplateAuthorRequestG30Controller.java:111`; auth token; RateLimiter 120/60s.
- JSON: `protocolVersion`, `requestId` (lower UUID), `payloadSHA256` (64 hex), all required.
- success: same receipt as submit (`state` "NOT_FOUND" if absent). errors: 401; 400 请求无效; 409 原请求号对应的内容不一致.
- iOS: `Core/TemplateAuthoringRequestReceipt.swift:9`
- SYNTHETIC: `{"protocolVersion":"original-template-author-request-v1","requestId":"<uuid>","payloadSHA256":"<64 hex>"}` -> `{"code":200,"data":{...,"state":"NOT_FOUND","originalResult":null,"postProcessing":null,"processing":null,"auditState":null,"auditActions":null}}`

### GET /api/template/report-receipt
- controller: `C/ApiTemplateReportReceiptG30Controller.java:27` (class mapping :21); auth token (controller 401 `请先登录`). Read-only.
- encoding: query (form-style). params: `kind` string req (`TEMPLATE|TEMPLATE_LIBRARY`), `id` Long req (>0), `reasonSHA256` string optional (64 hex).
- success: `{code:200,data:{kind, id, actorMemberId, state:"NOT_REPORTED"|"REPORTED", [auditRecordId, auditTaskId, auditStatus (types UNKNOWN, from mapper row)], [reasonMatches:boolean when reasonSHA256 given]}}`
- errors: 401 请先登录; 400 参数不合规. idempotency: n/a. iOS: `Core/TemplateContentReportContracts.swift:11`
- SYNTHETIC: `GET /api/template/report-receipt?kind=TEMPLATE&id=9` -> `{"code":200,"data":{"kind":"TEMPLATE","id":9,"actorMemberId":5,"state":"NOT_REPORTED"}}`

### POST /api/template/report-receipt
- controller: `C/ApiTemplateReportReceiptG30Controller.java:33`; same as GET above but params are `@RequestParam` (query or urlencoded form body accepted by Spring; which the iOS uses: UNKNOWN). Response identical.
- iOS: `Core/TemplateContentReportContracts.swift:11` (method used UNKNOWN)
- SYNTHETIC: `kind=TEMPLATE_LIBRARY&id=9&reasonSHA256=<64 hex>` -> `{"code":200,"data":{"kind":"TEMPLATE_LIBRARY","id":9,"actorMemberId":5,"state":"REPORTED","auditRecordId":1,"auditTaskId":2,"auditStatus":0,"reasonMatches":true}}`

### POST /api/us/auth/apple/challenges
- controller: `C/ApiUsAppleAuthG30Controller.java:47` (class mapping :34). Class is `@ConditionalOnProperty(app.auth.us.apple.enabled=false, matchIfMissing=true)` (property name inverse of the sys-config key `us.apple.enabled` — verify at deploy). auth: GUEST (`@Anonymous`); RateLimiter 20/60s per IP. Also requires sys-config `us.apple.enabled=true`.
- encoding: JSON, no body fields read (iOS sends `{}`).
- success (`ResponseEntity`, `Cache-Control: no-store`): `{code:200,data:{challengeId:string,rawNonce:string,state:string,expiresIn:number(seconds),market:"US",provider:"apple"}}`
- errors (HTTP status == code; body `{code,errorCode,msg}`): 503 US_APPLE_UNAVAILABLE.
- idempotency: none (each call issues a new challenge). iOS: `Core/USAppleService.swift:92`
- SYNTHETIC: `{}` -> `{"code":200,"data":{"challengeId":"<rand>","rawNonce":"<rand>","state":"<rand>","expiresIn":300,"market":"US","provider":"apple"}}` (expiresIn value = `UsAppleG30Service.TTL_SECONDS`; number not read)

### POST /api/us/auth/apple/exchange
- controller: `C/ApiUsAppleAuthG30Controller.java:70`; GUEST (`@Anonymous`); RateLimiter 20/60s per IP.
- JSON: `challengeId` string req, `state` string req (both must pass `isRandomValue`), `identityToken` string req (<=16384 chars, printable ASCII 0x21–0x7e).
- success: `{code:200, token:string (key = Constants.TOKEN; literal name UNKNOWN here), market:"US", data:{id,userType,avatar,nickname,role}}` (`Cache-Control: no-store`).
- errors: 400 US_APPLE_INVALID_REQUEST; 401 US_APPLE_INVALID_CHALLENGE / US_APPLE_INVALID_IDENTITY; 503 US_APPLE_UNAVAILABLE.
- idempotency: challenge is single-use (burned before token verification). iOS: `Core/USAppleService.swift:104`
- SYNTHETIC: `{"challengeId":"<rand>","state":"<rand>","identityToken":"<apple jwt>"}` -> `{"code":200,"token":"<jwt>","market":"US","data":{"id":10,"userType":1,"avatar":null,"nickname":"城瘾用户","role":"player"}}`

### GET /api/us/auth/session
- controller: `C/ApiUsAppleAuthG30Controller.java:130`; auth token required (not @Anonymous; controller 401 `请先登录`).
- no params. success: `{code:200,data:{market:"US",realm:string,account:{id,userType,avatar,nickname,role}}}`
- errors: 401 `请先登录` / `非美国区账号` (body `{code,msg}`); 503 US_SESSION_UNAVAILABLE. iOS: `Core/USAppleService.swift:121`
- SYNTHETIC: -> `{"code":200,"data":{"market":"US","realm":"<realm>","account":{"id":10,"userType":1,"avatar":null,"nickname":"城瘾用户","role":"player"}}}`

### GET /api/common/uploadOSS/receipt
- controller: `C/ApiCommonUploadReceiptG30Controller.java:22` (class mapping :16). Auth: controller requires login (401 `请先登录`). SecurityConfig line 137 lists `/api/common/uploadOSS` and `/api/common/uploadOSS/` as authenticated but line 153 permits `/api/common/**`; whether `…/receipt` matches the exact-path matcher is UNKNOWN (legacyMatchers semantics not read), so filter-level guest access is UNKNOWN; the controller itself rejects guests.
- encoding: query. `request_id` string req, `source_sha256` string req (64 hex lower).
- success (flat body, not under `data`): `{code:200, uploadProtocol:"original-upload-request-v1", uploadRequestId:string, sourceSHA256:string, uploadState:"NOT_FOUND"|"PENDING"|"UPLOADED", [url, fileName, reviewState:"APPROVED" when UPLOADED]}`
- errors (HTTP status == code, body `{code,msg}`): 401 请先登录; 400 参数不合规; 409 上传请求号对应的内容不一致.
- idempotency: keyed by `request_id` (the `X-Upload-Request-ID` header of the upload route writes it; upload route is outside this group). iOS: `Core/IMExpandedService.swift:243` (also `Core/BusinessRuntimeConfiguration.swift:278`)
- SYNTHETIC: `GET …?request_id=<id>&source_sha256=<64 hex>` -> `{"code":200,"uploadProtocol":"original-upload-request-v1","uploadRequestId":"<id>","sourceSHA256":"<64 hex>","uploadState":"UPLOADED","url":"https://…/a.jpg","fileName":"a.jpg","reviewState":"APPROVED"}`

## G31

(G31 error envelope: `{code, msg, errorCode, businessCode}`; HTTP status via AjaxResult UNKNOWN. All routes: token required; no guest.)

### GET /api/free-explore/bundle/transfer/preview
- controller: `C/ApiBundleTransferG31Controller.java:28` (class mapping :18). params: `registrationId` Long req (query).
- success `data`: `{registrationId:number, eligible:boolean, ineligibleCode:string|null, channels:["IN_APP","SMS"], impact:["UNUSED_UNITS_MOVE_TO_RECEIVER","USED_AND_RESERVED_UNITS_STAY","ONE_TIME_CODE_SHOWN_ONCE"]}`
- errors: 401 LOGIN_REQUIRED. (ineligible is reported in data, not as an error: `BUNDLE_TRANSFER_NOT_ELIGIBLE` / `BUNDLE_TRANSFER_DUPLICATE_PENDING`.)
- idempotency: n/a. iOS: `App/BundleTransferClient`… exact: `Core/BundleTransferClient.swift:67`
- SYNTHETIC: `?registrationId=11` -> `{"code":200,"data":{"registrationId":11,"eligible":true,"ineligibleCode":null,"channels":["IN_APP","SMS"],"impact":["UNUSED_UNITS_MOVE_TO_RECEIVER","USED_AND_RESERVED_UNITS_STAY","ONE_TIME_CODE_SHOWN_ONCE"]}}`

### POST /api/free-explore/bundle/transfer
- controller: `C/ApiBundleTransferG31Controller.java:33`. JSON `SendBody`: `registrationId` Long req, `receiverPhone` string req (`+E.164` or CN `1[3-9]xxxxxxxxx`), `channel` string req (`IN_APP|SMS`), `idempotencyKey` string req (1–64, `[A-Za-z0-9_-]`).
- success `data`: `{id:number, registrationId:number, status:string, expiresAt:number(epoch ms), claimCode?:string (only on the first, creating call)}`
- errors: 400 INVALID_REQUEST; 401 LOGIN_REQUIRED; 409 IDEMPOTENCY_KEY_REUSED, BUNDLE_TRANSFER_NOT_ELIGIBLE, BUNDLE_TRANSFER_DUPLICATE_PENDING (other 409 codes thrown by the ineligible branch: only these two values are defined in code; BUNDLE_TRANSFER_SELF is declared, use not verified).
- idempotency: body `idempotencyKey`, scoped (sender, key), fingerprint of registration/phone/channel. iOS: `Core/BundleTransferClient.swift:101`
- SYNTHETIC: `{"registrationId":11,"receiverPhone":"13800000000","channel":"SMS","idempotencyKey":"k-0001"}` -> `{"code":200,"data":{"id":1,"registrationId":11,"status":"PENDING","expiresAt":1790000000000,"claimCode":"ABCDEFGHJK"}}` (status literal "PENDING" is from SQL; other statuses REVOKED, EXPIRED)

### GET /api/free-explore/bundle/transfer
- controller: `C/ApiBundleTransferG31Controller.java:38`. `registrationId` Long req.
- success `data`: array (<=50, id DESC) of `{id, registrationId, status, expiresAt}` (no claimCode). errors: 401. iOS: `Core/BundleTransferClient.swift:89`
- SYNTHETIC: -> `{"code":200,"data":[{"id":1,"registrationId":11,"status":"PENDING","expiresAt":1790000000000}]}`

### GET /api/free-explore/bundle/transfer/receipt
- controller: `C/ApiBundleTransferG31Controller.java:43`. `idempotencyKey` string req.
- success `data`: `{idempotencyKey, receipt:"FOUND"|"NOT_FOUND", transfer:{id,registrationId,status,expiresAt}|null}`. errors: 400 INVALID_REQUEST; 401. iOS: `Core/BundleTransferClient.swift:75`
- SYNTHETIC: `?idempotencyKey=k-0001` -> `{"code":200,"data":{"idempotencyKey":"k-0001","receipt":"NOT_FOUND","transfer":null}}`

### POST /api/free-explore/bundle/transfer/{id}/revoke
- controller: `C/ApiBundleTransferG31Controller.java:48`. path `id` Long req; body not read (iOS sends `{}`).
- success `data`: `{id, registrationId, status:"REVOKED", expiresAt}`. errors: 401; 404 BUNDLE_TRANSFER_NOT_FOUND; 409 BUNDLE_TRANSFER_NOT_ELIGIBLE. Idempotent: revoking an already-REVOKED transfer returns it.
- iOS: `Core/BundleTransferClient.swift:114`
- SYNTHETIC: `POST …/transfer/1/revoke {}` -> `{"code":200,"data":{"id":1,"registrationId":11,"status":"REVOKED","expiresAt":1790000000000}}`

### POST /api/free-explore/bundle/voucher/appeal
- controller: `C/ApiBundleTransferG31Controller.java:53`. JSON `AppealBody`: `registrationId` Long req, `unitId` Long req, `reasonCode` string req (`MERCHANT_FORGOT_SCAN|OTHER`), `note` string opt (limit MAX_NOTE, value UNKNOWN unread), `evidenceRefs` string[] opt (distinct, each 1–128 printable ASCII, count<=MAX_EVIDENCE unread), `idempotencyKey` string req.
- success `data` (wire): `{id, registrationId, unitId, holderMemberId, reasonCode, status, applyState, idempotencyKey, decisionReason, version}` (types: numbers for id/registrationId/unitId/holderMemberId/version; others string/UNKNOWN nullable). errors: 400 INVALID_REQUEST; 401; 404 BUNDLE_UNIT_NOT_FOUND; 409 IDEMPOTENCY_KEY_REUSED, BUNDLE_APPEAL_DUPLICATE_OPEN.
- idempotency: body `idempotencyKey`. iOS: `Core/BundleAppealClient.swift:118`
- SYNTHETIC: `{"registrationId":11,"unitId":3,"reasonCode":"OTHER","note":"x","evidenceRefs":[],"idempotencyKey":"a-0001"}` -> `{"code":200,"data":{"id":1,"registrationId":11,"unitId":3,"holderMemberId":5,"reasonCode":"OTHER","status":"<UNKNOWN>","applyState":"<UNKNOWN>","idempotencyKey":"a-0001","decisionReason":null,"version":0}}`

### GET /api/free-explore/bundle/voucher/appeal/receipt
- controller: `C/ApiBundleTransferG31Controller.java:58`. `idempotencyKey` req. success `data`: `{idempotencyKey, receipt:"FOUND"|"NOT_FOUND", appeal:{wire above}|null}`. errors 400 INVALID_REQUEST; 401. iOS: `Core/BundleAppealClient.swift:130`
- SYNTHETIC: -> `{"code":200,"data":{"idempotencyKey":"a-0001","receipt":"NOT_FOUND","appeal":null}}`

### GET /api/free-explore/bundle/voucher/appeal
- controller: `C/ApiBundleTransferG31Controller.java:63`. `registrationId` Long req. success `data`: `{items:[appeal wire…]}` (<=50). errors 401. iOS: `Core/BundleAppealClient.swift:144`
- SYNTHETIC: -> `{"code":200,"data":{"items":[]}}`

### GET /api/guilds/{kind}/{guildId}/channels
- controller: `C/ApiGuildChannelG31Controller.java:21` (class mapping :13). path `kind` int, `guildId` long; query `include_hidden` string default "0", `with_unread` string default "0" — both accepted but IGNORED by the code.
- success `data`: `{guild_kind:int, guild_id:string, groups:[{category:{id:string,name:string,kind:0}, channels:[…]}], ungrouped:[…]}`; channel item field names: UNKNOWN (leaf mapping not read).
- errors: 401 LOGIN_REQUIRED; 403 NOT_GUILD_MEMBER; 404 GUILD_KIND_UNSUPPORTED. iOS: `Core/NativeChannelManagementService.swift:265`
- SYNTHETIC: `GET /api/guilds/1/42/channels?include_hidden=0&with_unread=1` -> `{"code":200,"data":{"guild_kind":1,"guild_id":"42","groups":[{"category":{"id":"7","name":"Text","kind":0},"channels":[]}],"ungrouped":[]}}`

### GET /api/guilds/{kind}/{guildId}/channels/manage
- controller: `C/ApiGuildChannelG31Controller.java:28`. path as above. success `data`: array of `{id:string, guild_kind:int, guild_id:string, parent_id:string, kind:int, name, [topic], position:int, is_default:int, status:int, version:string, perm_version:string, visibility:int, slowmode_sec:int, [archive_reason], [purge_at:ISO], recoverable:boolean, my_permissions_list, member_count_capped:0}` (conditional fields per code lines 93,104,108).
- errors: 401; 403 MISSING_PERMISSION / NOT_GUILD_MEMBER; 404 GUILD_KIND_UNSUPPORTED. iOS: `Core/NativeChannelManagementService.swift:272`
- SYNTHETIC: -> `{"code":200,"data":[{"id":"9","guild_kind":1,"guild_id":"42","parent_id":"7","kind":1,"name":"general","position":0,"is_default":1,"status":1,"version":"1","perm_version":"1","visibility":1,"slowmode_sec":0,"recoverable":false,"my_permissions_list":["MANAGE_CHANNEL"],"member_count_capped":0}]}`

### GET /api/im/pins
- controller: `C/ApiImPinG31Controller.java:24` (class mapping :16). query `conversation_id` string req (`[1-9][0-9]{0,17}`).
- success `data`: `{list:[{id:string,message_id:string,conversation_id:string,summary,sort_no:int}], total:int, limit:20}`. errors: 400 INVALID_REQUEST; 401; 403 MISSING_PERMISSION; 404 CHANNEL_NOT_FOUND / CONVERSATION_NOT_FOUND (read-access error codes beyond these UNKNOWN). iOS: `Core/NativeChannelMessageService.swift:76`
- SYNTHETIC: `?conversation_id=100` -> `{"code":200,"data":{"list":[{"id":"1","message_id":"55","conversation_id":"100","summary":"hi","sort_no":1}],"total":1,"limit":20}}`

### POST /api/im/pins/sort
- controller: `C/ApiImPinG31Controller.java:29`. JSON: `conversation_id` string req, `request_id` string req (16–64, `[A-Za-z0-9_-]`), `ordered_pin_ids` string[] req (1–20, distinct, `[1-9][0-9]{0,17}`).
- success `data`: `{conversation_id:string, updated:int, sort_nos:{<pinId>:int}}`. errors: 400 INVALID_REQUEST; 401; 403 MISSING_PERMISSION; 404 CHANNEL_NOT_FOUND/CONVERSATION_NOT_FOUND; 409 IDEMPOTENCY_KEY_REUSED, PIN_SET_CHANGED, REQUEST_IN_PROGRESS.
- idempotency: `request_id` (member, request_id). iOS: `Core/NativeChannelMessageService.swift:58`
- SYNTHETIC: `{"conversation_id":"100","request_id":"req-0123456789abcdef","ordered_pin_ids":["2","1"]}` -> `{"code":200,"data":{"conversation_id":"100","updated":2,"sort_nos":{"2":1,"1":2}}}`

### GET /api/mod-settlement/mine
- controller: `C/ApiModSettlementG31Controller.java:20` (class mapping :12). query `limit` Integer opt (1–100, default 100), `before` string opt (`ms_[0-9a-f]{64}`).
- success `data`: array of `{id, orderKey, currency, state, creatorId:number, amount:number, retainedAmount:number, version:number, frozen:boolean, [freezeReason], draftDigest, [intentKey], [providerTransferId], createdAt:ISO, updatedAt:ISO}`. errors: 400 INVALID_REQUEST; 401. iOS: `Core/ModSettlementService.swift:129`
- SYNTHETIC: `?limit=20` -> `{"code":200,"data":[{"id":"ms_<64 hex>","orderKey":"MOD<29 hex>","currency":"CNY","state":"<UNKNOWN>","creatorId":5,"amount":1000,"retainedAmount":0,"version":1,"frozen":false,"draftDigest":"<hex>","createdAt":"2026-11-08T00:00:00Z","updatedAt":"2026-11-08T00:00:00Z"}]}` (id type/format: UNKNOWN, `r.get("id")`; ISO format per G31Util.iso)

### GET /api/mod-settlement/mine/income
- controller: `C/ApiModSettlementG31Controller.java:26`. query `before` opt (`MOD[0-9a-f]{29}`).
- success `data`: `{schema:"mod-creator-income-page-v1", creatorId:number, facts:[{source, orderKey, modReleaseId, currency, creatorId, creatorAmount, refundedAmount, chargebackAmount, revision, paidAt:ISO, disputed:boolean}], nextCursor?:string (last orderKey; present only when more, page size 50)}`. errors 400 INVALID_REQUEST; 401. iOS: `Core/ModSettlementService.swift:132`
- SYNTHETIC: -> `{"code":200,"data":{"schema":"mod-creator-income-page-v1","creatorId":5,"facts":[]}}`

### POST /api/onboarding/get
- controller: `C/ApiOnboardingG31Controller.java:23` (class mapping :15). JSON `Body`: `guild_kind` number|numeric string req, `guild_id` number|numeric string req.
- success `data`: `{viewer_id:string, guild_id:string, guild_kind:int, configuration_hash:string, completion_policy, answer_state:"CURRENT"|"SOURCE_CHANGED"|"NONE", submitted:0|1, can_skip:true, next:"welcome_screen", prompts:[{prompt_id, title, single_select, required, enabled:true, options:[{option_id,label,description,emoji,channel_ids,role_ids}], selected_option_ids, previous_answer_exists, answer_source_current, answer_configuration_hash}]}` (prompt/option element types beyond names: UNKNOWN; `completion_policy` type UNKNOWN).
- errors: 400 INVALID_REQUEST (空间参数不合法); 401; 403 NOT_GUILD_MEMBER; 404 GUILD_KIND_UNSUPPORTED; 409 ONBOARDING_NOT_CONFIGURED. iOS: `Core/NativeChannelOnboarding.swift:14`
- SYNTHETIC: `{"guild_kind":1,"guild_id":"42"}` -> `{"code":200,"data":{"viewer_id":"5","guild_id":"42","guild_kind":1,"configuration_hash":"<64 hex>","completion_policy":"<UNKNOWN>","answer_state":"NONE","submitted":0,"can_skip":true,"next":"welcome_screen","prompts":[]}}`

### POST /api/onboarding/submit
- controller: `C/ApiOnboardingG31Controller.java:28`. JSON: `guild_kind`, `guild_id`, `request_id` string req (lower UUID), `configuration_hash` string req (64 hex lower), `answers` array req (1–3) of `{prompt_id:string "[1-9][0-9]{0,17}", option_ids:string[] (1–8, distinct)}`.
- success `data` (receipt `result`, from `OnboardingG31Service.result`): `{request_id, state:"APPLIED", viewer_id, guild_id, guild_kind, submitted:1, configuration_hash, effects_state:"NONE", granted_role_ids:[], joined_channel_ids:[], answers:[{prompt_id, option_ids}]}`. (Whether `submit` returns this `result` or the outer receipt object: UNKNOWN, return statement not read.)
- errors: 400 INVALID_REQUEST; 401; 403 NOT_GUILD_MEMBER; 409 IDEMPOTENCY_KEY_REUSED, ONBOARDING_CONFIGURATION_CHANGED, ONBOARDING_POLICY_UNSUPPORTED, ONBOARDING_EFFECTS_UNSUPPORTED, REQUEST_IN_PROGRESS, ONBOARDING_NOT_CONFIGURED; 422 ONBOARDING_ANSWER_INCOMPLETE, ONBOARDING_OPTION_INVALID.
- idempotency: `request_id` (member, request_id). iOS: `Core/NativeChannelOnboarding.swift:14`
- SYNTHETIC: `{"guild_kind":1,"guild_id":"42","request_id":"0b8f3c2e-1111-4222-8333-444455556666","configuration_hash":"<64 hex>","answers":[{"prompt_id":"1","option_ids":["2"]}]}` -> `{"code":200,"data":{"request_id":"0b8f3c2e-…","state":"APPLIED","viewer_id":"5","guild_id":"42","guild_kind":1,"submitted":1,"configuration_hash":"<64 hex>","effects_state":"NONE","granted_role_ids":[],"joined_channel_ids":[],"answers":[{"prompt_id":"1","option_ids":["2"]}]}}`

## G32

### GET /api/compliance/usage-records
- controller: `C/ApiComplianceUsageG32Controller.java:17` (class mapping :13). auth: token (controller 401 `请先登录`). query `beforeId` string opt (`[1-9][0-9]{0,17}`).
- success `data`: `{…envelope: accountId:number, scene:"app_launch", readOnly:true, nativeMarketBinding:"UNPROVEN", items:[{id:number, docType, docVersion, eventType, requestId, occurredAt:number|null (epoch ms)}], nextBeforeId:number|null}` (page size 50; some record fields at lines 82 not shown — UNKNOWN).
- errors: 401 请先登录; 400 beforeId 不合法. iOS: `Core/UsageConsentRead.swift:155`
- SYNTHETIC: -> `{"code":200,"data":{"accountId":5,"scene":"app_launch","readOnly":true,"nativeMarketBinding":"UNPROVEN","items":[{"id":3,"docType":"privacy","docVersion":"1","eventType":"accept","requestId":"r1","occurredAt":1790000000000}],"nextBeforeId":null}}` (docType/eventType values SYNTHETIC)

### GET /api/compliance/usage-records/request
- controller: `C/ApiComplianceUsageG32Controller.java:29`. token. query `requestId` string req (`^[A-Za-z0-9:._-]{1,64}$`).
- success `data`: `{…envelope, record:{id,docType,docVersion,eventType,requestId,occurredAt}, latestRecordId:number|null, document:{docType, version, availability:"MISSING"}}`. errors: 401; 400 requestId 不合法; 404 记录不存在. iOS: `Core/UsageConsentRead.swift:160`
- SYNTHETIC: `?requestId=r1` -> `{"code":200,"data":{"accountId":5,"scene":"app_launch","readOnly":true,"nativeMarketBinding":"UNPROVEN","record":{...},"latestRecordId":3,"document":{"docType":"privacy","version":"1","availability":"MISSING"}}}`

### POST /api/growth/leaderboard/anonymous
- controller: `C/ApiGrowthAnonymousG32Controller.java:20` (class mapping :16). auth: token (controller 401 on no login). encoding: urlencoded FORM (model attribute `LeaderboardQueryDTO`): `metric` string req (`point|exp`), `period` string req (`total|week`), `limit` Integer req (1–50).
- success `data`: `{metric, period, list:[{rank:int, score, rankPercentage, self:boolean, [nickname:"匿名玩家" only when not self]}], me:{rank, score, rankPercentage, self:true}}` (score/rankPercentage types from LeaderboardItemVO, UNKNOWN here).
- errors: 401 请先登录; 400 `limit 须为 1..50` / `metric/period 不合法`. iOS: `Core/GrowthCenterService.swift:22`
- SYNTHETIC: `metric=point&period=week&limit=10` -> `{"code":200,"data":{"metric":"point","period":"week","list":[{"rank":1,"score":100,"rankPercentage":99.0,"self":true}],"me":{"rank":1,"score":100,"rankPercentage":99.0,"self":true}}}`

### POST /api/space/leave
- controller: `C/ApiSpaceG32Controller.java:18` (class mapping :14). token. JSON: `guild_kind` positive long req (only 1 = club supported), `guild_id` positive long req, `request_id` string req (`^[A-Za-z0-9:._-]{1,64}$`); numbers or numeric strings accepted.
- success `data`: `{left:true, was_member:boolean, guild_kind:int, guild_id:number, request_id}`. errors: 401; 400 参数不合法 / 暂不支持的 guild_kind; 403 主理人不能直接退出…; 404 空间不存在; 409 请求标识已用于其他操作; 500 回执不可读/回执写入失败.
- idempotency: `request_id`. iOS: `Core/ChannelAdmissionGovernanceClient.swift:84`
- SYNTHETIC: `{"guild_kind":1,"guild_id":42,"request_id":"req-1"}` -> `{"code":200,"data":{"left":true,"was_member":true,"guild_kind":1,"guild_id":42,"request_id":"req-1"}}`

### POST /api/space/join-pause
- controller: `C/ApiSpaceG32Controller.java:33`. token. JSON: `guild_kind`, `guild_id`, `request_id` (as above), `paused` boolean req, `paused_until` string opt (future datetime; accepted format UNKNOWN), `reason` string (required, <=120 chars per service).
- success `data`: `{join_paused:boolean, paused_until:ISO local datetime|null, reason, guild_kind, guild_id, request_id}`. errors: 401; 400 参数不合法 / 原因必填且不超过120字 / 暂停截止时间…; 403 无权限; 404 空间不存在; 409; 500.
- idempotency: `request_id`. iOS: `Core/ChannelAdmissionGovernanceClient.swift:97`
- SYNTHETIC: `{"guild_kind":1,"guild_id":42,"request_id":"req-2","paused":true,"paused_until":"2026-12-01T00:00:00","reason":"full"}` -> `{"code":200,"data":{"join_paused":true,"paused_until":"2026-12-01T00:00:00","reason":"full","guild_kind":1,"guild_id":42,"request_id":"req-2"}}`

### POST /api/ugc/block
- controller: `C/ApiUgcG32Controller.java:18` (class mapping :14). token. JSON: `blocked_member_id` positive long req, `request_id` req, `blocked` boolean opt (default true).
- success `data`: `{blocked_member_id:number, blocked:boolean, request_id}`. errors: 401; 400 参数不合法 / 不能屏蔽自己; 404 用户不存在; 409 请求标识已用于其他屏蔽 / 请求标识冲突.
- idempotency: `request_id`. iOS: endpoint string default only, `App/PublishTopicAndCommentModerationSectionView.swift:81` (no live call site found).
- SYNTHETIC: `{"blocked_member_id":9,"request_id":"b-1"}` -> `{"code":200,"data":{"blocked_member_id":9,"blocked":true,"request_id":"b-1"}}`

### POST /api/ugc/report
- controller: `C/ApiUgcG32Controller.java:35`. token. JSON: `target_type` req (`MEMBER|TOPIC|COMMENT|POST|CLUB|MESSAGE`), `target_id` positive long req, `reason_code` req (`SPAM|ABUSE|PORN|ILLEGAL|PRIVACY|FRAUD|MINOR|OTHER`), `detail` string opt (<=500), `request_id` req.
- success `data`: `{report_id:number, status:"OPEN", request_id}`. errors: 401; 400 参数不合法; 409 请求标识已用于其他举报 / 请求标识冲突.
- idempotency: `request_id`. iOS caller: NONE (iOS default report endpoint is `api/community-trust/reports/submit`, `App/PublishTopicAndCommentModerationSectionView.swift:80`).
- SYNTHETIC: `{"target_type":"TOPIC","target_id":3,"reason_code":"SPAM","request_id":"r-1"}` -> `{"code":200,"data":{"report_id":1,"status":"OPEN","request_id":"r-1"}}`

### GET /api/user/follow-list
- controller: `C/ApiUserFollowListG32Controller.java:17` (class mapping :13). token (controller 401 on no login). query: `kind` req (`following|followers`), `cursor` string default "0" (`0|[1-9][0-9]{0,17}`), `limit` string default "50" (1–50).
- success `data`: `{owner_id:number, kind, rows:[{id:number, nickname:string, avatar:string|null, isFollow:boolean}], has_more:boolean, next_cursor:number|null}` (rows may carry more fields: lines 34–38 only). errors: 401; 400 kind 不合法 / 分页参数不合法 / limit 最大 50. iOS: `Core/ProfileFollowListService.swift:96`
- SYNTHETIC: `?kind=following&cursor=0&limit=20` -> `{"code":200,"data":{"owner_id":5,"kind":"following","rows":[{"id":9,"nickname":"a","avatar":null,"isFollow":true}],"has_more":false,"next_cursor":null}}`

### POST /api/user/sms/send
- controller: `C/ApiUserSmsG32Controller.java:24` (class mapping :20). auth: INTENDED pre-login (guest) but class has no `@Anonymous` and SecurityConfig has no matcher for the path (controller comment says permitAll is missing), so as built it requires a token; UNKNOWN whether an `@Anonymous` scan or other filter changes this. RateLimiter 20/60s per IP.
- encoding: form/query: `phone` string (required-ness enforced inside `SmsVerificationService.send`, rules UNKNOWN here).
- success: `{code:200,msg:<result.getMessage()>}` (`success(String)`); errors: `error(<message>)` code 500 default (AjaxResult.error(String) default code assumed; UNKNOWN). idempotency: none; rate limits in SmsVerificationService.
- iOS caller: constant only `Core/RegionalEndpointAllowlistAudit.swift:12`, `App/RegionalEndpointAllowlistSectionView.swift:156`; live call site NONE found.
- SYNTHETIC: `phone=13800000000` -> `{"code":200,"msg":"<message>"}`

# Part C — G33, G34, G35, G36

Conventions (all rows): controllers are under `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/` (abbrev `C/`). Envelope is RuoYi `AjaxResult`: success `{"code":200,"msg":"操作成功","data":<shape>}` (`AjaxResult.java:78`); errors are `{"code":<n>,"msg":"<text>"[, "errorCode":"<X>"]}`; the controllers never set an HTTP status, so the business code is in the body (HTTP status of the error response = UNKNOWN from controller code; the report says iOS reads body code). **Auth for every route below:** `SecurityConfig.java:117-163` has no permitAll entry for any of these paths and ends in `.anyRequest().authenticated()` (`:~158`), and none of these controllers uses `@Anonymous` → token required, guests NOT allowed. Member id is taken from the token (`BaseController.getAppUserId()`), never from the request. No custom header is read by any controller; token header name = UNKNOWN here (JwtAuthenticationTokenFilter not read). iOS caller refs are in `/home/user/chengyin-app` @ origin/wip/wave5-build. All examples are SYNTHETIC. "static contract" — not run against a live server.

---
## G33 (ApiImG33Controller, `@RequestMapping("/api/im")` C/ApiImG33Controller.java:23; service `ImNotifyG33ServiceImpl`)
Error mapping (`ApiImG33Controller.java:98-119`): `ImG33Exception` → `{code,msg,errorCode}`; `ServiceException` → `{code,msg}`; other → `{"code":500,"msg":"操作失败，请稍后重试"}`. Common: `UNAUTHORIZED` 401 if member id ≤0 (`:579`).
G33 reported BLOCKED (no route): `PUT /api/im/members/{memberId}/roles`.

### GET /api/im/device/attempts
- Controller: C/ApiImG33Controller.java:29 · Auth: token · Encoding: query string (no body)
- Params: `installation_id` String, required in practice (regex `^[0-9A-Za-z._:-]{1,64}$`, else 400 INVALID_INSTALLATION); `before` String optional digits cursor (default "0", else 400 INVALID_CURSOR); `read_attempts` String optional comma list of 1..50 unique lowercase UUIDs (switches to reconciliation mode; else 400 INVALID_ATTEMPT).
- Success (page mode): `{source:"original-im-push-attempts-v1", installation_id:str, items:[{id:str, attempt_id, source_kind, state, provider_status, reason, badge_snapshot?{generation:long,count:long,network_fenced:bool}}], next_before:str("0" when no more), delivery_proven:false}`. Types of `attempt_id/source_kind/state/provider_status/reason` come from mapper row = UNKNOWN (not read). Reconciliation mode: `{source:"original-im-push-read-reconciliation-v1", installation_id, read_attempts:[uuid], delivery_proven:false}`.
- Errors: 400 INVALID_INSTALLATION / INVALID_CURSOR / INVALID_ATTEMPT; 401 UNAUTHORIZED.
- Idempotency/headers: read-only; none.
- iOS caller: Core/NativePushAttemptRead.swift:67 (page, sends `installation_id`,`before`) and :103 (second call site, params there not read = UNKNOWN whether read_attempts).
- SYNTHETIC: req `GET /api/im/device/attempts?installation_id=ios-abc123&before=0` → `{"code":200,"msg":"操作成功","data":{"source":"original-im-push-attempts-v1","installation_id":"ios-abc123","items":[],"next_before":"0","delivery_proven":false}}`

### GET /api/im/notify-log
- C/ApiImG33Controller.java:37 · token · query
- Params: `limit` String optional int 1..50 (default 20; else 400 INVALID_LIMIT); `event` String optional `^[A-Z][A-Z0-9_]{0,39}$` (400 INVALID_EVENT); `cursor` String optional `^[0-9A-Za-z_-]{1,1024}$`, digits only effective (400 INVALID_CURSOR).
- Success: `{source:"original-notification-results-v1", member_id:str, list:[{id:"apns:<attempt_id>", event, channel:"apns", ok:bool, reason, biz_key, create_time, provider_state, result_source:"original-apns-attempt", source_conflict:false}], next_cursor:str|null, has_more:bool, sources:{wx:false,apns:true,inapp:false}, delivery_proven:false}`.
- Errors: 400 INVALID_LIMIT/INVALID_EVENT/INVALID_CURSOR; 401.
- Idempotency: read-only.
- iOS caller: Core/NativeChannelNotificationService.swift:131
- SYNTHETIC: `GET /api/im/notify-log?limit=20` → `{"code":200,"msg":"操作成功","data":{"source":"original-notification-results-v1","member_id":"1001","list":[],"next_cursor":null,"has_more":false,"sources":{"wx":false,"apns":true,"inapp":false},"delivery_proven":false}}`

### GET /api/im/notify-pref
- C/ApiImG33Controller.java:45 · token · query
- Params: `scope_type` String optional ("1"|"2"|"4", else 400 INVALID_SCOPE); `scope_id` String optional positive long (400 INVALID_SCOPE). If either is present, returns that scope only; absent → all saved prefs.
- Success: `{list:[PrefView], defaults:PrefView(scope 4), server_time:ISO-instant}`; PrefView = `{scope_type:int, scope_id:str, level:int, effective_level:int, effective:{level,muted,permanent_muted,quiet,suppress_broadcast,suppress_team_status,show_preview}, permanent_muted:bool, muted_until:ISO|null, quiet_start, quiet_end, quiet_tz, suppress_broadcast:bool, suppress_team_status:bool, show_preview:bool|null, version:long}`.
- Errors: 400 INVALID_SCOPE; 403 SCOPE_FORBIDDEN (not owner of scope / not club member / not conv member); 401.
- iOS caller: Core/NativeChannelNotificationService.swift:124
- SYNTHETIC: `GET /api/im/notify-pref?scope_type=4&scope_id=1001` → `{"code":200,"msg":"操作成功","data":{"list":[{"scope_type":4,"scope_id":"1001","level":1,"effective_level":1,"effective":{"level":1,"muted":false,"permanent_muted":false,"quiet":false,"suppress_broadcast":false,"suppress_team_status":false,"show_preview":true},"permanent_muted":false,"muted_until":null,"quiet_start":null,"quiet_end":null,"quiet_tz":null,"suppress_broadcast":false,"suppress_team_status":false,"show_preview":null,"version":0}],"defaults":{"...":"same shape as list item"},"server_time":"2026-11-08T00:00:00Z"}}`

### POST /api/im/notify-pref
- C/ApiImG33Controller.java:52 · token · **JSON** (`@RequestBody Map`)
- Body: `request_id` String required (`^[0-9A-Za-z_-]{16,96}$`); `scope_type` ("1"|"2"|"4", stringified in code via String.valueOf); `scope_id` **String** required positive long (a JSON number is rejected → INVALID_SCOPE); `level` int 0..3 required; `version` long ≥0 required (CAS); optional `muted_until` ISO-8601 instant string (≤30 days ahead), `quiet_start`/`quiet_end` "HH:mm" + `quiet_tz` IANA (all three or none; start≠end), `suppress_broadcast` bool, `suppress_team_status` bool, `show_preview` bool. Unknown keys → 400 UNKNOWN_FIELD; `permanent_muted` → 400 READ_ONLY_FIELD. Scope 4 rejects muted_until/suppress_* (INVALID_ACCOUNT_DEFAULT).
- Success: `{request_id, status:"APPLIED", operation:"PREFERENCE", scope_type:int, scope_id:str, result_redacted:false, must_refresh_state:true, outcome:"APPLIED", result:{version:long(new), permanent_muted:bool, muted_until:str|null}}`.
- Errors: 400 INVALID_BODY / READ_ONLY_FIELD / UNKNOWN_FIELD / INVALID_REQUEST_ID / INVALID_SCOPE / INVALID_LEVEL / INVALID_VERSION / INVALID_MUTED_UNTIL / INVALID_QUIET_HOURS / INVALID_ACCOUNT_DEFAULT; 403 SCOPE_FORBIDDEN; 409 REQUEST_ID_CONFLICT (same id, different content), NOTIFY_PREF_VERSION_CONFLICT.
- Idempotency: `request_id` in body, ledger (NOTIFY, member, request_id); same id+same hash replays stored receipt. No headers.
- iOS caller: Core/NativeChannelNotificationService.swift:147
- SYNTHETIC: req `{"request_id":"a1b2c3d4e5f6g7h8i9","scope_type":"4","scope_id":"1001","level":1,"version":0}` → `{"code":200,"msg":"操作成功","data":{"request_id":"a1b2c3d4e5f6g7h8i9","status":"APPLIED","operation":"PREFERENCE","scope_type":4,"scope_id":"1001","result_redacted":false,"must_refresh_state":true,"outcome":"APPLIED","result":{"version":1,"permanent_muted":false,"muted_until":null}}}`

### GET /api/im/notification-requests/{requestId}
- C/ApiImG33Controller.java:58 · token · path var
- Params: `requestId` String required `^[0-9A-Za-z_-]{16,96}$` (400 INVALID_REQUEST_ID).
- Success: stored receipt JSON (same shape as notify-pref POST response) or, if none, `{request_id, status:"NOT_FOUND", outcome:"UNKNOWN"}` (note: HTTP/body code 200 for NOT_FOUND). Only PREFERENCE writes are recorded (report).
- Errors: 400 INVALID_REQUEST_ID; 401. Idempotency: read-only.
- iOS caller: Core/NativeChannelNotificationService.swift:156 (path built `"/api/im/notification-requests/" + requestID`)
- SYNTHETIC: `GET /api/im/notification-requests/zzzzzzzzzzzzzzzz` → `{"code":200,"msg":"操作成功","data":{"request_id":"zzzzzzzzzzzzzzzz","status":"NOT_FOUND","outcome":"UNKNOWN"}}`

### GET /api/im/mute-state
- C/ApiImG33Controller.java:64 · token · query
- Params: `conversation_id` String required positive long (invalid → error thrown by `conversationOf`, errorCode UNKNOWN: helper body not read; likely INVALID_CONVERSATION per report).
- Success: `{source:"original-ordinary-im-mute-state-v1", owner_member_id:str, conversation_id:str, conversation_type:int(1..3), muted:bool}`.
- Errors: 400 INVALID_CONVERSATION (per report), NOT_ORDINARY_CONVERSATION (type not 1..3); 403 NOT_A_MEMBER; 401.
- iOS caller: Core/IMExpandedService.swift:339
- SYNTHETIC: `GET /api/im/mute-state?conversation_id=55` → `{"code":200,"msg":"操作成功","data":{"source":"original-ordinary-im-mute-state-v1","owner_member_id":"1001","conversation_id":"55","conversation_type":1,"muted":false}}`

### GET /api/im/mute-receipt
- C/ApiImG33Controller.java:70 · token · query
- Params: `conversation_id` String required; `muted` String required "0"|"1" (400 INVALID_MUTED); `request_id` String required lowercase UUID (400 INVALID_REQUEST_ID).
- Success: `{source:"original-ordinary-im-mute-receipt-v1", owner_member_id:str, conversation_id:str, request_id, outcome:"APPLIED"|"NOT_FOUND", requested_muted:bool}`. Per report outcome is always NOT_FOUND until `POST /api/im/mute` records the request_id (not done).
- Errors: 400 INVALID_MUTED/INVALID_REQUEST_ID/conversation invalid; 403 NOT_A_MEMBER; 409 REQUEST_ID_CONFLICT.
- Idempotency: request_id (query). iOS caller: Core/IMExpandedService.swift:332
- SYNTHETIC: `GET /api/im/mute-receipt?conversation_id=55&muted=1&request_id=123e4567-e89b-12d3-a456-426614174000` → `{"code":200,"msg":"操作成功","data":{"source":"original-ordinary-im-mute-receipt-v1","owner_member_id":"1001","conversation_id":"55","request_id":"123e4567-e89b-12d3-a456-426614174000","outcome":"NOT_FOUND","requested_muted":true}}`

### GET /api/im/interaction/request
- C/ApiImG33Controller.java:78 · token · query
- Params: `conversation_id` String required; `request_id` String required lowercase UUID.
- Success: `{source:"original-channel-chain-request-v1", actorId:str, conversationId:str, requestId, state:"NOT_FOUND"|<ledger state>, [operation, requestHash, resultRedacted:bool, result:obj (APPLIED & not redacted)]}`. Always NOT_FOUND until another group calls `recordChainRequest` (report).
- Errors: 400 INVALID_REQUEST_ID; 403 NOT_A_MEMBER; 409 REQUEST_ID_CONFLICT (id used for other conversation).
- iOS caller: Core/NativeChannelChain.swift:228
- SYNTHETIC: `GET /api/im/interaction/request?conversation_id=55&request_id=123e4567-e89b-12d3-a456-426614174000` → `{"code":200,"msg":"操作成功","data":{"source":"original-channel-chain-request-v1","actorId":"1001","conversationId":"55","requestId":"123e4567-e89b-12d3-a456-426614174000","state":"NOT_FOUND"}}`

### POST /api/im/pin
- C/ApiImG33Controller.java:85 · token · **JSON**
- Body: `request_id` String required (`^[0-9A-Za-z_-]{16,96}$`); `conversation_id` positive long (accepted type per `positiveLong(Object)`: not read, UNKNOWN whether number or string both OK); `message_id` same.
- Success: `{message_id:str, conversation_id:str, pinned:true, id:str, sort_no:int}`.
- Errors: 400 INVALID_BODY/INVALID_REQUEST_ID/INVALID_TARGET; 403 NOT_A_MEMBER, MISSING_PERMISSION (only if G31 pin guard present); 404 MESSAGE_NOT_FOUND; 409 REQUEST_ID_CONFLICT, CONVERSATION_UNAVAILABLE, MESSAGE_NOT_PINNABLE, PIN_LIMIT_REACHED (max 20).
- Idempotency: `request_id` in body (ledger PIN). iOS caller: Core/NativeChannelMessageService.swift:56 (also NativeChannelMessageFinalForward.swift:86)
- SYNTHETIC: req `{"request_id":"pin-0000000000001","conversation_id":55,"message_id":900}` → `{"code":200,"msg":"操作成功","data":{"message_id":"900","conversation_id":"55","pinned":true,"id":"7","sort_no":100}}`

### GET /api/im/poll/create-receipt
- C/ApiImG33Controller.java:91 · token · query
- Params: `conversation_id` String required; `client_poll_key` String required lowercase UUID (400 INVALID_CLIENT_POLL_KEY).
- Success: `{source:"original-poll-create-v1", conversation_id:str, creator_member_id:str, client_poll_key, state:"NOT_FOUND"|"UNKNOWN"|"APPLIED", [poll_id:str, message_id:str, request_hash, poll:<ImPoll bean, key casing unverified>]}`.
- Errors: 400 INVALID_CLIENT_POLL_KEY; 403 NOT_A_MEMBER.
- iOS caller: Core/GroupPollCoordinator.swift:79,89 (only `client.permits("api/im/poll/create-receipt")` gate sites; the actual request-building line = UNKNOWN)
- SYNTHETIC: `GET /api/im/poll/create-receipt?conversation_id=55&client_poll_key=123e4567-e89b-12d3-a456-426614174000` → `{"code":200,"msg":"操作成功","data":{"source":"original-poll-create-v1","conversation_id":"55","creator_member_id":"1001","client_poll_key":"123e4567-e89b-12d3-a456-426614174000","state":"NOT_FOUND"}}`

---
## G34 (ApiImReadG34Controller `@RequestMapping("/api/im")` C/ApiImReadG34Controller.java:27; ApiMapPublicLayersG34Controller C/…:31)
Error mapping (`ApiImReadG34Controller.java:104`): `ServiceException(msg,code)` → `{code, msg, errorCode}` with errorCode 400→INVALID_REQUEST, 401→UNAUTHORIZED, 403→FORBIDDEN, 404→NOT_FOUND, else REQUEST_REJECTED; other exceptions → `{"code":500,"msg":"操作失败，请稍后重试"}`. Invalid/missing numeric `conversation_id` is coerced to 0 by `Convert.toLong(x,0L)` → 404 "会话不存在". G34 BLOCKED/no route: `POST /api/im/unpin`, `POST /api/invite/revoke`, `/api/location-share/personal/*`, `/api/mod-commerce/*`.

### GET /api/im/read-state
- C/ApiImReadG34Controller.java:34 · token · query
- Params: `conversation_id` String required.
- Success: `{source:"original-ordinary-im-read-state-v1", owner_member_id:str, conversation_id:str, conversation_type:int, latest_visible_message_id:str("0" if none), last_read_message_id:str, unread:int}`.
- Errors: 401 请先登录; 404 会话不存在; 403 无权查看该会话; 400 该会话类型不支持 (group type 4 rejected).
- iOS caller: Core/IMExpandedService.swift:317
- SYNTHETIC: `GET /api/im/read-state?conversation_id=55` → `{"code":200,"msg":"操作成功","data":{"source":"original-ordinary-im-read-state-v1","owner_member_id":"1001","conversation_id":"55","conversation_type":1,"latest_visible_message_id":"900","last_read_message_id":"880","unread":2}}`

### GET /api/im/read-receipt
- C/ApiImReadG34Controller.java:46 · token · query
- Params: `conversation_id` String required; `read_to` String required non-negative long (400 已读位置无效); `request_id` String required lowercase UUID (400 请求编号无效).
- Success: `{source:"original-ordinary-im-read-receipt-v1", owner_member_id:str, conversation_id:str, request_id, requested_read_to:str, outcome:"APPLIED"|"NOT_FOUND"}` (derived from read cursor; never PENDING; request_id is not persisted).
- Errors: as read-state plus 400 above. Idempotency: request_id echoed only. iOS caller: Core/IMExpandedService.swift:310
- SYNTHETIC: `GET /api/im/read-receipt?conversation_id=55&read_to=900&request_id=123e4567-e89b-12d3-a456-426614174000` → `{"code":200,"msg":"操作成功","data":{"source":"original-ordinary-im-read-receipt-v1","owner_member_id":"1001","conversation_id":"55","request_id":"123e4567-e89b-12d3-a456-426614174000","requested_read_to":"900","outcome":"APPLIED"}}`

### POST /api/im/route-share-source
- C/ApiImReadG34Controller.java:60 · token (login required, `getAppUserId()` `:65`) · **form** (`@RequestParam`, urlencoded/multipart)
- Params: `topic_id` String required positive long (else 404 "该路线暂不可用").
- Success: `{source:"original-route-share-v1", topic_id:str, name:str(≤1000), publicly_shareable:true}`.
- Errors: 404 该路线暂不可用 (missing/unpublished/private/club-only — not distinguished); 401.
- iOS caller: Core/IMExpandedService.swift:162 (form request)
- SYNTHETIC: `POST topic_id=321` → `{"code":200,"msg":"操作成功","data":{"source":"original-route-share-v1","topic_id":"321","name":"西湖慢走","publicly_shareable":true}}`

### GET /api/im/unread-summary
- C/ApiImReadG34Controller.java:73 · token · no params
- Success: `{total:long, mention_count:0, has_mention:0, by_tab:{dm:long, sys:long, channel:long}}` (dm+sys+channel==total; `by_channel`/`badge_generation` omitted).
- Errors: 401. iOS caller: Core/NativeChannelNotificationService.swift:162
- SYNTHETIC: → `{"code":200,"msg":"操作成功","data":{"total":3,"mention_count":0,"has_mention":0,"by_tab":{"dm":2,"sys":1,"channel":0}}}`

### GET /api/im/search
- C/ApiImReadG34Controller.java:85 · token · query
- Params: `conversation_id` String required; `keyword` String required, trimmed 1..100 (400 搜索关键词无效); `from`,`to` String optional (epoch s/ms, ISO-8601, yyyy-MM-dd, yyyy-MM-dd HH:mm:ss; else 400 时间格式无效); `author_id` String optional positive long (400 作者无效); `cursor` optional non-neg long (400 游标无效); `limit` optional positive long, capped at 20 (400 条数无效).
- Success: `{list:[{id:str, conversationId:str, version:1, status:0, msgType:1, senderId:str, content, extraJson?, createTime}], has_more:bool, next_cursor:str|null, degraded:false, oldest_searchable_at:str "yyyy-MM-dd HH:mm:ss"}`. (camelCase item keys, snake_case envelope keys; `content`/`createTime` runtime types from mapper = UNKNOWN.)
- Errors: 400s above; 401/403/404 via scope. iOS caller: Core/NativeChannelMessageService.swift:84
- SYNTHETIC: `GET /api/im/search?conversation_id=55&keyword=hello&limit=20` → `{"code":200,"msg":"操作成功","data":{"list":[{"id":"900","conversationId":"55","version":1,"status":0,"msgType":1,"senderId":"1002","content":"hello","createTime":"2026-11-08 09:00:00"}],"has_more":false,"next_cursor":null,"degraded":false,"oldest_searchable_at":"2026-10-01 00:00:00"}}`

### POST /api/map/public-layers
- C/ApiMapPublicLayersG34Controller.java:39 · token (`getAppUserId()` `:44`) · **JSON** (body optional → null → 400 请求体缺失)
- Body: `datum` "GCJ-02" required; `minLat,maxLat,minLng,maxLng` number|numeric string required (|lat|≤90,|lng|≤180, min≤max, area (Δlat·Δlng) <1); `layers` array 1..5 unique strings from {roam_poi,store,activity,theme,story_node}; `limit` integer 1..50 required; `cursor` optional non-empty string ≤2048.
- Success: `{datum:"GCJ-02", layers:[{sourceType:str, status:"UNAVAILABLE", reason:"PUBLIC_READ_NOT_ENABLED", capabilities:{read:false}, items:[]}], aggregatedQueryEnabled:false}` (no data source wired).
- Errors: `{code:400,msg:<坐标系无效|limit 无效|范围无效|范围过大|图层无效|游标无效|请求体缺失>, errorCode:"INVALID_REQUEST"}`; other exception → `{code:500,msg:"操作失败，请稍后重试"}` (note: a `getAppUserId()` failure is caught by the generic catch → 500, not 401, at the controller level).
- Idempotency: none (read). iOS caller: Core/MapPublicLayerService.swift:172 (route recognizer; HTTP service at :224 — exact send line UNKNOWN)
- SYNTHETIC: req `{"datum":"GCJ-02","minLat":30.2,"maxLat":30.3,"minLng":120.1,"maxLng":120.2,"layers":["store"],"limit":20}` → `{"code":200,"msg":"操作成功","data":{"datum":"GCJ-02","layers":[{"sourceType":"store","status":"UNAVAILABLE","reason":"PUBLIC_READ_NOT_ENABLED","capabilities":{"read":false},"items":[]}],"aggregatedQueryEnabled":false}}`

---
## G35 (ApiPrivacyProgressG35Controller C/…:21, ApiSupportTicketG35Controller C/…:20, ApiRegistrationOriginalEventG35Controller C/…:26, ApiOfficialEventController)
BLOCKED/no route per report: `/api/mod-installation/`, `/api/mod-owned-report/licenses/`, `/api/mod-upgrade/`, `/api/pay/create`, `/api/team/original-request`. `/api/npc/chat/delete` is a label only (live call `POST /api/ai/npc/chat/data/delete`, other group). `/api/official/v2/events`: only the publish-check sub-route is attributed to G35.

### GET /api/privacy/progress
- C/ApiPrivacyProgressG35Controller.java:26 · token (own check → `{code:401,msg:"请先登录"}`) · no params (iOS sends optional `channel_id`; server ignores it, account-level only)
- Success: `{aggregate_scope, detail_scope, photo_scope, leaderboard_scope (strings), revision:long, updated_at:str|null, effective:{aggregate_scope,detail_scope}, applies_to:"CHANNEL_PROGRESS"}`; defaults CHANNEL/SELF/SELF/OUT, revision 0.
- Errors: 401. iOS caller: Core/NativeChannelProgressService.swift:58
- SYNTHETIC: → `{"code":200,"msg":"操作成功","data":{"aggregate_scope":"CHANNEL","detail_scope":"SELF","photo_scope":"SELF","leaderboard_scope":"OUT","revision":0,"updated_at":null,"effective":{"aggregate_scope":"CHANNEL","detail_scope":"SELF"},"applies_to":"CHANNEL_PROGRESS"}}`

### POST /api/privacy/progress
- C/ApiPrivacyProgressG35Controller.java:36 · token · **JSON**
- Body: `aggregate_scope` ∈ PUBLIC|CHANNEL|TEAM|SELF; `detail_scope` same set but PUBLIC forbidden; `photo_scope` ∈ SELF|TEAM|ADMIN; `leaderboard_scope` ∈ IN|OUT; `request_id` `^[A-Za-z0-9_-]{16,64}$`; `expected_revision` integer ≥0 (JSON non-float) OR `expected_updated_at` string — one required. All required.
- Success: view above plus `request_id, status:"APPLIED", replayed:bool, outcome_known:true, outcome_confirmed:true`.
- Errors (body code + errorCode): 400 PROGRESS_PRIVACY_INVALID (bad enum / missing expected version), 400 PROGRESS_DETAIL_PUBLIC_FORBIDDEN, 400 PROGRESS_REQUEST_ID_INVALID, 409 PROGRESS_PRIVACY_STALE, 409 REQUEST_ID_CONFLICT; 401 请先登录.
- Idempotency: `request_id` (fingerprint = sha256 of fields); same id+same content → `replayed:true`. iOS caller: Core/NativeChannelProgressService.swift:63
- SYNTHETIC: req `{"aggregate_scope":"CHANNEL","detail_scope":"SELF","photo_scope":"SELF","leaderboard_scope":"IN","request_id":"req-0000000000001","expected_revision":0}` → `{"code":200,"msg":"操作成功","data":{"aggregate_scope":"CHANNEL","detail_scope":"SELF","photo_scope":"SELF","leaderboard_scope":"IN","revision":1,"updated_at":"2026-11-08 10:00:00","effective":{"aggregate_scope":"CHANNEL","detail_scope":"SELF"},"applies_to":"CHANNEL_PROGRESS","request_id":"req-0000000000001","status":"APPLIED","replayed":false,"outcome_known":true,"outcome_confirmed":true}}`

### POST /api/support/tickets/list
- C/ApiSupportTicketG35Controller.java:27 · token (own 401) · **JSON** (body optional)
- Body: `cursor` integer ≥0 required (JSON Integer/Long only; missing/other → 400 参数不合法). Page size 30, descending.
- Success: `{list:[Ticket], has_more:bool, next_cursor:long}`; Ticket = `{ticket_no, requester_role, category, subject, status, version, [timezone, locale, sla_state, sla_first_due_at, sla_resolve_due_at, create_time, resolved_at, closed_at], [related_reference:{source,domain_type,resource_id:str,owner_type:"MEMBER",owner_member_id:str}]}` (nullable fields omitted; column types = UNKNOWN, tables empty until a writer exists).
- Errors: 401 请先登录; 400 参数不合法. iOS caller: Core/SupportTicketReadContracts.swift:103-108 (path/body built here, body at :111-118; transport send line UNKNOWN)
- SYNTHETIC: req `{"cursor":0}` → `{"code":200,"msg":"操作成功","data":{"list":[],"has_more":false,"next_cursor":0}}`

### POST /api/support/tickets/detail
- C/ApiSupportTicketG35Controller.java:41 · token · **JSON**
- Body: `ticket_no` string `^CS[A-Za-z0-9_-]{1,22}$` required; `cursor` integer ≥0 required (message page after this id, 50/page); `event_cursor` optional integer ≥0 — if present, `cursor` must be 0 and timeline is returned (50/page, before this id).
- Success: `{ticket:Ticket, messages:[{id:long,sender_type,content,content_type,create_time,attachments:[long]}], has_more, next_cursor:long, business_result:"NO_FINANCIAL_ACTION", [timeline:{resource_type:"CS_TICKET",ticket_no,audience:"MEMBER",source:"cs_ticket_event",events:[{id,event_type,actor_type,created_at,result_state,[historical_status,historical_sla_state,historical_version,message_id,reason,request_id(only actor MEMBER)]}],has_more,next_before:long}]}`.
- Errors: 400 参数不合法; 404 工单不存在 (missing or not owned); 401.
- iOS caller: Core/SupportTicketReadContracts.swift:103-110 (same as above)
- SYNTHETIC: req `{"ticket_no":"CS20261108001","cursor":0}` → `{"code":200,"msg":"操作成功","data":{"ticket":{"ticket_no":"CS20261108001","requester_role":"MEMBER","category":"ORDER","subject":"示例","status":"OPEN","version":1},"messages":[],"has_more":false,"next_cursor":0,"business_result":"NO_FINANCIAL_ACTION"}}`

### POST /api/registration/original-event
- C/ApiRegistrationOriginalEventG35Controller.java:33 · token (own check → 401) · **form** field `id` (comment says multipart/form)
- Params: `id` String required positive long (else `{code:500,msg:"报名id不合法"}` — plain `AjaxResult.error(msg)` = code 500).
- Success: array (up to 20) of rows from `RegistrationOriginalEventG35Mapper.selectOwnOrderEvents` — field names UNKNOWN (mapper XML not read); currently empty list (no ORDER audit writer, per report).
- Errors: 401 请先登录; 500 报名id不合法; 500 报名记录不存在 (missing or not owner).
- iOS caller: Core/ProfileOrderEventHost.swift:8 (path constant `originalEventPath`)
- SYNTHETIC: req `id=777` → `{"code":200,"msg":"操作成功","data":[]}`

### GET /api/official/v2/events/{id}/publish-check
- C/ApiOfficialEventController.java:356 (class `@RequestMapping("/api/official")` :56) · token (SecurityConfig:149 permits only GET `/api/official/events` and `/events/*`, not `/v2/...`); additionally `canPublish(memberId)` requires id in config `official_publish_whitelist`, and `canReadControlledEvent`
- Params: `id` Long path.
- Success: `OfficialEventV2PublishCheck` serialized by Jackson: `{blockers:[str], risks:[str], pass:bool, [warnings:[str], results:[{level:"BLOCK"|"WARN",message}]] (only when tiering flag enabled)}`.
- Errors: `{code:500,msg:"无权查看该活动发布检查"}` (plain `error(msg)`); unauthenticated filter → HTTP 401 (filter, not read).
- iOS caller: Core/OfficialOrganizer.swift:197
- SYNTHETIC: `GET /api/official/v2/events/12/publish-check` → `{"code":200,"msg":"操作成功","data":{"blockers":[],"risks":[],"pass":true}}`

---
## G36 (ApiWelcomeScreenG36Controller, `@RequestMapping("/api/welcome-screen")` C/ApiWelcomeScreenG36Controller.java:11)

### POST /api/welcome-screen/get
- C/ApiWelcomeScreenG36Controller.java:15 · token · **JSON only** (`consumes = "application/json"`; other content type → Spring 415, not a body code)
- Body: `guild_kind` integer 1 or 3 required (non-integer JSON number rejected); `guild_id` **String** of a positive long required (a JSON number → 400). Kind 3 always denied (403). Caller must be a club member (kind 1).
- Success: `{viewer_id:str, guild_id:str, guild_kind:int, entry_channel_id:str, version:long, title, description, signposts:[{channel_id:str,label,emoji:str("" if null)}] (≤5)}`.
- Errors: body `{code,msg:<errorCode>,errorCode}`: 400 WELCOME_SCREEN_INVALID; 401 UNAUTHORIZED; 403 WELCOME_SCREEN_FORBIDDEN; 409 WELCOME_SCREEN_NOT_CONFIGURED. `SCREENING_PENDING` is never emitted (report).
- Idempotency: read-only. iOS caller: Core/NativeChannelWelcome.swift:9 (path constant)
- SYNTHETIC: req `{"guild_kind":1,"guild_id":"88"}` → `{"code":200,"msg":"操作成功","data":{"viewer_id":"1001","guild_id":"88","guild_kind":1,"entry_channel_id":"501","version":3,"title":"欢迎","description":"示例","signposts":[{"channel_id":"501","label":"公告","emoji":"📢"}]}}`
