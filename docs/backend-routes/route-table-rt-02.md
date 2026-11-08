# Route table rt-02 (groups G13-G25)

Source: static reading of code on `origin/claude/be-v2-fixes` (base commit 537e43c74); not run against a live server. iOS callers refer to `origin/wip/wave5-build` of chengyin-app. All examples are SYNTHETIC (derived from code, not captured traffic). Anything not determinable from code is marked UNKNOWN.

Totals: A (G13-G17) 42 routes, B (G18-G21) 47 routes, C (G22-G25) 29 routes = 118 routes.

Common: envelope `AjaxResult {code,msg,data}`; default auth is `anyRequest().authenticated()` (SecurityConfig.java); no route of these controllers is permit-all. Per-group error shapes differ; see each row.

---
# Part A: G13-G17
# Part A route table (G13-G17), backend branch cloud/rt-02, iOS ref origin/wip/wave5-build

Common facts (verified in code, referenced by every block below):
- Envelope: `AjaxResult extends HashMap` (chengyinhub-common/.../AjaxResult.java:14). Success = `{code:200, msg:"操作成功" (or given msg), data:<payload>}`; `data` key is OMITTED when payload is null (AjaxResult.java ctor with data, `isNotNull`). Non-200 `msg` passes through `UserSafeMessage.of` (masks msgs >120 chars or containing `/api/`, class names, "token=" etc. -> "系统繁忙，请稍后重试").
- Auth default: `SecurityConfig.java:166 anyRequest().authenticated()`. Permit-all lists (SecurityConfig.java:117-163) and `PermitAllUrlProperties` (@Anonymous scan) were checked: none of the six controllers carries `@Anonymous` and none of their paths appears in a permit-all matcher. So ALL routes below = **token required**. Unauthenticated -> `AuthenticationEntryPointImpl` (sets HTTP 401, SecurityConfig-level, before controller). No class-level feature flag/@Profile on any controller EXCEPT G16 (see its blocks).
- Viewer id always `getAppUserId()` from token (BaseController.java:222).
- Global handler (GlobalExceptionHandler.java): uncaught `ServiceException` -> `{code:<e.code or 500>, msg}`; any other RuntimeException/Exception -> `{code:500, msg:userSafeMessage}`; all with HTTP 200 (no @ResponseStatus on those handlers; only NoResource -> HTTP 404).

---------------------------------------------------------------- G13

### G13 GET /api/native/blacklist/list
- Controller: ApiNativeBlacklistG13Controller.java:31
- Auth: token required (default authenticated; no @Anonymous, no flag).
- Encoding: query string only.
- Params: `cursor` long, optional, default 0 (0 = first page; <0 -> 400).
- Success shape: `data` = `{viewer_id:long, items:[{block_id:long, peer_id:long, nickname:string(<=1000)}], has_more:bool, next_cursor:long|null, write_enabled:true}`; page size 50 fixed, ordered block id desc; next_cursor = last block_id when has_more (NativeBlacklistG13Service.java:96-123).
- Errors: HTTP 200 always; body `{code:400,msg:"参数无效"}` (cursor<0, service:98). Other exception -> `{code:500,msg:"操作失败，请稍后重试"}` (controller run() :74-89). ServiceException with null code -> 500.
- Idempotency/headers: none (read).
- iOS caller: Core/NativeBlacklistService.swift:12 (path const), :48 (`exchange(listPath, fields:["cursor":...])`, sent as GET query, :73-75).
- SYNTHETIC example: `GET /api/native/blacklist/list?cursor=0` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":42,"items":[{"block_id":9,"peer_id":77,"nickname":"alice"}],"has_more":false,"next_cursor":null,"write_enabled":true}}` (SYNTHETIC). Note `next_cursor:null` is present as JSON null inside data (LinkedHashMap).

### G13 GET /api/native/blacklist/current
- Controller: ApiNativeBlacklistG13Controller.java:37
- Auth: token required.
- Encoding: query string.
- Params: `peer_id` long, REQUIRED (missing -> Spring MissingServletRequestParameter -> global handler `{code:500,...}` HTTP 200; non-numeric -> MethodArgumentTypeMismatch handler `code:500`). Service: peer<=0 or peer==viewer -> 400.
- Success shape: `data` = `{viewer_id:long, peer_id:long, blocked:bool, block_id:long|null}` (service:125-135).
- Errors: `{code:400,msg:"参数无效"}` HTTP 200 (service:127).
- Idempotency/headers: none.
- iOS caller: Core/NativeBlacklistService.swift:13, :52 (`fields:["peer_id":...]`).
- SYNTHETIC example: `GET /api/native/blacklist/current?peer_id=77` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":42,"peer_id":77,"blocked":true,"block_id":9}}` (SYNTHETIC).

### G13 GET /api/native/blacklist/receipt
- Controller: ApiNativeBlacklistG13Controller.java:43
- Auth: token required.
- Encoding: query string.
- Params: `peer_id` long REQUIRED, `expected_block_id` long REQUIRED, `request_id` string REQUIRED (must be canonical lower-case UUID: `UUID.fromString(s).toString().equals(s)`); peer<=0, peer==viewer, block<=0 -> 400 (NativeBlacklistRulesG13.parse :38-58 via service.receipt :139).
- Success shape: `data` = `{viewer_id, peer_id, expected_block_id, request_id, action:"UNBLOCK", payload_hash:<sha256 hex of "native-blacklist-v1\n{peer}\n{block}">, outcome:"UNKNOWN"|"APPLIED"|"REJECTED", reason:string|null}`. If no stored receipt: outcome="UNKNOWN", reason=null (service:142). Stored: outcome APPLIED(reason UNBLOCKED) or REJECTED(reason BLOCK_ABSENT|BLOCK_CHANGED|FINALIZED_WITHOUT_CHANGE) (service:161-166,182).
- Errors: HTTP 200 with `{code:400,msg:"参数无效"}`; `{code:409,msg:"请求编号已用于其他操作"}` when stored receipt's peer/block/hash differ (service:216).
- Idempotency/headers: key = (member_id=viewer, request_id) in table native_blacklist_receipt_g13; read-only.
- iOS caller: Core/NativeBlacklistService.swift:14, :66-67 (request_id sent `uuidString.lowercased()`).
- SYNTHETIC example: `GET /api/native/blacklist/receipt?peer_id=77&expected_block_id=9&request_id=3f2c1a9e-8b7d-4c11-9a55-0e1d2c3b4a5f` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":42,"peer_id":77,"expected_block_id":9,"request_id":"3f2c1a9e-8b7d-4c11-9a55-0e1d2c3b4a5f","action":"UNBLOCK","payload_hash":"<64hex>","outcome":"UNKNOWN","reason":null}}` (SYNTHETIC).

### G13 POST /api/native/blacklist/unblock
- Controller: ApiNativeBlacklistG13Controller.java:50
- Auth: token required.
- Encoding: JSON (`@RequestBody Map<String,Object>`, no `consumes` attr; JSON body required — missing/invalid body -> Spring HttpMessageNotReadable -> global handler `{code:500,...}` HTTP 200).
- Params: body must contain EXACTLY 3 keys `peer_id` (integer JSON number: Integer/Long/Short only, else treated invalid), `expected_block_id` (integer >0), `request_id` (canonical lowercase UUID string); extra/missing key -> 400. peer_id<=0 or ==viewer -> 400. Header `X-Audit-Log-Reason` REQUIRED, must equal exactly `SELF_CONFIRMED_UNBLOCK` (else 400 "缺少确认头") (Rules :60-63; controller :54-56). Viewer never read from body.
- Success shape: same 8-field receipt as /receipt: `{viewer_id, peer_id, expected_block_id, request_id, action:"UNBLOCK", payload_hash, outcome:"APPLIED"|"REJECTED", reason:"UNBLOCKED"|"BLOCK_ABSENT"|"BLOCK_CHANGED"}` under `data`. A REJECTED business outcome is still `code:200` (service:157-168).
- Errors (HTTP 200, body code): 400 "参数无效"/"缺少确认头"; 409 "请求编号已用于其他操作" (same request_id, different peer/block, service:216); 409 "请求正在处理，请稍后查询回执" (DuplicateKey race, service:194); 500 "操作失败，请稍后重试".
- Idempotency/headers: (viewer, request_id) row locked FOR UPDATE; replay returns stored receipt unchanged; fingerprint sha256(peer,block). Header X-Audit-Log-Reason required.
- iOS caller: Core/NativeBlacklistService.swift:15, :56 (`send(command, path: unblockPath)`), header set at :77.
- SYNTHETIC example: `POST /api/native/blacklist/unblock` headers `X-Audit-Log-Reason: SELF_CONFIRMED_UNBLOCK`, body `{"peer_id":77,"expected_block_id":9,"request_id":"3f2c1a9e-8b7d-4c11-9a55-0e1d2c3b4a5f"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":42,"peer_id":77,"expected_block_id":9,"request_id":"3f2c1a9e-...","action":"UNBLOCK","payload_hash":"<64hex>","outcome":"APPLIED","reason":"UNBLOCKED"}}` (SYNTHETIC).

### G13 POST /api/native/blacklist/settle
- Controller: ApiNativeBlacklistG13Controller.java:62
- Auth: token required.
- Encoding: JSON `@RequestBody Map` (same as unblock).
- Params: same 3-key body as unblock. Header `X-Audit-Log-Reason` REQUIRED = exactly `SELF_CONFIRMED_SETTLE`.
- Success shape: same receipt object. If no prior receipt for (viewer, request_id): records tombstone `outcome:"REJECTED", reason:"FINALIZED_WITHOUT_CHANGE"` (no im_block change); if prior receipt exists returns it (service:172-183). `action` is still the literal "UNBLOCK".
- Errors: same set as unblock (400/409/500 in body, HTTP 200).
- Idempotency/headers: same table/key; settle can never later be overridden by an unblock with that request_id (tombstone).
- iOS caller: Core/NativeBlacklistService.swift:16, :59 (`send(command, path: settlePath)`), header :77.
- SYNTHETIC example: `POST /api/native/blacklist/settle` header `X-Audit-Log-Reason: SELF_CONFIRMED_SETTLE`, same body -> `data.outcome:"REJECTED", data.reason:"FINALIZED_WITHOUT_CHANGE"` (SYNTHETIC).

### G13 POST /api/native/channels/read-through
- Controller: ApiNativeChannelG13Controller.java:25 (class mapping :21 `/api/native/channels`)
- Auth: token required.
- Encoding: FORM / plain request params (no @RequestBody, no `consumes`; Spring binds `conversation_id`, `read_to` from query or x-www-form-urlencoded body).
- Params: `conversation_id` string optional-in-signature (Convert.toLong default 0), `read_to` string (default 0). Service: either <=0 -> 400.
- Success shape: `data` = `{conversationId:long, readTo:long (stored last-read, may be clamped), clamped:bool (last != requested), lastReadMessageId:long, unread:int(>=0)}` (NativeChannelReadThroughG13Service.java:274-279) — NOTE camelCase here, unlike other G13 routes.
- Errors: HTTP 200 body `{code:400,"参数无效"}`; `{code:403,"无权查看该会话"}` if viewer not member (service:270); errors from `imService.markRead` ServiceException pass through with their code; other -> 500 "操作失败，请稍后重试". Clamp is NOT an error.
- Idempotency/headers: naturally idempotent (monotonic read pointer via IImService.markRead); no request id.
- iOS caller: Core/NativeChannelService.swift:41 (`execute(path:"api/native/channels/read-through", fields:[conversation_id, read_to])`; iOS then requires `receipt.readTo == requested` at :44, so a server clamp makes iOS throw malformedResponse).
- SYNTHETIC example: `POST /api/native/channels/read-through` form `conversation_id=501&read_to=9000` -> `{"code":200,"msg":"操作成功","data":{"conversationId":501,"readTo":8990,"clamped":true,"lastReadMessageId":8990,"unread":0}}` (SYNTHETIC).

---------------------------------------------------------------- G14  (all: ApiChannelPlatformG14Controller, class mapping `/api/channels` at :153)

Shared G14 facts (controller :224-257, service ChannelPlatformG14ServiceImpl.java): JSON in/out; IDs, versions, member ids are JSON STRINGS; masks are "0x.." hex strings. Success: HTTP 200 `{code:200,msg:"操作成功",data:{...}}`. Errors: HTTP status == `code`, body `{code:<status>, msg:<english msg>, errorCode:"<STRING>"}` (NOTE `errorCode` is at TOP level, not in data) (controller reject() :235-239). `ChannelG14Exception` codes in service: 400 INVALID_REQUEST, 401 UNAUTHORIZED (controller :227), 403 FORBIDDEN / PERMISSION_ESCALATION, 404 CHANNEL_NOT_FOUND / MEMBER_NOT_FOUND / OVERWRITE_NOT_FOUND, 409 VERSION_CONFLICT / REQUEST_ID_REUSED / CHANNEL_STATE_INVALID / NOT_RECOVERABLE, 500 OUTCOME_UNKNOWN. Unreadable JSON body -> 400 INVALID_REQUEST "请求格式不正确" (:255). Any other exception is NOT caught by controller -> global handler (HTTP 200, code 500). Path ids must be canonical positive long strings else 400 INVALID_REQUEST "invalid id" (:241-247). Only club guilds (guild_kind=1) served; other channels 404. Mutation body shape (common(), service:~381): required `request_id` (regex `^[A-Za-z0-9_.:-]{8,64}$`), `reason` (non-blank string <=120 chars, no control chars), `expected_version` (non-negative number or numeric string); optional `expected_perm_version`; unknown fields -> 400 "unknown field X"; body null -> 400 "body required". Idempotency: `(actor, request_id)` reserved+locked in channel_g14 request table; same id + same canonical-digest body -> replay stored result with extra `"replayed":true`; same id + different body/kind -> 409 REQUEST_ID_REUSED. Header `X-Audit-Log-Reason` is IGNORED (be-g14-report deviation 6). Permission bits are server-derived from club access; non-viewers get 404 CHANNEL_NOT_FOUND (existence not leaked). No feature flag.

### G14 GET /api/channels/{id}
- Controller: ApiChannelPlatformG14Controller.java:157
- Auth: token required.
- Encoding: path only.
- Params: `id` path, canonical positive long string.
- Success shape: `data` = `{id:str, guild_kind:int, guild_id:str, parent_id:str, kind:int, name, topic, position:int, is_default:int, status:int, version:str, visibility:int, slowmode_sec:int, archive_reason, purge_at, recoverable:bool, perm_version:str, my_permissions_list:[string names e.g. "VIEW_CHANNEL"], member_count:int(<=50), member_count_capped:0|1, my_state:{pinned:int,hidden:int,muted:int,permanent_muted:bool,muted_until}}` (service:36-55, channelJson ~:500).
- Errors: 400 INVALID_REQUEST (bad id); 404 CHANNEL_NOT_FOUND (missing/deleted/not guild_kind 1/viewer lacks VIEW); 401 UNAUTHORIZED.
- Idempotency/headers: none (read).
- iOS caller: Core/NativeChannelManagementService.swift:280 (`query("api/channels/\(id)", .detail)`); also Core/ChannelDirectoryCatalogProducer.swift:25 (GET `api/channels/\(channelID)`); gating Core/NativeChannelManagementFinalForward.swift:81.
- SYNTHETIC example: `GET /api/channels/12` -> `{"code":200,"msg":"操作成功","data":{"id":"12","guild_kind":1,"guild_id":"5","parent_id":"0","kind":1,"name":"general","topic":null,"position":0,"is_default":1,"status":0,"version":"3","visibility":1,"slowmode_sec":0,"archive_reason":null,"purge_at":null,"recoverable":false,"perm_version":"1","my_permissions_list":["VIEW_CHANNEL","SEND_MESSAGE"],"member_count":8,"member_count_capped":0,"my_state":{"pinned":0,"hidden":0,"muted":0,"permanent_muted":false,"muted_until":null}}}` (SYNTHETIC).

### G14 PATCH /api/channels/{id}
- Controller: ApiChannelPlatformG14Controller.java:160
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map` (no `consumes`).
- Params: path `id`; body: common fields (request_id, reason, expected_version required) + at least one of `name` (string, non-blank, <=64 code points, no `/` `#` or control chars), `topic` (string<=120 code points or null to clear), `visibility` (number 1|2), `slowmode_sec` (number 0..21600). Empty field set -> 400 "no fields". Requires MANAGE_CHANNEL (else 403 FORBIDDEN).
- Success shape: `data` = `{request_id, state:"APPLIED", id:str, guild_kind:int, guild_id:str, version:str, status:int, name, [purge_at if status==3]}`; if nothing changed also `unchanged:true` (version not bumped); replay adds `replayed:true` (service edit ~:174-200, metaResult ~:486).
- Errors: 400 INVALID_REQUEST; 403 FORBIDDEN; 404 CHANNEL_NOT_FOUND; 409 CHANNEL_STATE_INVALID (status != 0 "channel is not active"), VERSION_CONFLICT (expected_version != channel version, or CAS miss), REQUEST_ID_REUSED.
- Idempotency/headers: body.request_id (kind META, op "edit"); dedupe as described above. X-Audit-Log-Reason ignored.
- iOS caller: Core/NativeChannelManagementIntent.swift:65-70 (path build), :60 (method PATCH for `.edit`); sent via Core/NativeChannelManagementService.swift:330 and :347 (`send(path: intent.path, method: intent.method, ...)`); gate Core/NativeChannelManagementFinalForward.swift:106. iOS body adds `reason` and string `expected_version` (Intent.swift body()).
- SYNTHETIC example: `PATCH /api/channels/12` body `{"request_id":"req-0001-abcd","reason":"rename","expected_version":"3","name":"lobby"}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"req-0001-abcd","state":"APPLIED","id":"12","guild_kind":1,"guild_id":"5","version":"4","status":0,"name":"lobby"}}` (SYNTHETIC).

### G14 DELETE /api/channels/{id}
- Controller: ApiChannelPlatformG14Controller.java:165
- Auth: token required.
- Encoding: JSON body on DELETE (`@RequestBody(required=false) Map`).
- Params: path `id`; body `{request_id, reason, expected_version}` only (any other key -> 400 "unknown field"). Requires MANAGE_CHANNEL.
- Success shape: metaResult `{request_id, state:"APPLIED", id, guild_kind, guild_id, version, status:3, name, purge_at}` (soft delete, purge_at = now+30d; service:~205-219).
- Errors: 400; 403 FORBIDDEN; 404 CHANNEL_NOT_FOUND; 409 CHANNEL_STATE_INVALID (status>1, is_default==1, or kind==2 "channel cannot be deleted"), VERSION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: request_id (META/"delete").
- iOS caller: Core/NativeChannelManagementIntent.swift:61 (method DELETE for `.delete`), sent Core/NativeChannelManagementService.swift:330/:347; gate NativeChannelManagementFinalForward.swift:107.
- SYNTHETIC example: `DELETE /api/channels/12` body `{"request_id":"req-0002-abcd","reason":"cleanup","expected_version":"4"}` -> `data:{"request_id":"req-0002-abcd","state":"APPLIED","id":"12","guild_kind":1,"guild_id":"5","version":"5","status":3,"name":"lobby","purge_at":"<ts>"}` (SYNTHETIC; purge_at format UNKNOWN, DB value).

### G14 POST /api/channels/{id}/archive
- Controller: ApiChannelPlatformG14Controller.java:170
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map`.
- Params: path `id`; body `{request_id, reason, expected_version, archived: 0|1 (JSON number, not string/bool)}`; non-0/1 -> 400 "archived must be 0 or 1". Requires MANAGE_CHANNEL.
- Success shape: metaResult `{request_id,state:"APPLIED",id,guild_kind,guild_id,version,status:1|0,name}` (archived -> status 1 reason "manual"; archived=0 -> status 0).
- Errors: 400; 403; 404; 409 CHANNEL_STATE_INVALID (archive: status!=0 or default channel; unarchive: not manually archived), VERSION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: request_id (META, op "archive"/"unarchive").
- iOS caller: Core/NativeChannelManagementIntent.swift:67; gate Core/NativeChannelManagementFinalForward.swift:109 (requires `.integer` archived field); send Core/NativeChannelManagementService.swift:330/:347.
- SYNTHETIC example: `POST /api/channels/12/archive` body `{"request_id":"req-0003-abcd","reason":"quiet","expected_version":"4","archived":1}` -> `data:{...,"version":"5","status":1,"name":"lobby"}` (SYNTHETIC).

### G14 POST /api/channels/{id}/restore
- Controller: ApiChannelPlatformG14Controller.java:175
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map`.
- Params: path `id`; body `{request_id, reason, expected_version}` only. Requires guild-level MANAGE_CHANNEL (deleted channels are looked up with allowDeleted; non-club-members -> 404).
- Success shape: metaResult with `status:1` (restored as manually archived).
- Errors: 400; 403; 404 CHANNEL_NOT_FOUND; 409 NOT_RECOVERABLE (status!=3 or not recoverable), VERSION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: request_id (META/"restore").
- iOS caller: Core/NativeChannelManagementIntent.swift:68; gate NativeChannelManagementFinalForward.swift:108; send Core/NativeChannelManagementService.swift:330/:347.
- SYNTHETIC example: `POST /api/channels/12/restore` body `{"request_id":"req-0004-abcd","reason":"oops","expected_version":"5"}` -> `data:{"request_id":"req-0004-abcd","state":"APPLIED","id":"12",...,"version":"6","status":1,"name":"lobby"}` (SYNTHETIC).

### G14 GET /api/channels/{id}/permissions
- Controller: ApiChannelPlatformG14Controller.java:180
- Auth: token required.
- Encoding: path only.
- Params: path `id`.
- Success shape: `data` = `{channel_id:str, version:str, perm_version:str, overrides:[{target_type:int(1=everyone,2=role), target_id:str, allow_bits:"0x..", deny_bits:"0x..", note}]}` (service:58-70). Requires MANAGE_ROLE or MANAGE_CHANNEL (else 403).
- Errors: 400; 403 FORBIDDEN; 404 CHANNEL_NOT_FOUND.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelManagementService.swift:284 (`query("api/channels/\(id)/permissions", .permissionsRead)`); gate FinalForward.swift:82.
- SYNTHETIC example: `GET /api/channels/12/permissions` -> `data:{"channel_id":"12","version":"4","perm_version":"2","overrides":[{"target_type":1,"target_id":"0","allow_bits":"0x2","deny_bits":"0x0","note":null}]}` (SYNTHETIC).

### G14 PUT /api/channels/{id}/permissions/{type}/{target}
- Controller: ApiChannelPlatformG14Controller.java:183
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map`.
- Params: path `id`; `type` must be "1" or "2" (else 400 "invalid target type"); `target`: for type 1 must be "0"; for type 2 a positive long string (else 400 "invalid overwrite target"). Body: `request_id`, `reason`, `expected_version`, `expected_perm_version` (ALL required; perm version missing -> 400), `allow_bits` & `deny_bits` ("0x"+hex, total length 3..10, value <= 0x3ffffff, allow & deny must be disjoint, no guild-scoped bits), optional `note` (string <=120). Requires MANAGE_ROLE; cannot allow bits actor lacks (403 PERMISSION_ESCALATION).
- Success shape: `data` = `{request_id, state:"APPLIED", channel_id:str, version:str, perm_version:str, target_type:int, target_id:str, allow_bits:"0x..", deny_bits:"0x..", note, inherited:false, audit_id:str}` (service overwrite() ~:266-326). Bumps both version and perm_version.
- Errors: 400; 403 FORBIDDEN / PERMISSION_ESCALATION; 404; 409 CHANNEL_STATE_INVALID (status>1), VERSION_CONFLICT (channel version or perm_version mismatch), REQUEST_ID_REUSED.
- Idempotency/headers: request_id (GOV, op "ow-put:{type}:{target}").
- iOS caller: Core/NativeChannelManagementIntent.swift:69 (path), :60 (PUT); gate NativeChannelManagementFinalForward.swift:113; send NativeChannelManagementService.swift:330/:347.
- SYNTHETIC example: `PUT /api/channels/12/permissions/1/0` body `{"request_id":"req-0005-abcd","reason":"lock","expected_version":"4","expected_perm_version":"2","allow_bits":"0x1","deny_bits":"0x2"}` -> `data:{"request_id":"req-0005-abcd","state":"APPLIED","channel_id":"12","version":"5","perm_version":"3","target_type":1,"target_id":"0","allow_bits":"0x1","deny_bits":"0x2","note":null,"inherited":false,"audit_id":"88"}` (SYNTHETIC).

### G14 DELETE /api/channels/{id}/permissions/{type}/{target}
- Controller: ApiChannelPlatformG14Controller.java:189
- Auth: token required.
- Encoding: JSON body on DELETE.
- Params: same path rules as PUT; body `{request_id, reason, expected_version, expected_perm_version}` ONLY (allow/deny/note rejected as unknown field). Requires MANAGE_ROLE.
- Success shape: `data` = `{request_id, state:"APPLIED", channel_id, version, perm_version, target_type, target_id, deleted:true, inherited:true, audit_id}`.
- Errors: as PUT plus 404 OVERWRITE_NOT_FOUND ("no such overwrite").
- Idempotency/headers: request_id (GOV, "ow-del:{type}:{target}").
- iOS caller: Core/NativeChannelManagementIntent.swift:61,69; gate FinalForward.swift:113; send NativeChannelManagementService.swift:330/:347.
- SYNTHETIC example: `DELETE /api/channels/12/permissions/2/77` body `{"request_id":"req-0006-abcd","reason":"undo","expected_version":"5","expected_perm_version":"3"}` -> `data:{"request_id":"req-0006-abcd","state":"APPLIED","channel_id":"12","version":"6","perm_version":"4","target_type":2,"target_id":"77","deleted":true,"inherited":true,"audit_id":"89"}` (SYNTHETIC).

### G14 GET /api/channels/{id}/effective/{memberId}
- Controller: ApiChannelPlatformG14Controller.java:195
- Auth: token required.
- Encoding: path only.
- Params: `id`, `memberId` canonical positive long strings. For memberId != caller requires MANAGE_ROLE (403), and target must be a club member (404 MEMBER_NOT_FOUND).
- Success shape: `data` = `{channel_id:str, member_id:str, permissions:"0x..", permissions_list:[names], version:str (this is channel perm_version)}` (service:73-89).
- Errors: 400; 403 FORBIDDEN; 404 CHANNEL_NOT_FOUND / MEMBER_NOT_FOUND.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelManagementService.swift:302 (`query("api/channels/\(id)/effective/\(owner.accountID)", .permissionsRead)`); gate FinalForward.swift:82 (own id only).
- SYNTHETIC example: `GET /api/channels/12/effective/42` -> `data:{"channel_id":"12","member_id":"42","permissions":"0x3f","permissions_list":["VIEW_CHANNEL","SEND_MESSAGE","ATTACH_FILE","EMBED_LINK","ADD_REACTION","READ_HISTORY"],"version":"2"}` (SYNTHETIC).

### G14 GET /api/channels/{id}/members
- Controller: ApiChannelPlatformG14Controller.java:200
- Auth: token required.
- Encoding: query string.
- Params: `limit` int optional default 50 (must be 1..50 else 400 "limit must be 1..50"); `cursor` string optional (canonical positive long = last member_id); `role_id` string optional (canonical positive long; filter matches NOBODY — role membership not modelled, be-g14-report #4). Requires VIEW (else 404).
- Success shape: `data` = `{list:[{member_id:str, nickname:str (falls back to member_id string), role_ids:[] (always empty), join_time}], has_more:0|1 (INT, not bool), next_cursor:str|null}` (service:92-120).
- Errors: 400 INVALID_REQUEST; 404 CHANNEL_NOT_FOUND.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelMentionTargets.swift:30 (path), :68-69 (limit=50, cursor); Core/NativeChannelRoleFlow.swift:33,:48; Core/NativeFriendChannelSourceFlow.swift:12.
- SYNTHETIC example: `GET /api/channels/12/members?limit=50` -> `data:{"list":[{"member_id":"42","nickname":"alice","role_ids":[],"join_time":"<ts>"}],"has_more":0,"next_cursor":null}` (SYNTHETIC).

### G14 GET /api/channels/{id}/op-log
- Controller: ApiChannelPlatformG14Controller.java:207
- Auth: token required.
- Encoding: query string.
- Params: `limit` int default 50 (1..50); `before_id` string optional (canonical positive long). Requires VIEW_AUDIT bit (else 403).
- Success shape: `data` = `{list:[{id:str, channel_id:str, action:string e.g. CHANNEL_UPDATE|CHANNEL_DELETE|CHANNEL_ARCHIVE|CHANNEL_UNARCHIVE|CHANNEL_RESTORE|OVERWRITE_PUT|OVERWRITE_DELETE, from_status, to_status, operator_id:str|null, request_id, reason, create_time}], has_more:bool (true boolean here, unlike /members), next_cursor:str|null}` (service:123-150). Ordering id desc (mapper; UNKNOWN exact SQL not read).
- Errors: 400; 403 FORBIDDEN; 404 CHANNEL_NOT_FOUND.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelAuditFlow.swift:202 (limit=50, before_id), App/AppSession.swift:144, Core/BusinessRuntimeConfiguration.swift:211.
- SYNTHETIC example: `GET /api/channels/12/op-log?limit=50` -> `data:{"list":[{"id":"88","channel_id":"12","action":"CHANNEL_UPDATE","from_status":null,"to_status":null,"operator_id":"42","request_id":"req-0001-abcd","reason":"rename","create_time":"<ts>"}],"has_more":false,"next_cursor":null}` (SYNTHETIC).

### G14 POST /api/channels/{id}/member-state
- Controller: ApiChannelPlatformG14Controller.java:214 (comment: not in G14 path list; needed by receipts)
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map`.
- Params: path `id`; body EXACTLY `request_id` (regex `^[A-Za-z0-9_.:-]{8,64}$`) + exactly one of `pinned`|`hidden`|`muted` with JSON number 0 or 1 (else 400 "exactly one of pinned/hidden/muted" / "<f> must be 0 or 1"). NO reason / expected_version. Requires VIEW (else 404).
- Success shape: `data` = `{request_id, status:"APPLIED", channel_id:str, member_id:str, pinned:int, hidden:int, muted:int, permanent_muted:bool, muted_until:null}` (service memberState ~:331-361). NOTE key is `status` here (meta routes use `state`). Replay adds `replayed:true`.
- Errors: 400 INVALID_REQUEST; 404 CHANNEL_NOT_FOUND; 409 REQUEST_ID_REUSED.
- Idempotency/headers: request_id (MEMBER_STATE kind); (actor, request_id) dedupe. muted=1 sets permanent_muted=1, no timed mute (report #7).
- iOS caller: Core/NativeChannelPersonalStateFlow.swift:92 and :110 (`exchange("POST", path+"/member-state", body:...)`), gating :41,:43; Core/BusinessRuntimeConfiguration.swift:175.
- SYNTHETIC example: `POST /api/channels/12/member-state` body `{"request_id":"ms-0001-abcd","pinned":1}` -> `data:{"request_id":"ms-0001-abcd","status":"APPLIED","channel_id":"12","member_id":"42","pinned":1,"hidden":0,"muted":0,"permanent_muted":false,"muted_until":null}` (SYNTHETIC).

### G14 GET /api/channels/member-state-requests/{requestId}
- Controller: ApiChannelPlatformG14Controller.java:219
- Auth: token required.
- Encoding: path only.
- Params: `requestId` path, regex `^[A-Za-z0-9_.:-]{8,64}$` else 400 "invalid request id".
- Success shape: if a stored APPLIED MEMBER_STATE result exists for (caller, requestId): returns that stored map (same as member-state success, `status:"APPLIED"`); else `data` = `{request_id, status:"NOT_FOUND", resume_with_same_request:1}` (service:153-162). Note receipt is keyed by caller only (not channel).
- Errors: 400 INVALID_REQUEST.
- Idempotency/headers: read-only receipt for the member-state request id.
- iOS caller: Core/NativeChannelPersonalStateFlow.swift:167 (`receiptPath`), Core/BusinessRuntimeConfiguration.swift:168 (prefix gate).
- SYNTHETIC example: `GET /api/channels/member-state-requests/ms-0001-abcd` -> `data:{"request_id":"ms-0001-abcd","status":"NOT_FOUND","resume_with_same_request":1}` (SYNTHETIC).

(G14 side note: iOS meta/governance mutation receipts live at `api/channel-platform/requests/{id}` and `.../governance/requests/{id}` (NativeChannelManagementIntent.swift:~78); those are NOT in this controller — only `findReceipt` hook exists in the service. Their controller is UNKNOWN / out of Part A scope.)

---------------------------------------------------------------- G15  (ApiImMessageG15Controller, class mapping `/api/im/message` at :29)

Shared G15 facts (controller :37-60, service ImMessageMutationG15Service.java): returns `ResponseEntity<AjaxResult>`. Success HTTP 200 `{code:200,msg:"操作成功",data:{...}}`. Known failure (`Failure`): HTTP status == body `code`, body `{code, msg:<Chinese>, errorCode:"<STRING>", outcome_known:true}` (top-level keys). Unexpected exception: HTTP 500 `{code:500,msg:"操作失败，请稍后重试",errorCode:"OUTCOME_UNKNOWN",outcome_known:false}` (:50). Membership check on every route: caller must be non-deleted member of conversation AND `imService.isActiveGroupMember` else 403 NOT_CONVERSATION_MEMBER "无权访问该会话" (service:427-436). Invalid body (not JSON) on edit/recall -> Spring error (global handler path, UNKNOWN exact shape; code 500 HTTP 200). No feature flag.

### G15 POST /api/im/message/edit
- Controller: ApiImMessageG15Controller.java:62
- Auth: token required.
- Encoding: JSON `@RequestBody Map` (required body).
- Params: body `request_id` (regex `[A-Za-z0-9_-]{16,64}`), `conversation_id` (digits 1..18, >0; number or string), `message_id` (same), `expected_version` (positive integer; number or numeric string), `content` (string, non-blank, <=2000 code points). Server reads only these keys (extras ignored).
- Success shape: `data` = `{message_id:str, conversation_id:str, version:long, revision:long, changed:bool}`; changed=false when content identical (no version bump); replay returns the stored result JSON (service:56-108).
- Errors (HTTP status = code): 400 INVALID_REQUEST_ID / INVALID_CONVERSATION_ID / INVALID_MESSAGE_ID / INVALID_EXPECTED_VERSION / INVALID_CONTENT; 403 NOT_CONVERSATION_MEMBER, MESSAGE_NOT_OWNER; 404 MESSAGE_NOT_FOUND; 409 MESSAGE_NOT_EDITABLE (msg_type!=1 or status!=0), EDIT_WINDOW_EXPIRED (>15 min), MESSAGE_VERSION_CONFLICT, REQUEST_ID_CONFLICT (same request_id, different hash/op/conversation), REQUEST_IN_PROGRESS; 422 CONTENT_REJECTED (content-security check, msg = checker text); 500 OUTCOME_UNKNOWN.
- Idempotency/headers: (member_id, request_id) in im_message_request_g15, request_hash = sha256(EDIT,cid,mid,expected,content); replay returns stored result; no custom headers.
- iOS caller: Core/NativeChannelMessageService.swift:54 (`path = "api/im/message/edit"`, POST via execute :51/:107-110); Core/NativeChannelMessageFinalForward.swift:84.
- SYNTHETIC example: `POST /api/im/message/edit` body `{"request_id":"abcd1234abcd1234","conversation_id":"501","message_id":"9001","expected_version":1,"content":"hi (edited)"}` -> `{"code":200,"msg":"操作成功","data":{"message_id":"9001","conversation_id":"501","version":2,"revision":2,"changed":true}}` (SYNTHETIC).

### G15 POST /api/im/message/recall
- Controller: ApiImMessageG15Controller.java:68
- Auth: token required.
- Encoding: JSON `@RequestBody Map`.
- Params: `request_id`, `conversation_id`, `message_id`, `expected_version` (as edit); optional `reason` (any value -> String.valueOf, <=200 code points else 400 INVALID_REASON).
- Success shape: `data` = `{message_id:str, conversation_id:str, status:1, version:long, changed:bool}`; already-recalled message returns changed=false if expected_version equals current (service:111-152).
- Errors: 400 INVALID_REQUEST_ID/INVALID_*/INVALID_REASON; 403 NOT_CONVERSATION_MEMBER, MESSAGE_NOT_OWNER; 404 MESSAGE_NOT_FOUND; 409 MESSAGE_NOT_RECALLABLE (status not 0/1), MESSAGE_VERSION_CONFLICT, RECALL_WINDOW_EXPIRED (>2 min), REQUEST_ID_CONFLICT, REQUEST_IN_PROGRESS; 500 OUTCOME_UNKNOWN.
- Idempotency/headers: same request table; hash sha256(RECALL,cid,mid,expected,reason).
- iOS caller: Core/NativeChannelMessageService.swift:55; Core/NativeChannelMessageFinalForward.swift:85.
- SYNTHETIC example: `POST /api/im/message/recall` body `{"request_id":"abcd1234abcd1235","conversation_id":"501","message_id":"9001","expected_version":2,"reason":"typo"}` -> `data:{"message_id":"9001","conversation_id":"501","status":1,"version":3,"changed":true}` (SYNTHETIC).

### G15 GET /api/im/message/request
- Controller: ApiImMessageG15Controller.java:74
- Auth: token required.
- Encoding: query string.
- Params: `request_id` string REQUIRED (regex `[A-Za-z0-9_-]{16,64}` else 400 INVALID_REQUEST_ID).
- Success shape: not found: `data` = `{request_id, state:"NOT_FOUND", outcome_confirmed:false}`. Found: `{request_id, state:"APPLIED", outcome_confirmed:true, operation:"EDIT"|"RECALL", conversation_id:str, result_redacted:bool, result:{...stored mutation result}}`; if caller no longer a member, `result_redacted:true` and `result` omitted (service:155-186).
- Errors: 400 INVALID_REQUEST_ID; 500 OUTCOME_UNKNOWN.
- Idempotency/headers: receipt lookup by (caller, request_id).
- iOS caller: Core/NativeChannelMessageService.swift:66 (`execute(.receipt, path:"api/im/message/request", query:["request_id":...])`); Core/NativeChannelMessageFinalForward.swift:96.
- SYNTHETIC example: `GET /api/im/message/request?request_id=abcd1234abcd1234` -> `data:{"request_id":"abcd1234abcd1234","state":"APPLIED","outcome_confirmed":true,"operation":"EDIT","conversation_id":"501","result_redacted":false,"result":{"message_id":"9001","conversation_id":"501","version":2,"revision":2,"changed":true}}` (SYNTHETIC).

### G15 GET /api/im/message/mutations
- Controller: ApiImMessageG15Controller.java:80
- Auth: token required.
- Encoding: query string.
- Params: `conversation_id` string REQUIRED (digits, >0 else 400 INVALID_CONVERSATION_ID); `mutation_cursor` string REQUIRED (`0` or `[1-9][0-9]{0,17}` else 400 INVALID_CURSOR); `limit` int default 50 (clamped 1..50, no error).
- Success shape: `data` = `{list:[{mutation_cursor:str, message_id:str, version:long, kind:"EDIT"|"RECALL", invalidate:true | message:{id:str,conversationId:str,version:long,status:0|1,[msgType,senderId:str,content,extraJson,createTime:epoch-ms,edited_at:ISO8601]}}], has_more:bool, next_mutation_cursor:str, sync_contract:"VISIBLE_ORDER_PLUS_MUTATIONS_V1"}` (service:191-233; snapshot :343-371 uses camelCase keys). RECALL entries or stale snapshots carry `invalidate:true` instead of `message`.
- Errors: 400 INVALID_CONVERSATION_ID / INVALID_CURSOR; 403 NOT_CONVERSATION_MEMBER.
- Idempotency/headers: none; cursor = im_message_mutation_g15.id ascending.
- iOS caller: Core/NativeChannelMessageService.swift:71 (limit "50", `mutation_cursor`); Core/NativeChannelMessageFinalForward.swift:107.
- SYNTHETIC example: `GET /api/im/message/mutations?conversation_id=501&mutation_cursor=0&limit=50` -> `data:{"list":[{"mutation_cursor":"7","message_id":"9001","version":2,"kind":"EDIT","message":{"id":"9001","conversationId":"501","version":2,"status":0,"msgType":1,"senderId":"42","content":"hi (edited)","extraJson":null,"createTime":1762560000000,"edited_at":"2026-11-08T10:00:00+08:00"}}],"has_more":false,"next_mutation_cursor":"7","sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1"}` (SYNTHETIC).

### G15 GET /api/im/message/context
- Controller: ApiImMessageG15Controller.java:87
- Auth: token required.
- Encoding: query string.
- Params: `conversation_id` REQUIRED, `message_id` REQUIRED (controller id(): regex `[1-9][0-9]{0,17}` else 400 INVALID_ID "参数不合法"); `limit` int default 20 (clamped 1..20).
- Success shape: `data` = `{source:"original-channel-message-context-v1", conversation_id:str, anchor_id:str, anchor:{snapshot}, older:{list:[snapshots, oldest-first], has_more:bool, next_cursor:str|null, next_after:null}, newer:{list:[snapshots], has_more:bool, next_cursor:null, next_after:str|null}}` (service:236-273). Snapshot keys camelCase as in /mutations.
- Errors: 400 INVALID_ID; 403 NOT_CONVERSATION_MEMBER; 404 MESSAGE_NOT_FOUND (anchor missing/hidden/status!=0).
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelMessageService.swift:88; Core/NativeChannelMessageFinalForward.swift:100.
- SYNTHETIC example: `GET /api/im/message/context?conversation_id=501&message_id=9001&limit=20` -> `data:{"source":"original-channel-message-context-v1","conversation_id":"501","anchor_id":"9001","anchor":{"id":"9001","conversationId":"501","version":2,"status":0,...},"older":{"list":[],"has_more":false,"next_cursor":null,"next_after":null},"newer":{"list":[],"has_more":false,"next_cursor":null,"next_after":null}}` (SYNTHETIC).

### G15 GET /api/im/message/{messageId}/revisions
- Controller: ApiImMessageG15Controller.java:94
- Auth: token required.
- Encoding: path + query.
- Params: `messageId` path (regex `[1-9][0-9]{0,17}` else 400 INVALID_ID); `cursor` string optional (same regex; exclusive upper bound on revision_no); `limit` int default 20 (clamped 1..20).
- Success shape: `data` = `{list:[{message_id:str, revision_no:long, check_status:int, [content:string only if check_status==1 AND caller is the sender]}], has_more:bool, next_cursor:str|null}` newest first (service:277-309).
- Errors: 404 MESSAGE_NOT_FOUND (missing or status!=0); 403 NOT_CONVERSATION_MEMBER; 400 INVALID_ID / INVALID_CURSOR.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelMessageService.swift:96 (limit "20", optional cursor); Core/NativeChannelMessageFinalForward.swift:123.
- SYNTHETIC example: `GET /api/im/message/9001/revisions?limit=20` -> `data:{"list":[{"message_id":"9001","revision_no":2,"check_status":1,"content":"hi (edited)"},{"message_id":"9001","revision_no":1,"check_status":1,"content":"hi"}],"has_more":false,"next_cursor":null}` (SYNTHETIC; viewer is sender).

### G15 GET /api/im/message/{messageId}/attachment
- Controller: ApiImMessageG15Controller.java:101
- Auth: token required.
- Encoding: path only.
- Params: `messageId` path (regex as above).
- Success shape: `data` = `{message_id:str, conversation_id:str, kind:"IMAGE", source:"LEGACY_SINGLE_IMAGE", state:"UNAVAILABLE"|"UNSUPPORTED"|"REJECTED"|"PENDING"|"SOURCE_UNCONFIRMED", message_version:long}` — never READY, no URL/lease (service:316-338; by design per javadoc :311-315).
- Errors: 400 INVALID_ID; 403 NOT_CONVERSATION_MEMBER; 404 MESSAGE_NOT_FOUND.
- Idempotency/headers: none.
- iOS caller: Core/NativeChannelAttachmentDescriptorTransport.swift:25; Core/NativeChannelAttachmentPreviewFlow.swift:145; App/NativeChannelAttachmentPreviewAssembly.swift:15; gate Core/BusinessRuntimeConfiguration.swift:163.
- SYNTHETIC example: `GET /api/im/message/9002/attachment` -> `data:{"message_id":"9002","conversation_id":"501","kind":"IMAGE","source":"LEGACY_SINGLE_IMAGE","state":"SOURCE_UNCONFIRMED","message_version":1}` (SYNTHETIC).

---------------------------------------------------------------- G16  (ApiNonCashRewardAliasG16Controller, class mapping `/api/rewards/noncash` at :29)

Shared G16 facts: CLASS GATING: `@ConditionalOnProperty(prefix="chengyin.pledge-v1", name="enabled", havingValue="true", matchIfMissing=false)` (:27) AND `@Profile("!w17-reward-read-contract")` (:28). Property not set in any yml/properties in repo (grep found none) => default OFF => when off, the controller bean does not exist and all 8 routes return NotFound (global handler HTTP 404, `{code:404,msg:"请求路径不存在"}`). When profile `w17-reward-read-contract` is active, this alias is replaced by ApiNonCashRewardReadController (GET /api/rewards/noncash and /{awardId} only, different contract) and the POST/case/claim/catalog/offer routes below do NOT exist. Every method first calls `availability.requireEnabled()` (PledgeV1Availability; throws PledgeRejection PLEDGE_V1_DISABLED outside run() -> global RuntimeException handler -> `{code:500,msg:"PLEDGE_V1_DISABLED"}` HTTP 200; unreachable when flag on). Error mapping (controller run() :99-110): PledgeRejection.code NOT_FOUND -> envelope code 404, INVALID_INPUT -> 400, ALL others -> 409; body `AjaxResult.error(code, rejected.code)` i.e. `{code:<404|400|409>, msg:"<REJECTION_CODE>"}` with HTTP status 200 (envelope only, NO HTTP status change, NO errorCode key). Other RuntimeExceptions -> global handler `{code:500,...}`. `msg` carries the machine string. Possible rejection codes seen in RewardPledgeService: INVALID_INPUT, NOT_FOUND, CONFLICT, FORBIDDEN, CASH_CLOSED, SUBJECT_ACCESS_UNCONFIGURED, SUBJECT_REWARD_MISMATCH, SUBJECT_UNMAPPED, COUPON_ABSENT, NO_VALID_VERSION, AMBIGUOUS_VERSION, NO_AUTHORITATIVE_FACT, COUPON_NOT_ISSUED, STOCK_CONFLICT, RECEIPT_MISMATCH.

### G16 POST /api/rewards/noncash/claims
- Controller: ApiNonCashRewardAliasG16Controller.java:39
- Auth: token required; gated by flag `chengyin.pledge-v1.enabled=true` and profile !w17-reward-read-contract (see shared).
- Encoding: JSON `@RequestBody Claim` (public-field POJO; no `consumes`).
- Params: body `requestId` (text, non-blank, <=128), `versionId` (same), `branch` (same; only "THEME" or "COMPENSATION" produce an award path; others -> state REFUSED NO_AUTHORITATIVE_FACT), `subjectId` (same; THEME: topic id numeric string; COMPENSATION: "awardId:..."). `ownerId` in body is ignored/overwritten with token id (:42).
- Success shape: `data` is one of: award view `{awardId, requestId, state:"AWARDED"|..., historyId, factRef:"THEME:{topic}:session:{sid}", terms, termsHash, ruleVersion, redeemStart, redeemEnd, serviceEnd, guaranteed:false, blocked:"W06_RESERVATION_ABSENT", useStatus}` (awardView RewardPledgeService.java:~1000-1017), or refusal `{requestId, state:"REFUSED", errorCode:<PLEDGE_NOT_FROZEN|POLICY_CLOSED|MINOR_CLOSED|NOT_NEW_SUPPLY|STOCK_EXHAUSTED|NO_AUTHORITATIVE_FACT>, guaranteed:false, blocked:"W06_RESERVATION_ABSENT"}` at code 200, or a stored non-award intent `{requestId, state, errorCode, guaranteed:false}`. Types of terms/redeemStart etc. UNKNOWN (come from Version row).
- Errors: envelope 400 INVALID_INPUT; 404 NOT_FOUND; 409 CONFLICT (same requestId, different payload hash), others per list above.
- Idempotency/headers: (ownerId, requestId) intent row locked; hash = sha(versionId|branch|subjectId|ownerId); replay returns original result; award unique key (ruleVersion, owner, scope, factRef) -> state REPLAY returns existing award.
- iOS caller: Core/RewardPledge.swift:48 (const `plannedClaim`), :263 (`RewardPledgeRequests.claim` builds JSON `{requestId, versionId, branch:"THEME", subjectId}`).
- SYNTHETIC example: `POST /api/rewards/noncash/claims` body `{"requestId":"req-abc","versionId":"v-1","branch":"THEME","subjectId":"1234"}` -> `{"code":200,"msg":"操作成功","data":{"awardId":"<uuid>","requestId":"req-abc","state":"AWARDED","historyId":555,"factRef":"THEME:1234:session:77","guaranteed":false,"blocked":"W06_RESERVATION_ABSENT",...}}` (SYNTHETIC).

### G16 POST /api/rewards/noncash/claims/recover
- Controller: ApiNonCashRewardAliasG16Controller.java:46
- Auth: token required; same flag/profile gating.
- Encoding: JSON `@RequestBody Map<String,String>` (all values must be strings).
- Params: body `requestId` (text <=128). Original request id only.
- Success shape: same as claim result (award view / intent state view). If intent still UNKNOWN it re-runs finish() with the stored original claim.
- Errors: envelope 404 NOT_FOUND (no intent for caller+requestId); 400 INVALID_INPUT; 409 others.
- Idempotency/headers: keyed (owner, requestId).
- iOS caller: Core/RewardPledge.swift:49 (`plannedIntentQuery`), :270ish `RewardPledgeRequests.query` posts `{requestId}`.
- SYNTHETIC example: `POST /api/rewards/noncash/claims/recover` body `{"requestId":"req-abc"}` -> `data:{...same award view...}` (SYNTHETIC).

### G16 GET /api/rewards/noncash
- Controller: ApiNonCashRewardAliasG16Controller.java:54
- Auth: token required; same flag/profile gating.
- Encoding: query string; controller declares NO params (limit/cursor from iOS are ignored).
- Params: none read.
- Success shape: `data` = JSON ARRAY of raw `RewardPledgeRows.Award` POJO public fields: `[{awardId, versionId, ruleVersion, rewardScope, factRef, state, requestId, beneficiaryId:long, createdAt:long(ms), historyId:long|null}]` — the owner's full list, unpaginated (RewardPledgeService.listMine :743; Award class RewardPledgeRows.java:40-44). MISMATCH: iOS decodes `data` as object `{items:[...], nextCursor, asOf}` (Core/NonCashRewardService.swift:83-87); an array `data` will fail iOS decode (also be-g16-report deviation 1).
- Errors: only 500-class/global; no per-owner rejection.
- Idempotency/headers: none (read).
- iOS caller: Core/NonCashRewardService.swift:17 (`get(path:"api/rewards/noncash", query: limit, cursor)`), Core/RewardPledge.swift:47 (const), :50 listPath check.
- SYNTHETIC example: `GET /api/rewards/noncash?limit=20` -> `{"code":200,"msg":"操作成功","data":[{"awardId":"<uuid>","versionId":"v-1","ruleVersion":"r1","rewardScope":"PLEDGE:v-1","factRef":"THEME:1234:session:77","state":"AWARDED","requestId":"req-abc","beneficiaryId":42,"createdAt":1762560000000,"historyId":555}]}` (SYNTHETIC; Jackson serialisation of public fields is assumed).

### G16 GET /api/rewards/noncash/subjects/{subjectId}
- Controller: ApiNonCashRewardAliasG16Controller.java:61
- Auth: token required; same flag/profile gating.
- Encoding: path only.
- Params: `subjectId` path = topic id numeric string (non-numeric -> INVALID_INPUT). Requires `PledgeSubjectAccess` bean (else SUBJECT_ACCESS_UNCONFIGURED 409).
- Success shape: `data` = `{versionId, ruleVersion, termsHash, subject:str, coupon:long, store:long, guaranteed:false, blocked:"W06_RESERVATION_ABSENT", errorCode:"NO_AUTHORITATIVE_FACT" | factRef:"THEME:{topic}:session:{sid}"}` (RewardPledgeService.catalog :778-815; exactly one of errorCode/factRef present).
- Errors: envelope 400 INVALID_INPUT; 409 SUBJECT_UNMAPPED / COUPON_ABSENT / NO_VALID_VERSION / AMBIGUOUS_VERSION / SUBJECT_ACCESS_UNCONFIGURED / others.
- Idempotency/headers: none (read).
- iOS caller: Core/RewardPledge.swift:274 (`RewardPledgeRequests.catalog` -> GET `api/rewards/noncash/subjects/`+id); route classifier :96.
- SYNTHETIC example: `GET /api/rewards/noncash/subjects/1234` -> `data:{"versionId":"v-1","ruleVersion":"r1","termsHash":"<hash>","subject":"1234","coupon":9,"store":3,"guaranteed":false,"blocked":"W06_RESERVATION_ABSENT","factRef":"THEME:1234:session:77"}` (SYNTHETIC).

### G16 GET /api/rewards/noncash/versions/{versionId}
- Controller: ApiNonCashRewardAliasG16Controller.java:68
- Auth: token required; same flag/profile gating.
- Encoding: path + query.
- Params: `versionId` path; `branch` query REQUIRED (only "THEME" accepted else 409 NO_AUTHORITATIVE_FACT); `subjectId` query REQUIRED (topic id numeric string). Missing query param -> global handler `{code:500,...}`.
- Success shape: `data` = `{versionId, ruleVersion, state, terms, redeemStart, redeemEnd, storeId, quantity, available, rewardScope:"PLEDGE:{versionId}", minorRestricted, guaranteed:false, blocked:"W06_RESERVATION_ABSENT", [errorCode: PLEDGE_NOT_FROZEN|POLICY_CLOSED|MINOR_CLOSED|NO_AUTHORITATIVE_FACT], [factRef]}` (offer :823-862). Types of terms/redeem*/quantity UNKNOWN (row-dependent).
- Errors: envelope 404 NOT_FOUND; 400 INVALID_INPUT; 409 NO_AUTHORITATIVE_FACT / SUBJECT_REWARD_MISMATCH / others.
- Idempotency/headers: none (read; takes a stock lock, no mutation).
- iOS caller: Core/RewardPledge.swift:50 (`offerPrefix`), :284-292 (`RewardPledgeRequests.offer`, GET with branch=THEME & subjectId).
- SYNTHETIC example: `GET /api/rewards/noncash/versions/v-1?branch=THEME&subjectId=1234` -> `data:{"versionId":"v-1","ruleVersion":"r1","state":"FROZEN","storeId":3,"quantity":10,"available":4,"rewardScope":"PLEDGE:v-1","minorRestricted":0,"guaranteed":false,"blocked":"W06_RESERVATION_ABSENT","factRef":"THEME:1234:session:77",...}` (SYNTHETIC).

### G16 POST /api/rewards/noncash/cases
- Controller: ApiNonCashRewardAliasG16Controller.java:77
- Auth: token required; same flag/profile gating.
- Encoding: JSON `@RequestBody Map<String,String>`.
- Params: body `versionId`, `awardId`, `reason` (each non-blank <=128; `reason` == "CASH_REFUND" -> 409 CASH_CLOSED). Award must belong to caller and match versionId else 404 NOT_FOUND.
- Success shape: `data` = `{caseId:uuid, awardId, state:"OPEN", reason}` (caseView :1033-1041).
- Errors: envelope 400 INVALID_INPUT; 404 NOT_FOUND; 409 CASH_CLOSED/CONFLICT.
- Idempotency/headers: per (owner, awardId): second call returns the existing case (insertCase :513-524 / DataIntegrityViolation fallback); no request id.
- iOS caller: Core/RewardPledge.swift:57 (const `cases`), :444 (`json(RewardPledgeRoutes.cases, [awardId, versionId, reason])`).
- SYNTHETIC example: `POST /api/rewards/noncash/cases` body `{"awardId":"<uuid>","versionId":"v-1","reason":"WRONG_ITEM"}` -> `data:{"caseId":"<uuid>","awardId":"<uuid>","state":"OPEN","reason":"WRONG_ITEM"}` (SYNTHETIC).

### G16 GET /api/rewards/noncash/cases/{caseId}
- Controller: ApiNonCashRewardAliasG16Controller.java:84
- Auth: token required; same flag/profile gating.
- Encoding: path only.
- Params: `caseId` path.
- Success shape: `data` = `{caseId, awardId, state, reason}`.
- Errors: envelope 404 NOT_FOUND (missing or other owner); 400 INVALID_INPUT.
- Idempotency/headers: none.
- iOS caller: Core/RewardPledge.swift:438 (GET cases + "/" + caseID); route classifier :91.
- SYNTHETIC example: `GET /api/rewards/noncash/cases/<uuid>` -> `data:{"caseId":"<uuid>","awardId":"<uuid>","state":"OPEN","reason":"WRONG_ITEM"}` (SYNTHETIC).

### G16 GET /api/rewards/noncash/{awardId}
- Controller: ApiNonCashRewardAliasG16Controller.java:92
- Auth: token required; same flag/profile gating.
- Encoding: path; iOS also sends query `contextType, contextId, releaseId, instanceId` which the alias IGNORES (be-g16-report).
- Params: `awardId` path. NOTE literal siblings `claims`, `cases`, `subjects`, `versions` have more-specific mappings.
- Success shape: `data` = awardView `{awardId, requestId, state, historyId, factRef, terms, termsHash, ruleVersion, redeemStart, redeemEnd, serviceEnd, guaranteed:false, blocked:"W06_RESERVATION_ABSENT", useStatus}` (:1000-1017). iOS expects a RewardWire with contextType/contextId/asOf etc. (Core/NonCashRewardService.swift:39-45) — field-level match UNKNOWN / likely mismatch (be-g16-report: "not checked field by field").
- Errors: envelope 404 NOT_FOUND (missing or beneficiary != caller).
- Idempotency/headers: none.
- iOS caller: Core/NonCashRewardService.swift:35 (`get(path:"api/rewards/noncash/"+awardId, query:[contextType,contextId,releaseId,instanceId])`); classifier Core/RewardPledge.swift:98.
- SYNTHETIC example: `GET /api/rewards/noncash/<awardId>?contextType=THEME&contextId=1234&releaseId=r1&instanceId=run1` -> `data:{"awardId":"<awardId>","requestId":"req-abc","state":"AWARDED","historyId":555,"factRef":"THEME:1234:session:77","guaranteed":false,"blocked":"W06_RESERVATION_ABSENT",...}` (SYNTHETIC).

---------------------------------------------------------------- G17  (ApiApprovedTopicReleaseG17Controller, class mapping `/api/approved-topic-release/v1` at :21)

Shared G17 facts: all 8 routes POST with `consumes="application/json"` (wrong Content-Type -> Spring HttpMediaTypeNotSupported, shape via global handler UNKNOWN), `@RequestBody String body` (raw text parsed by ApprovedTopicReleaseG17Codec.parse :41-52: size cap SMALL_BODY=4096 bytes / SOURCE_BODY=16384 bytes, must be a JSON object with EXACT key set (required + optional), duplicate keys/trailing tokens rejected -> 400 INVALID_REQUEST). Success: HTTP 200 `{code:200, msg:"OK", data:{...}}` (controller :50). Failure: HTTP status == code, body `{code:<status>, msg:"<CODE_STRING>"}` — the machine code is in `msg`, NO `errorCode` key, no `data` (controller :51-52). Unexpected RuntimeException -> HTTP 500 `{code:500,msg:"UNAVAILABLE"}` (:53-56). Unauthenticated/owner<=0 -> 401 `{code:401,msg:"AUTHENTICATION_REQUIRED"}` (:48-49; normally the security filter 401 fires first). Owner must own the topic (cms_topic.member_id) else 403 FORBIDDEN; topic missing 404 TOPIC_NOT_FOUND; productType != 1 -> 422 NOT_CITY_TOPIC; audit task missing 404 AUDIT_TASK_NOT_FOUND; task not bound to topic -> 409 REVIEW_CHANGED (service:372-407). Numeric fields must be JSON integers (not strings). `requestId` must be a 36-char UUID. Hashes are 64 lowercase hex chars. No feature flag/profile on this controller (no @Anonymous).

### G17 POST /api/approved-topic-release/v1/prepare
- Controller: ApiApprovedTopicReleaseG17Controller.java:26
- Auth: token required.
- Encoding: JSON raw body (`consumes=application/json`).
- Params: body EXACT keys `topicId` (int>0), `auditTaskId` (int>0).
- Success shape: `data` = `{contract:"questify.topic-release.text-city.v1", topicId, auditTaskId, auditTaskVersion:int, auditSnapshotHash:hex64, manifestHash:hex64, headRevision:long, sourceConfigVersion:long, name, description, categoryIds, currentlyApproved:true, releaseAllocated:false, secretValuesExcluded:true, chapters:[...]}` (service.prepared :283-317). `chapters` inner shape from Codec.releaseChapters (nodes have imgUrl:null) — fine-grained shape UNKNOWN beyond that. No `requestId`; read-only.
- Errors: 400 INVALID_REQUEST; 401; 403 FORBIDDEN; 404 TOPIC_NOT_FOUND / AUDIT_TASK_NOT_FOUND; 409 REVIEW_CHANGED (task.status != 1 i.e. not approved, or stored review snapshotHash != live hash, or no review link); 422 NOT_CITY_TOPIC / NOT_PUBLISHABLE / NODE_TEMPLATE_MISSING; 500 UNAVAILABLE.
- Idempotency/headers: none (pure read; locks audit task row FOR UPDATE).
- iOS caller: Core/ApprovedTopicReleaseDomain.swift:4 (const `prepare`), Core/ApprovedTopicReleasePreparationClient.swift:46; App/ApprovedReleaseCompositionRoute.swift:16.
- SYNTHETIC example: `POST /api/approved-topic-release/v1/prepare` body `{"topicId":100,"auditTaskId":55}` -> `{"code":200,"msg":"OK","data":{"contract":"questify.topic-release.text-city.v1","topicId":100,"auditTaskId":55,"auditTaskVersion":3,"auditSnapshotHash":"<64hex>","manifestHash":"<64hex>","headRevision":4,"sourceConfigVersion":4,"name":"City walk","description":"...","categoryIds":"1,2","currentlyApproved":true,"releaseAllocated":false,"secretValuesExcluded":true,"chapters":[...]}}` (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/publish
- Controller: ApiApprovedTopicReleaseG17Controller.java:28
- Auth: token required.
- Encoding: JSON raw body.
- Params: body EXACT keys `topicId` (int>0), `auditTaskId` (int>0), `auditTaskVersion` (int>=0), `auditSnapshotHash` (hex64), `expectedHeadRevision` (int>=0), `expectedManifestHash` (hex64), `requestId` (UUID).
- Success shape: `data` = receipt `{releaseId:long, topicId, sourceConfigVersion, auditTaskId, auditRecordId, auditTaskVersion, schemaVersion:1, manifestHash, auditSnapshotHash, currentlyApproved:bool}` (receiptOf :262-275). Releases are immutable records only; does NOT make topic public.
- Errors: 400 INVALID_REQUEST; 403 FORBIDDEN; 404 TOPIC_NOT_FOUND/AUDIT_TASK_NOT_FOUND/RELEASE_NOT_FOUND; 409 REVIEW_CHANGED (task version/hash/head/manifest mismatch, no audit record, or same requestId with different command hash); 422 NOT_PUBLISHABLE/NOT_CITY_TOPIC; 503 RELEASE_UNAVAILABLE; 500 UNAVAILABLE.
- Idempotency/headers: `requestId` + owner stored with sha256(canonical body) `commandHash`; replay returns receipt (with `currentlyApproved` recomputed live); different body -> 409 REVIEW_CHANGED. Release row unique by (topic, task, taskVersion, manifestHash).
- iOS caller: Core/ApprovedTopicReleasePublicationClient.swift:7 (const), :44 (`send(record, ..., path: publish)`); App/AppSession.swift:3984.
- SYNTHETIC example: `POST /api/approved-topic-release/v1/publish` body `{"topicId":100,"auditTaskId":55,"auditTaskVersion":3,"auditSnapshotHash":"<64hex>","expectedHeadRevision":4,"expectedManifestHash":"<64hex>","requestId":"3f2c1a9e-8b7d-4c11-9a55-0e1d2c3b4a5f"}` -> `data:{"releaseId":12,"topicId":100,"sourceConfigVersion":4,"auditTaskId":55,"auditRecordId":301,"auditTaskVersion":3,"schemaVersion":1,"manifestHash":"<64hex>","auditSnapshotHash":"<64hex>","currentlyApproved":true}` (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/status
- Controller: ApiApprovedTopicReleaseG17Controller.java:30
- Auth: token required.
- Encoding: JSON raw body.
- Params: same 7 keys as publish (identical PUBLISH key set).
- Success shape: same receipt as publish, `currentlyApproved` recomputed live (task.status==1, review link present, live manifest hash equals stored) (service:232-260).
- Errors: 404 RELEASE_NOT_FOUND (no prior request for owner+requestId, or release owner mismatch); 409 REVIEW_CHANGED (command hash differs); 400; 500 UNAVAILABLE.
- Idempotency/headers: read-only receipt by (owner, requestId).
- iOS caller: Core/ApprovedTopicReleasePublicationClient.swift:8, :47; App/AppSession.swift:3985.
- SYNTHETIC example: `POST /api/approved-topic-release/v1/status` same body as publish -> same receipt shape, e.g. `currentlyApproved:false` if task later changed (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/review/sources
- Controller: ApiApprovedTopicReleaseG17Controller.java:32
- Auth: token required.
- Encoding: JSON raw body.
- Params: body EXACT keys `topicId` (int>0), `observedAuditTaskId` (int>0).
- Success shape: `data` = `{contract:"questify.topic-release.merchant-source-choices.v1", templateIdNamespace:"CMS_MEMBER_TEMPLATE", currentness:"CONFIRMED_HISTORICAL_INPUTS", ownerMemberId, topicId, observedAuditTaskId, sourceConfigVersion, observedAuditTaskVersion, approvalProof:false, publicationAuthority:false, sources:[]}` — `sources` ALWAYS empty (no merchant source store; service:55-74).
- Errors: 400; 403; 404 TOPIC_NOT_FOUND/AUDIT_TASK_NOT_FOUND; 409 REVIEW_CHANGED (task not for this topic); 422 NOT_CITY_TOPIC; 500 UNAVAILABLE.
- Idempotency/headers: none (read).
- iOS caller: Core/ApprovedTopicReviewRequest.swift:4 (const), Core/ApprovedTopicReviewClient.swift:57 (`send(..., path: ApprovedTopicReviewPath.sources)`).
- SYNTHETIC example: `POST .../review/sources` body `{"topicId":100,"observedAuditTaskId":55}` -> `data:{"contract":"questify.topic-release.merchant-source-choices.v1","templateIdNamespace":"CMS_MEMBER_TEMPLATE","currentness":"CONFIRMED_HISTORICAL_INPUTS","ownerMemberId":42,"topicId":100,"observedAuditTaskId":55,"sourceConfigVersion":4,"observedAuditTaskVersion":3,"approvalProof":false,"publicationAuthority":false,"sources":[]}` (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/review/prepare
- Controller: ApiApprovedTopicReleaseG17Controller.java:34
- Auth: token required.
- Encoding: JSON raw body (16 KB cap).
- Params: required `topicId`, `observedAuditTaskId`; optional key `sourceSelections` — if PRESENT (any value) -> 422 MERCHANT_SOURCES_UNSUPPORTED.
- Success shape: `data` = `{contract:"questify.topic-release.review-preparation.v1", topicId, observedAuditTaskId, observedAuditTaskVersion:int, sourceConfigVersion:long, snapshotHash:hex64, approvalProof:false, releaseAllocated:false, summary:{...live topic summary + productType:1, publishMode:"pro", secretValuesExcluded:true, publicationEligibilityChecked:false}}` (service:76-99). Summary inner fields UNKNOWN (Codec.summary not fully read).
- Errors: 400; 403; 404; 409 REVIEW_CHANGED; 422 MERCHANT_SOURCES_UNSUPPORTED / NOT_CITY_TOPIC / NODE_TEMPLATE_MISSING; 500 UNAVAILABLE.
- Idempotency/headers: none (read).
- iOS caller: Core/ApprovedTopicReviewRequest.swift:5; Core/ApprovedTopicReviewClient.swift:65; Core/ApprovedTopicReviewRequestBody.swift:13.
- SYNTHETIC example: `POST .../review/prepare` body `{"topicId":100,"observedAuditTaskId":55}` -> `data:{"contract":"questify.topic-release.review-preparation.v1","topicId":100,"observedAuditTaskId":55,"observedAuditTaskVersion":3,"sourceConfigVersion":4,"snapshotHash":"<64hex>","approvalProof":false,"releaseAllocated":false,"summary":{...,"productType":1,"publishMode":"pro","secretValuesExcluded":true,"publicationEligibilityChecked":false}}` (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/review/submit
- Controller: ApiApprovedTopicReleaseG17Controller.java:36
- Auth: token required.
- Encoding: JSON raw body (16 KB cap).
- Params: required `topicId`, `observedAuditTaskId`, `observedAuditTaskVersion` (int>=0), `sourceConfigVersion` (int>=0), `snapshotHash` (hex64), `requestId` (UUID); optional `sourceSelections` (present -> 422 MERCHANT_SOURCES_UNSUPPORTED).
- Success shape: `data` = `{topicId, auditTaskId, sourceConfigVersion, submittedTaskVersion:int, submittedTaskStatus:int, snapshotHash, requestId, approvalProof:false, releaseAllocated:false}` (receipt :358-370). Side effect: freezes topic bundle and submits/refreshes the audit task (`auditTaskService.submitOrRefreshTopicBundle`).
- Errors: 400; 403; 404; 409 REVIEW_CHANGED (observed task version / config version / snapshot hash differ, or result not explainable, or same requestId with different selector); 422 NOT_SUBMITTABLE (RuntimeException from freeze/submit) / MERCHANT_SOURCES_UNSUPPORTED / NOT_CITY_TOPIC; 500 UNAVAILABLE.
- Idempotency/headers: (owner, requestId) row in review request table; replay (before and after lock) returns the same receipt if selector fields match, else 409 REVIEW_CHANGED. @Transactional.
- iOS caller: Core/ApprovedTopicReviewRequest.swift:6; Core/ApprovedTopicReviewClient.swift:72 (`receipt(record, ..., path: submit)`).
- SYNTHETIC example: body `{"topicId":100,"observedAuditTaskId":55,"observedAuditTaskVersion":3,"sourceConfigVersion":4,"snapshotHash":"<64hex>","requestId":"<uuid>"}` -> `data:{"topicId":100,"auditTaskId":55,"sourceConfigVersion":4,"submittedTaskVersion":4,"submittedTaskStatus":0,"snapshotHash":"<64hex>","requestId":"<uuid>","approvalProof":false,"releaseAllocated":false}` (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/review/status
- Controller: ApiApprovedTopicReleaseG17Controller.java:38
- Auth: token required.
- Encoding: JSON raw body (4 KB cap).
- Params: EXACT 6 keys (SELECTOR): `topicId`, `observedAuditTaskId`, `observedAuditTaskVersion`, `sourceConfigVersion`, `snapshotHash`, `requestId` (no sourceSelections allowed here).
- Success shape: same receipt as review/submit (replay of stored row) (service:149-154).
- Errors: 404 REVIEW_NOT_FOUND; 409 REVIEW_CHANGED (selector mismatch with stored); 400; 500 UNAVAILABLE.
- Idempotency/headers: read-only lookup by (owner, requestId).
- iOS caller: Core/ApprovedTopicReviewRequest.swift:7; Core/ApprovedTopicReviewClient.swift:75.
- SYNTHETIC example: same body as submit (SELECTOR keys) -> same receipt shape (SYNTHETIC).

### G17 POST /api/approved-topic-release/v1/review/current
- Controller: ApiApprovedTopicReleaseG17Controller.java:40
- Auth: token required.
- Encoding: JSON raw body (4 KB cap).
- Params: same 6 SELECTOR keys as review/status.
- Success shape: `data` = `{contract:"questify.topic-release.review-observation.v1", topicId, auditTaskId, requestId, submittedTaskVersion:int, observedTaskVersion:int, observedTaskStatus:int, submittedSnapshotHash, observedSnapshotHash, matchesSubmittedCapture:bool, approvalProof:false, releaseAllocated:false}` (service:156-181).
- Errors: 404 REVIEW_NOT_FOUND; 409 REVIEW_CHANGED; 403/404 topic ownership errors; 400; 500 UNAVAILABLE.
- Idempotency/headers: read-only; keyed by (owner, requestId).
- iOS caller: Core/ApprovedTopicReviewRequest.swift:8; Core/ApprovedTopicReviewClient.swift:49 (`send(record.command.readSelectorFields, ..., path: current)`).
- SYNTHETIC example: same SELECTOR body -> `data:{"contract":"questify.topic-release.review-observation.v1","topicId":100,"auditTaskId":55,"requestId":"<uuid>","submittedTaskVersion":4,"observedTaskVersion":4,"observedTaskStatus":0,"submittedSnapshotHash":"<64hex>","observedSnapshotHash":"<64hex>","matchesSubmittedCapture":true,"approvalProof":false,"releaseAllocated":false}` (SYNTHETIC).

---
# Part B: G18-G21
# Part B: G18-G21 routes (backend branch cloud/rt-02 = origin/claude/be-v2-fixes; iOS ref origin/wip/wave5-build)

Controller dir: `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/` (abbrev `C/`).

## COMMON FACTS (verified in code; referenced by the blocks below)
- **Envelope (AjaxResult, chengyinhub-common/.../core/domain/AjaxResult.java:53-61)**: a HashMap `{code:int, msg:string, data?:object}`; `data` is only put when non-null. `success(x)` = `{code:200,msg:"操作成功",data:x}`. `error(msg)` = code 500. `new AjaxResult(code,msg)` for non-200 codes passes `msg` through `UserSafeMessage.of` (AjaxResult.java:204), which replaces technical-looking or >120-char messages with "系统繁忙，请稍后重试". Extra top-level keys (`errorCode`, `err`) are put beside `code/msg`, NOT under `data`.
- **HTTP status**: every controller below except city-walking returns a bare `AjaxResult`, so business errors are HTTP 200 with the failure in `code` (no ResponseEntity, no status mapping found in the controllers; GlobalExceptionHandler only sets an HTTP status for NoResource/NoHandlerFound = 404, line 46). The G19 report's "404/403/409" for pledge are body `code` values, not HTTP statuses.
- **Auth (all 47 routes)**: none of these paths are in SecurityConfig permit-all (SecurityConfig.java:117-166 lists: login/register/captcha, static, swagger, `/api/common/**`, `/api/activity/list`, `/api/topic/list`, selected `/api/template/*` POSTs, GET `/api/official/events*`, merchant public-*, `/api/user/public-info`, GET `/api/roam/share/snapshot`, POST `/api/merchant/list`, etc.) and none of the 8 controllers carries `@Anonymous` (PermitAllUrlProperties scans for it; grep found none). So the final rule is `.anyRequest().authenticated()` (SecurityConfig.java:166) = **token required**. Inside handlers, `getAppUserId()` (BaseController.java:222) is the member id; when it throws, most handlers return `error("请先登录")` = `{code:500,msg:"请先登录"}`.
- **Rate limit** only on create-requests/submit (see block).
- **Not routed by these controllers**: `/api/im/webhook/inbound/{id}/{token}` (the URL string returned for endpoints) has no controller anywhere in chengyinhub-admin/src/main (grep), and would not be permit-all either. `PUT /api/im/members/{id}/roles` (iOS NativeChannelRoleFlow.swift:301) also has no controller in this group.

---
# G18

### G18 POST /api/activity/create-requests/submit
- Controller: C/ApiActivityCreateRequestG18Controller.java:37
- Auth: token required. FEATURE FLAG: class is `@ConditionalOnProperty(prefix="chengyin.activity-create-request-g18", name="enabled", havingValue="true", matchIfMissing=false)` (line 29): default-closed, whole controller absent (HTTP 404 via NoResourceFound) unless the property is true. No definition of the property in any application*.yml in the repo (grep).
- Encoding: JSON `@RequestBody Map<String,Object>` (no `consumes`).
- Params (body): `protocolVersion` string == "original-activity-create-request-v1" (required); `requestId` string lowercase UUID `[0-9a-f]{8}-...-{12}` (required); `payloadSHA256` string `[0-9a-f]{64}` (required); `payloadBase64Chunks` array of 1..86 non-empty strings each <=32768 chars, concatenated base64 must decode to 1..2,097,152 bytes (required); `merchantId`/`ownerId`/`actorId` must be absent or null (else rejected). SHA-256 of decoded bytes must equal `payloadSHA256`. No query/headers.
- Success shape: `{code:200,msg:"操作成功",data:{protocolVersion:string, requestId:string, payloadSHA256:string, merchantId:null, ownerId:null, actorId:null, state:string}}`; `state` is "RUNNING" for a new row; "COMMITTED" rows (never set by this controller; no commit step is wired, see comment lines 21-24) would add `originalResult:{activityId:long}`. It does NOT create an activity.
- Errors (all `{code:500,msg}` via `error()`): "请先登录" (line 41); "请求不合法" (43-47, 55: bad protocol/id/sha/unknown identity fields/bad chunks, or same requestId with different sha since `receipt()` returns null on sha mismatch, line 91); "请求摘要不匹配" (48); "请求过于频繁" (49: >=20 new rows in the last 24h per member, MAX_NEW_PER_DAY). `@RateLimiter(time=60,count=10,limitType=MEMBER)` (line 38) throws ServiceException "访问过于频繁，请稍候再试" -> handled as code 500.
- Idempotency/headers: key = (member_id from token, requestId) in table `activity_create_request_g18`; INSERT, `DuplicateKeyException` is swallowed and the stored receipt returned (replay) provided payload_sha256 matches. No header used (iOS test asserts no `Idempotency-Key` header is sent, Tests/CoreTests/PublishingModesTests.swift:138).
- iOS caller: path defined Core/ActivityCreateRequestContract.swift:5 (`submitPath`); also whitelisted in Core/BusinessRuntimeConfiguration.swift:332 (publishingWrite); exercised in Tests/CoreTests/PublishingModesTests.swift:138,141 and PublishingOriginalRequestRecoveryTests.swift:297. The non-test Swift file that builds the request from `submitPath` was not located (UNKNOWN).
- SYNTHETIC example:
  `POST /api/activity/create-requests/submit` body `{"protocolVersion":"original-activity-create-request-v1","requestId":"123e4567-e89b-12d3-a456-426614174000","payloadSHA256":"<64 hex of decoded bytes>","payloadBase64Chunks":["eyJhIjoxfQ=="]}`
  -> `{"code":200,"msg":"操作成功","data":{"protocolVersion":"original-activity-create-request-v1","requestId":"123e4567-e89b-12d3-a456-426614174000","payloadSHA256":"<same>","merchantId":null,"ownerId":null,"actorId":null,"state":"RUNNING"}}`

### G18 POST /api/activity/create-requests/read
- Controller: C/ApiActivityCreateRequestG18Controller.java:59
- Auth: token required; same ConditionalOnProperty gate as submit (closed by default). No RateLimiter.
- Encoding: JSON `@RequestBody Map`.
- Params (body): `protocolVersion` (== v1 constant), `requestId` (lowercase UUID), `payloadSHA256` (64 hex); all required.
- Success shape: `data` same fields as submit with `state`; if no row for (member, requestId) OR stored sha differs, returns `state:"NOT_FOUND"` (still code 200, no error). COMMITTED adds `originalResult:{activityId}`.
- Errors: `{code:500,msg:"请先登录"}`; `{code:500,msg:"请求不合法"}` for bad protocol/id/sha (lines 64-65).
- Idempotency/headers: read-only; scoped to token member.
- iOS caller: Core/ActivityCreateRequestContract.swift:6 (`readPath`); whitelisted Core/BusinessRuntimeConfiguration.swift:322 (publishingRead); tests PublishingOriginalRequestRecoveryTests.swift:105. Request builder file UNKNOWN.
- SYNTHETIC example: `POST /api/activity/create-requests/read` body `{"protocolVersion":"original-activity-create-request-v1","requestId":"123e4567-e89b-12d3-a456-426614174000","payloadSHA256":"<64 hex>"}` -> `{"code":200,"msg":"操作成功","data":{"protocolVersion":"original-activity-create-request-v1","requestId":"123e4567-e89b-12d3-a456-426614174000","payloadSHA256":"<64 hex>","merchantId":null,"ownerId":null,"actorId":null,"state":"NOT_FOUND"}}`

### G18 POST /api/activity/create-requests/resume-post-processing
- Controller: C/ApiActivityCreateRequestG18Controller.java:74
- Auth: token required; same ConditionalOnProperty gate (closed by default).
- Encoding: JSON `@RequestBody Map`.
- Params: identical to `/read` (it just calls `read(body)`, line 76).
- Success shape: identical to `/read` (stored receipt; nothing is resumed).
- Errors: identical to `/read`.
- Idempotency/headers: read-only.
- iOS caller: Core/ActivityCreateRequestContract.swift:7 (`resumePath`); BusinessRuntimeConfiguration.swift:332; tests PublishingOriginalRequestRecoveryTests.swift:231,343. Request builder UNKNOWN.
- SYNTHETIC example: same request body as `/read`; response same shape as `/read`.

### G18 POST /api/club/update
- Controller: C/ApiClubAdminG18Controller.java:38
- Auth: token required. No flag.
- Encoding: JSON `@RequestBody Club` (domain bean, Jackson binding).
- Params: delegates to `ApiClubController.updateMine(body)` (ApiClubController.java:504). Body = Club JSON; `id` selects club (must pass `clubMemberService.canGovernClub`); `name` required non-empty; whitelisted fields written: name, logo, cover, description, clubType, clubTypes, activityPrefs, city, keywords, style, categoryId, address, leaderName, phone; owner-only: `operationConfigUpdated=true` with prioritySignupEnabled (0|1), memberReservedQuota (>=0), memberDiscountPrice (>=0, <=2 decimals), and `joinPolicy` (0|1). Without `id` the first club of the member is used. Full Club field list: UNKNOWN (not read).
- Success shape: `{code:200,msg:"已保存",data:{joinPolicySupported:boolean, joinPolicy:int}}` (ApiClubController.java:~571).
- Errors (code 500 `error(msg)`): "请先登录"; "无权修改该俱乐部"; "你还不是俱乐部"; "只有主理人可以修改会员经营配置"; "只有主理人可以修改加入方式"; "请填写俱乐部名称"; operation-config validation texts; "加入方式仅支持公开或需审批"; content-security rejection text; IllegalArgument/IllegalState message from `updateOwnedClubProfile`.
- Idempotency/headers: none (plain overwrite).
- iOS caller: NONE for this exact path as a request: only listed as `nativeOnlyEndpoints: ["api/club/update"]` in Core/ChannelDiscordMessaging.swift:3029. iOS actually calls `api/club/update-mine` (Core/ClubOperationsContracts.swift:135; tests ClubOperationsTests.swift:139).
- SYNTHETIC example: `POST /api/club/update` body `{"id":81,"name":"Demo Club","description":"x"}` -> `{"code":200,"msg":"已保存","data":{"joinPolicySupported":true,"joinPolicy":0}}`

### G18 GET /api/club/workbench
- Controller: C/ApiClubAdminG18Controller.java:43 (`@RequestMapping(value="/workbench", method={GET,POST})`)
- Auth: token required.
- Encoding: query param (GET) or optional JSON body (`@RequestBody(required=false) Map`).
- Params: `clubId` Long query (optional); else body `clubId` (via Convert.toLong); one of them required, >0.
- Success shape: `data:{clubId:long, name:string, isOwner:boolean, canReadSettlement:boolean, pendingSettlementCount:int?, settledSettlementCount:int?}`; the two counts present only when `canReadSettlement` (FINANCE_READ via clubAccessService.resolve) is true; counted from `coopSettlementMapper.selectSummaryByBeneficiary("CLUB", clubId)` status 0 = pending, 1 = settled.
- Errors (code 500): "请先登录"; "缺少俱乐部信息"; "俱乐部不存在"; "仅主理人与管理员可进入工作台" (canGovernClub false).
- Idempotency/headers: none; read-only.
- iOS caller: NONE as a request; only `nativeOnlyEndpoints: ["api/club/workbench"]` in Core/ChannelDiscordMessaging.swift:3066.
- SYNTHETIC example: `GET /api/club/workbench?clubId=81` -> `{"code":200,"msg":"操作成功","data":{"clubId":81,"name":"Demo Club","isOwner":true,"canReadSettlement":true,"pendingSettlementCount":2,"settledSettlementCount":5}}`

### G18 POST /api/club/workbench
- Controller: C/ApiClubAdminG18Controller.java:43 (same method as the GET block)
- Auth / Encoding / Params / Success / Errors / Idempotency: identical to GET /api/club/workbench; POST body may be JSON `{"clubId":81}` (or query `clubId`).
- iOS caller: NONE (same as GET; Core/ChannelDiscordMessaging.swift:3066 definition only).
- SYNTHETIC example: `POST /api/club/workbench` body `{"clubId":81}` -> same response as GET example.

### G18 GET /api/club/settlements
- Controller: C/ApiClubAdminG18Controller.java:72
- Auth: token required.
- Encoding: query param or optional JSON body.
- Params: `clubId` (query, or body key), required >0.
- Success shape: `data:{clubId:long, readOnly:true, list:[{id:long, topicId:long, topicName:string, originalAmount:string(plain decimal), executedAdjustment:string, netAmount:string, status:"pending"|"settled"|"void"|"unknown", actualPaidAmount?:string|null (only when settled)}]}`. Amounts are strings (BigDecimal.toPlainString). status mapping: 1=settled, 2=void, null=unknown, else pending.
- Errors (code 500): "请先登录"; "缺少俱乐部信息"; "仅有财务查看权限的成员可查看结算" (ClubPermission.FINANCE_READ required, and principal/club must match the resolved context).
- Idempotency/headers: none; read-only.
- iOS caller: NONE as a request; listed in `nativeOnlyEndpoints` Core/ChannelDiscordMessaging.swift:3098.
- SYNTHETIC example: `GET /api/club/settlements?clubId=81` -> `{"code":200,"msg":"操作成功","data":{"clubId":81,"readOnly":true,"list":[{"id":9,"topicId":3,"topicName":"Demo","originalAmount":"100.00","executedAdjustment":"0","netAmount":"100.00","status":"pending"}]}}`

### G18 POST /api/club/settlements
- Controller: C/ApiClubAdminG18Controller.java:72 (same method)
- Auth/Encoding/Params/Success/Errors: identical to GET /api/club/settlements (POST body `{"clubId":81}` accepted).
- Idempotency/headers: none.
- iOS caller: NONE (definition only, ChannelDiscordMessaging.swift:3098).
- SYNTHETIC example: `POST /api/club/settlements` body `{"clubId":81}` -> same as GET example.

### G18 GET /api/club/settlements/export
- Controller: C/ApiClubAdminG18Controller.java:88
- Auth: token required.
- Encoding: query param or optional JSON body.
- Params: `clubId` required >0.
- Success shape: JSON (not a file stream) `data:{fileName:"club-{clubId}-settlements.csv", contentType:"text/csv; charset=utf-8", content:string}`; CSV header `settlementId,topicId,topicName,originalAmount,executedAdjustment,netAmount,status`; topicName quoted, values beginning `= + - @` get a `'` prefix (formula-injection guard, line ~259). Note `status` column is the mapped word (pending/settled/void/unknown).
- Errors (code 500): "请先登录"; "缺少俱乐部信息"; "仅有财务查看权限的成员可导出结算".
- Idempotency/headers: none.
- iOS caller: NONE as a request; listed Core/ChannelDiscordMessaging.swift:3098.
- SYNTHETIC example: `GET /api/club/settlements/export?clubId=81` -> `{"code":200,"msg":"操作成功","data":{"fileName":"club-81-settlements.csv","contentType":"text/csv; charset=utf-8","content":"settlementId,topicId,topicName,originalAmount,executedAdjustment,netAmount,status\n9,3,\"Demo\",100.00,0,100.00,pending\n"}}`

### G18 POST /api/club/settlements/export
- Controller: C/ApiClubAdminG18Controller.java:88 (same method)
- Auth/Encoding/Params/Success/Errors: identical to GET variant (POST body `{"clubId":81}`).
- Idempotency/headers: none.
- iOS caller: NONE (definition only, ChannelDiscordMessaging.swift:3098).
- SYNTHETIC example: `POST /api/club/settlements/export` body `{"clubId":81}` -> same as GET example.

### G18 GET /api/club/settings/notify-level
- Controller: C/ApiClubNotifyLevelG18Controller.java:29 (class mapping line 23)
- Auth: token required. No flag.
- Encoding: query params.
- Params: `clubId` String, required (parsed with Convert.toLong).
- Success shape: `data:{club_id:string, level:int, version:int|long, configured:boolean, updated_at:string|null}`. Unconfigured club returns `level:1, version:0, configured:false, updated_at:null`; otherwise stored values and `updated_at` formatted `yyyy-MM-ddTHH:mm:ssZ` (raw DB time labelled Z, no tz conversion in code).
- Errors (code 500): "请先登录"; "俱乐部不存在" (also when clubId unparsable); "无权查看该俱乐部通知默认值" (needs `canGovernClub`, i.e. owner/admin only, despite the class comment saying members may read).
- Idempotency/headers: none; read-only.
- iOS caller: Core/NativeChannelNotificationService.swift:137 (GET with `clubId` query); also Core/NativeChannelNotificationFinalForward.swift:91.
- SYNTHETIC example: `GET /api/club/settings/notify-level?clubId=81` -> `{"code":200,"msg":"操作成功","data":{"club_id":"81","level":1,"version":0,"configured":false,"updated_at":null}}`

### G18 POST /api/club/settings/notify-level
- Controller: C/ApiClubNotifyLevelG18Controller.java:40
- Auth: token required; `@Transactional`.
- Encoding: JSON `@RequestBody Map`.
- Params (body): `request_id` string `[A-Za-z0-9_-]{8,64}` (required); `clubId` (Convert.toLong, >0, required); `level` JSON number 0 or 1 (required, strings rejected); `version` JSON number >=0 (required; optimistic-lock base version).
- Success shape (always code 200 once validated): `data:{request_id, status:"APPLIED"|"REJECTED", operation:"CLUB_DEFAULT", scope_type:2, scope_id:string clubId, result_redacted:boolean (true iff REJECTED), must_refresh_state:true, outcome:status, result?:{version:long} (only APPLIED)}`. REJECTED = base version != current version (stale), returned as a normal 200 receipt, not an error.
- Errors (code 500): "请先登录"; "参数不合法"; "俱乐部不存在"; "无权修改该俱乐部通知默认值"; "请求编号已用于不同内容" (same request_id+club with different level/version); "请求并发冲突，请用同一请求编号重试" (DuplicateKey).
- Idempotency/headers: key = (club_id, request_id) in `club_notify_level_req_g18` with `SELECT ... FOR UPDATE`; replay returns stored status/applied_version. Not scoped by member. No headers.
- iOS caller: Core/NativeChannelNotificationService.swift:148 (`.clubDefault` -> path `api/club/settings/notify-level`, body from command); NativeChannelNotificationFinalForward.swift:111.
- SYNTHETIC example: `POST /api/club/settings/notify-level` body `{"request_id":"req-0001-abcd","clubId":81,"level":0,"version":0}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"req-0001-abcd","status":"APPLIED","operation":"CLUB_DEFAULT","scope_type":2,"scope_id":"81","result_redacted":false,"must_refresh_state":true,"outcome":"APPLIED","result":{"version":1}}}`

---
# G19

### G19 GET /api/reward-pledge/pledges
- Controller: C/ApiRewardPledgeG19Controller.java:38
- Auth: token required. FEATURE FLAG: `@ConditionalOnProperty(prefix="chengyin.pledge-v1", name="enabled", havingValue="true", matchIfMissing=false)` (line 25) + `PledgeV1Availability` (`chengyin.pledge-v1.enabled`, default false): default-closed, route absent (404) when off. Also requires merchant permission `COUPON_MANAGE` via `IMerchantAccessService.require(memberId, ...)` and a resolved merchant (store) id.
- Encoding: no params/body.
- Params: none (store/owner/principal come from the merchant access context).
- Success shape: `data:{pledges:[{pledge:<Pledge POJO>, versions:[<Version POJO>...]}]}`. Pledge/Version field names: UNKNOWN (serialised domain objects, not read; the pledge has at least pledgeId, storeId, merchantMemberId, couponId, quantity per usage in RewardPledgeService.java:1261+).
- Errors: inside `run()` (lines 99-109) `PledgeRejection(code)` -> `{code:404|403|400|409, msg:<errorString>}` per `code()` (lines 111-116: NOT_FOUND 404, FORBIDDEN 403, INVALID_INPUT/NOT_CONFIRM 400, everything else 409). BUT `availability.requireEnabled()` and `store()` (merchant check, `PledgeRejection("FORBIDDEN")`) run OUTSIDE `run()`, so they hit GlobalExceptionHandler.handleRuntimeException -> `{code:500,msg:"FORBIDDEN"}`. Merchant-access failure is a ServiceException `{code:403,msg:"商家身份无效或权限不足"}` (MerchantAccessServiceImpl.java:97-98).
- Idempotency/headers: read-only.
- iOS caller: Core/RewardPledge.swift:277 (`get("api/reward-pledge/pledges", ...)`); route classifier RewardPledge.swift:116.
- SYNTHETIC example: `GET /api/reward-pledge/pledges` -> `{"code":200,"msg":"操作成功","data":{"pledges":[{"pledge":{"pledgeId":"p-1"},"versions":[{"versionId":"v-1"}]}]}}` (inner objects abbreviated; real field set UNKNOWN)

### G19 GET /api/reward-pledge/review
- Controller: C/ApiRewardPledgeG19Controller.java:45
- Auth: token required; same flag gate; merchant permission `BASIC_READ`; additionally service requires policy `REVIEWER` OPEN and `policy.actorMemberId == principal`.
- Encoding: no params.
- Params: none.
- Success shape: `data:{store:long, items:[{pledgeId, versionId, payloadHash, state, store:long}]}` (confirmed versions in the store excluding the caller's own).
- Errors: as for /pledges; `PledgeRejection("POLICY_CLOSED")` -> `{code:409,msg:"POLICY_CLOSED"}`; FORBIDDEN (store/reviewer <=0) -> 403.
- Idempotency/headers: read-only.
- iOS caller: Core/RewardPledge.swift:280.
- SYNTHETIC example: `GET /api/reward-pledge/review` -> `{"code":200,"msg":"操作成功","data":{"store":7,"items":[{"pledgeId":"p-1","versionId":"v-1","payloadHash":"<sha256>","state":"CONFIRMED","store":7}]}}`

### G19 GET /api/reward-pledge/review/{versionId}
- Controller: C/ApiRewardPledgeG19Controller.java:52
- Auth: token required; same flag; `BASIC_READ`; REVIEWER policy as above.
- Encoding: path variable.
- Params: `versionId` String path, required (service `requireText`: non-blank, <=128 chars else INVALID_INPUT).
- Success shape: `data:{pledgeId, versionId, payloadHash, state, ruleVersion, version:<Version POJO>, owner:long, reviewer:long, reviewerHash, frozenAt, store:long}`.
- Errors: `{code:404,msg:"NOT_FOUND"}` (no such version); `{code:403,msg:"FORBIDDEN"}` (other store, or reviewer is the version's merchant member); `{code:409,msg:"POLICY_CLOSED"}`; `{code:400,msg:"INVALID_INPUT"}`.
- Idempotency/headers: read-only.
- iOS caller: Core/RewardPledge.swift:283.
- SYNTHETIC example: `GET /api/reward-pledge/review/v-1` -> `{"code":200,"msg":"操作成功","data":{"pledgeId":"p-1","versionId":"v-1","payloadHash":"<sha256>","state":"CONFIRMED","ruleVersion":"r1","version":{"versionId":"v-1"},"owner":501,"reviewer":502,"reviewerHash":null,"frozenAt":null,"store":7}}`

### G19 GET /api/reward-pledge/ops/{op}/{key}
- Controller: C/ApiRewardPledgeG19Controller.java:59
- Auth: token required; same flag; merchant permission `COUPON_MANAGE`.
- Encoding: path variables.
- Params: `op` String must be one of draft, submit, confirm, hold, withdraw, expire, return (else immediate `AjaxResult.error(404,"NOT_FOUND")`, checked before auth); `key` String non-blank <=128 (business key = pledgeId / versionId / awardId depending on op).
- Success shape: `data:{receipt:{op, key, state:"APPLIED"|"REJECTED", payloadHash, errorCode:string|null, pledgeId, versionId, awardId}}`.
- Errors: `{code:404,msg:"NOT_FOUND"}` when no op row or it belongs to a different store/owner/principal; `{code:400,msg:"INVALID_INPUT"}` bad key; 403 FORBIDDEN.
- Idempotency/headers: this is the receipt lookup for the idempotent ops.
- iOS caller: Core/RewardPledge.swift:409 (`readOp`, op allow-list identical at line 406); classifier RewardPledge.swift:109.
- SYNTHETIC example: `GET /api/reward-pledge/ops/hold/v-1` -> `{"code":200,"msg":"操作成功","data":{"receipt":{"op":"hold","key":"v-1","state":"APPLIED","payloadHash":"<sha256>","errorCode":null,"pledgeId":"p-1","versionId":"v-1","awardId":null}}}`

### G19 POST /api/reward-pledge/versions/{versionId}/hold
- Controller: C/ApiRewardPledgeG19Controller.java:67
- Auth: token required; same flag; merchant `COUPON_MANAGE`; service also requires policy `STORE_HOLD` OPEN (else `POLICY_CLOSED`).
- Encoding: no body, no query.
- Params: `versionId` String path (the version must exist and belong to the owner's pledge in this store; version state must be FROZEN).
- Success shape: `data:{pledge:<Pledge POJO>, version:<Version POJO>, stock:<Stock POJO>|null, conserved:boolean, guaranteed:false, receipt:{op:"hold", key:versionId, state:"APPLIED", payloadHash, errorCode:null, pledgeId, versionId, awardId:null}}` (RewardPledgeService.viewPledge 1020-1031, attach 1260). State change only.
- Errors: body `code`: 404 NOT_FOUND (no version), 403 FORBIDDEN (other store/owner), 409 CONFLICT (version not FROZEN, stock CAS fails, OR a second call for the same versionId: `decided(..., replay=false)` throws CONFLICT for an existing APPLIED op, RewardPledgeService.java:1187-1197), 409 POLICY_CLOSED; a stored REJECTED op re-throws its stored errorCode. Unwrapped rejections (flag/merchant check) -> code 500 as noted for /pledges.
- Idempotency/headers: no request-id header or body. Op row keyed by (op="hold", versionId) with payloadHash sha("hold|"+versionId); first call APPLIED, repeat call returns 409 CONFLICT rather than replaying the success.
- iOS caller: Core/RewardPledge.swift:426 (`post("api/reward-pledge/versions/<id>/hold")`); classifier RewardPledge.swift:122.
- SYNTHETIC example: `POST /api/reward-pledge/versions/v-1/hold` (no body) -> `{"code":200,"msg":"操作成功","data":{"pledge":{...},"version":{...},"stock":{...},"conserved":true,"guaranteed":false,"receipt":{"op":"hold","key":"v-1","state":"APPLIED","payloadHash":"<sha256>","errorCode":null,"pledgeId":"p-1","versionId":"v-1","awardId":null}}}`

### G19 POST /api/reward-pledge/versions/{versionId}/withdraw
- Controller: C/ApiRewardPledgeG19Controller.java:74
- Auth: token required; same flag; merchant `COUPON_MANAGE`. No STORE_HOLD policy check here.
- Encoding: no body, no query.
- Params: `versionId` String path.
- Success shape: same wrapper as hold with `receipt.op:"withdraw"`; side effect: version withdrawn and pledge state set to WITHDRAWN (service lines 276-300).
- Errors: 404 NOT_FOUND; 403 FORBIDDEN; 409 CONFLICT (`withdrawVersion`/`withdrawAvailable` not exactly 1 row, or repeat call for same versionId as with hold); stored REJECTED code re-thrown. SQL preconditions in the mapper XML: UNKNOWN (not read).
- Idempotency/headers: keyed by (op="withdraw", versionId); no header/body key; repeat call -> 409 CONFLICT.
- iOS caller: Core/RewardPledge.swift:429; classifier RewardPledge.swift:121.
- SYNTHETIC example: `POST /api/reward-pledge/versions/v-1/withdraw` -> `{"code":200,"msg":"操作成功","data":{"pledge":{...},"version":{...},"stock":{...},"conserved":true,"guaranteed":false,"receipt":{"op":"withdraw","key":"v-1","state":"APPLIED",...}}}`

### G19 GET /api/city/walking/target
- Controller: C/ApiCityWalkingG19Controller.java:19
- Auth: token required (default authenticated; not permit-all). The handler tolerates a missing user (member=0) which the service turns into 401. No feature flag.
- Encoding: query param.
- Params: `poi_id` long, required (query). Missing/non-numeric `poi_id` is a Spring binding error handled by GlobalExceptionHandler (exact result UNKNOWN; likely `{code:500,...}` HTTP 200).
- Success shape: **BARE JSON, no AjaxResult envelope** (HTTP 200, header `Cache-Control: private, no-store`): `{schemaVersion:1, kind:"cityNode", id:long poi, title:string, longitude:double, latitude:double, datum:"wgs84", region:"XX"(2 uppercase letters), authorityRevision:"city:{poi}:{uuid}", issuedAtMs:long, expiresAtMs:long (now + ttl*1000, ttl 1..300 s)}`. Coordinates are converted from the stored declared datum to WGS84 via IOrientGeoService.
- Errors: REAL HTTP status with AjaxResult body `{code:<status>,msg}` : 401 "请先登录" (member<=0); 400 "参数不合规" (poi<=0); 404 "据点未开放或已下线" (node missing/status!=1/no lat-lng) or "据点未开放步行导航" (no enabled declaration row in `city_walking_authority_g19`); 503 "步行导航声明无效" (bad region/ttl/uuid revision or datum conversion failure) (CityWalkingTargetG19Service.java:target).
- Idempotency/headers: none; response `Cache-Control: private, no-store`.
- iOS caller: Core/CityWalkingAuthorityReader.swift:36 (builds `api/city/walking/target` with `poi_id`), :72 (validates URL); tests CityWalkingV1ReaderTests.swift:58-64.
- SYNTHETIC example: `GET /api/city/walking/target?poi_id=7` -> HTTP 200 `{"schemaVersion":1,"kind":"cityNode","id":7,"title":"Demo POI","longitude":121.47,"latitude":31.23,"datum":"wgs84","region":"CN","authorityRevision":"city:7:123e4567-e89b-12d3-a456-426614174000","issuedAtMs":1762560000000,"expiresAtMs":1762560060000}`

---
# G20 (class `@RequestMapping("/api/im/roles")`, C/ApiImRoleG20Controller.java:27; all via `run()` lines 205-215)
Shared for G20: token required, no flag. Service: chengyinhub-system/.../service/im/g20/ImRoleG20Service.java. Club guild only (`guild_kind` must be 1 else 400 GUILD_INVALID). Errors from `ImRoleG20Exception` become `{code:<e.code 400|403|404|409>, msg:<Chinese>, errorCode:"<STABLE_CODE>"}` (errorCode top-level, not in data); `ServiceException` (e.g. club access) becomes `{code:e.code|500,msg}` with no errorCode; non-login throws from getAppUserId are NOT caught here (GlobalExceptionHandler, code 500). Mutations are idempotent per (token member, request_id): request_id regex `[A-Za-z0-9-]{8,64}` (lower-cased), stored with op + target + SHA-256 of body (sans request_id); same id+same op/target/body replays the stored JSON receipt; different -> 409 REQUEST_ID_REUSED; row without result -> 409 REQUEST_IN_PROGRESS. Mutation receipts add `request_id`, `state:"APPLIED"`, `audit_id:long`. Permission: `ClubPermission.ROLE_MANAGE` (else 403 MANAGE_ROLE_REQUIRED "无角色管理权限"); privilege-escalation guard (403 PERMISSION_ESCALATION / ROLE_HIERARCHY).

### G20 GET /api/im/roles
- Controller: C/ApiImRoleG20Controller.java:31
- Auth: token required.
- Encoding: query params.
- Params: `guild_kind` int required (==1); `guild_id` long required (>0); `include_disabled` boolean default false (honoured only for ROLE_MANAGE holders).
- Success shape: `data:{list:[RoleView], has_more:false, my_highest_position:int}`; RoleView = `{id:long, guild_kind:long, guild_id:long, version:string, name:string, permissions:string("0x..."), position:long, status:long, is_system, managed, is_everyone, hoist, mentionable (all long 0/1), color:long|null, display_level:string|null}`. `my_highest_position` is 0 for non-managers, else min(1000, rank).
- Errors: 400 GUILD_INVALID; 403 MANAGE_ROLE_REQUIRED if `clubAccess.resolve` returns null (non-member); 409 ROLE_LIST_TOO_LARGE (>500 roles).
- Idempotency/headers: read-only.
- iOS caller: Core/NativeChannelManagementService.swift:294; Core/NativeChannelRoleFlow.swift:130; Core/NativeChannelMentionTargets.swift:87; gating Core/BusinessRuntimeConfiguration.swift:156,182.
- SYNTHETIC example: `GET /api/im/roles?guild_kind=1&guild_id=42&include_disabled=false` -> `{"code":200,"msg":"操作成功","data":{"list":[{"id":17,"guild_kind":1,"guild_id":42,"version":"3","name":"Mod","permissions":"0x10","position":5,"status":1,"is_system":0,"managed":0,"is_everyone":0,"hoist":0,"mentionable":1,"color":null,"display_level":null}],"has_more":false,"my_highest_position":1001}}`

### G20 POST /api/im/roles
- Controller: C/ApiImRoleG20Controller.java:37
- Auth: token required.
- Encoding: JSON `@RequestBody Map`.
- Params (body): `request_id` (required); `guild_kind` ==1; `guild_id` >0; `reason` string 1..120 (required; checked before idempotency); `name` string trimmed 1..32 code points; `permissions` string `0x[0-9a-fA-F]{1,16}`; `hoist` and `mentionable` 0|1 (required, flag() rejects missing); `color` 0..0xFFFFFF optional; `display_level` string <=8 optional.
- Success shape: `data:` RoleView (newly inserted role) + `request_id`, `state:"APPLIED"`, `audit_id`.
- Errors: 400 REQUEST_ID_INVALID, GUILD_INVALID, REASON_REQUIRED, ROLE_NAME_INVALID, PERMISSIONS_INVALID, FLAG_INVALID, COLOR_INVALID, DISPLAY_LEVEL_INVALID, ID_INVALID; 403 MANAGE_ROLE_REQUIRED / PERMISSION_ESCALATION; 409 ROLE_NAME_TAKEN, REQUEST_ID_REUSED, REQUEST_IN_PROGRESS.
- Idempotency/headers: body `request_id` (see shared notes). No headers.
- iOS caller: Core/NativeChannelRoleFlow.swift:301 (`.create -> ("POST","api/im/roles")`); gating BusinessRuntimeConfiguration.swift:188.
- SYNTHETIC example: `POST /api/im/roles` body `{"request_id":"abcd1234-aa","guild_kind":1,"guild_id":42,"reason":"new mod role","name":"Mod","permissions":"0x10","hoist":0,"mentionable":1}` -> `{"code":200,"msg":"操作成功","data":{"id":17,"guild_kind":1,"guild_id":42,"version":"1","name":"Mod","permissions":"0x10","position":0,"status":1,"is_system":0,"managed":0,"is_everyone":0,"hoist":0,"mentionable":1,"color":null,"display_level":null,"request_id":"abcd1234-aa","state":"APPLIED","audit_id":88}}` (position/status values in the row are DB defaults: UNKNOWN)

### G20 PATCH /api/im/roles/{id}
- Controller: C/ApiImRoleG20Controller.java:42
- Auth: token required.
- Encoding: JSON body + path variable.
- Params: `id` long path (guild derived from stored role, never from body); body `request_id`, `reason` (1..120), `version` (compared as string to current version), `permissions` (0x hex, always required); for non-@everyone roles also required: `name`, `position` 0..999, `status` 0|1, `hoist`/`mentionable` 0|1, optional `color`.
- Success shape: RoleView of the updated role + `request_id`, `state`, `audit_id`.
- Errors: 400 ROLE_ID_INVALID, ROLE_POSITION_INVALID, ROLE_STATUS_INVALID, plus validators above; 404 ROLE_NOT_FOUND; 403 MANAGE_ROLE_REQUIRED, ROLE_HIERARCHY, PERMISSION_ESCALATION; 409 ROLE_PROTECTED (system/managed non-everyone), ROLE_VERSION_CONFLICT, ROLE_NAME_TAKEN, REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id` (op EDIT, target=id).
- iOS caller: Core/NativeChannelRoleFlow.swift:301; tests NativeChannelManagementRuntimeGateTests.swift:26.
- SYNTHETIC example: `PATCH /api/im/roles/17` body `{"request_id":"abcd1234-ab","reason":"rename","version":"1","permissions":"0x10","name":"Mod2","position":5,"status":1,"hoist":0,"mentionable":1}` -> `{"code":200,"msg":"操作成功","data":{"id":17,...,"version":"2","name":"Mod2","request_id":"abcd1234-ab","state":"APPLIED","audit_id":89}}`

### G20 DELETE /api/im/roles/{id}
- Controller: C/ApiImRoleG20Controller.java:47
- Auth: token required.
- Encoding: JSON `@RequestBody` on DELETE (required body; missing body = Spring HttpMessageNotReadable, result UNKNOWN). G20 report notes some proxies drop DELETE bodies.
- Params: `id` long path; body `request_id`, `reason` (1..120), `version` (string-compared).
- Success shape: `data:{id:long, deleted:true, revoked_grants:int, request_id, state:"APPLIED", audit_id}`.
- Errors: 404 ROLE_NOT_FOUND; 409 ROLE_PROTECTED (system/managed/@everyone), ROLE_VERSION_CONFLICT, REQUEST_ID_REUSED; 403 ROLE_HIERARCHY (position>=1000 or >= actor rank), MANAGE_ROLE_REQUIRED; 400 validators.
- Idempotency/headers: body `request_id` (op DELETE).
- iOS caller: Core/NativeChannelRoleFlow.swift:301 (`.delete -> ("DELETE","api/im/roles/"+target)`).
- SYNTHETIC example: `DELETE /api/im/roles/17` body `{"request_id":"abcd1234-ac","reason":"cleanup","version":"2"}` -> `{"code":200,"msg":"操作成功","data":{"id":17,"deleted":true,"revoked_grants":3,"request_id":"abcd1234-ac","state":"APPLIED","audit_id":90}}`

### G20 PUT /api/im/roles/{id}/members
- Controller: C/ApiImRoleG20Controller.java:52
- Auth: token required.
- Encoding: JSON body + path variable.
- Params: `id` long path; body `request_id`; `grant_reason` string 1..120 (required; NOT `reason`); `scope_type` "CHANNEL"|"GUILD"; `scope_id` id (must equal the guild id when scope GUILD); `member_ids` array of positive ids, <=500, no duplicates = COMPLETE replacement set for (role, scope); `expires_at` optional ISO-8601 Instant in the future.
- Success shape: `data:{role_id:long, added:[long], removed:[long], request_id, state:"APPLIED", audit_id}`.
- Errors: 404 ROLE_NOT_FOUND; 409 ROLE_PROTECTED, ROLE_DISABLED, MEMBER_NOT_IN_GUILD, REQUEST_ID_REUSED; 400 SCOPE_INVALID, MEMBER_IDS_INVALID, EXPIRES_INVALID, REASON_REQUIRED, ID_INVALID; 403 as above.
- Idempotency/headers: body `request_id` (op ROLE_MEMBERS).
- iOS caller: Core/NativeChannelRoleFlow.swift:301 (`.roleMembers -> ("PUT","api/im/roles/\(target)/members")`); tests NativeChannelManagementRuntimeGateTests.swift:27,136.
- SYNTHETIC example: `PUT /api/im/roles/17/members` body `{"request_id":"abcd1234-ad","grant_reason":"promote","scope_type":"GUILD","scope_id":42,"member_ids":[501,502]}` -> `{"code":200,"msg":"操作成功","data":{"role_id":17,"added":[501,502],"removed":[],"request_id":"abcd1234-ad","state":"APPLIED","audit_id":91}}`

---
# G21 moderation (class `@RequestMapping("/api/im/moderation")`, C/ApiImModerationG21Controller.java:24)
Shared: token required, no flag. Service impl: chengyinhub-system/.../service/impl/ImModerationG21ServiceImpl.java. Errors: `ServiceException` -> `fail()` (controller lines ~292-296) = `{code:<400|403|404|409>, msg:<Chinese>, err:"<STABLE_CODE>"}` (`err` top-level when the exception carries data); not logged in -> `{code:500,msg:"请先登录"}`. Permission: `ClubPermission.MEMBER_MANAGE` via `clubAccessService.require` (failure `{code:403,msg:"俱乐部身份无效或权限不足"}` with no `err`). Action wire (WIRE) = `{request_id, state:"APPLIED", replayed:boolean, guild_kind:"1", guild_id:string, action_id:string, target_member_id:string, action_type:"TIMEOUT"|"KICK"|"BAN"|"REVOKE", status:string("ACTIVE" for timeout/ban, "APPLIED" for kick/revoke; may become expired via expireStale), version:string, scope_type, scope_id:string, reason_text, expires_at:"yyyy-MM-dd HH:mm:ss.SSS"(Asia/Shanghai)|null, appeal_deadline:same|null, appealable:0|1, existing_appeal_id?:string, revoked_action_id?:string}`.

### G21 POST /api/im/moderation/timeout
- Controller: C/ApiImModerationG21Controller.java:28
- Auth: token required.
- Encoding: JSON `@RequestBody(required=false) Map` (null -> 400 MODERATION_BODY_REQUIRED).
- Params (body): `guild_kind` ==1 (number or numeric string); `guild_id` >0; `target_member_id` >0; `request_id` `^[A-Za-z0-9_-]{1,64}$`; `scope_type` must be "CHANNEL"; `scope_id` >0 (channel id; not verified against the guild in this code); `reason_code` `^[A-Z][A-Z0-9_]{1,31}$`; `reason_text` 1..500 chars; `duration_sec` int 60..2419200 (28d); `delete_message_sec` must be absent/0.
- Success shape: WIRE (see shared); first call `replayed:false`.
- Errors (`err` / code): GUILD_INVALID, GUILD_KIND_UNSUPPORTED, TARGET_INVALID, REQUEST_ID_INVALID, SCOPE_INVALID, REASON_CODE_INVALID, REASON_INVALID, DURATION_INVALID, DELETE_WINDOW_INVALID (all 400); TARGET_SELF 400; TARGET_PROTECTED 403 (owner, or peer/higher MEMBER_MANAGE holder unless actor is owner); REQUEST_ID_REUSED 409; MODERATION_ALREADY_ACTIVE 409; MODERATION_VERSION_CONFLICT 409. Note body validation runs before the permission check.
- Idempotency/headers: key (guild_id, principal, request_id) with row lock; same id + same type + same target -> returns stored action with `replayed:true`; different type/target -> 409 REQUEST_ID_REUSED. No headers.
- iOS caller: Core/NativeChannelModerationFlow.swift:135 (`path:"api/im/moderation/"+operation.rawValue`); gating BusinessRuntimeConfiguration.swift:202; tests NativeChannelManagementRuntimeGateTests.swift:20.
- SYNTHETIC example: `POST /api/im/moderation/timeout` body `{"guild_kind":1,"guild_id":42,"target_member_id":503,"request_id":"mod-0001","scope_type":"CHANNEL","scope_id":900,"reason_code":"SPAM","reason_text":"flooding","duration_sec":600}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"mod-0001","state":"APPLIED","replayed":false,"guild_kind":"1","guild_id":"42","action_id":"31","target_member_id":"503","action_type":"TIMEOUT","status":"ACTIVE","version":"0","scope_type":"CHANNEL","scope_id":"900","reason_text":"flooding","expires_at":"2026-11-08 12:10:00.000","appeal_deadline":"2026-11-15 12:00:00.000","appealable":1}}`

### G21 POST /api/im/moderation/kick
- Controller: C/ApiImModerationG21Controller.java:31
- Auth: token required.
- Encoding: JSON body (optional at binding level).
- Params (body): as timeout except `scope_type` must be "GUILD" and `scope_id` must equal `guild_id`; `duration_sec` must be exactly 0 and is still REQUIRED (missing -> DURATION_INVALID); `delete_message_sec` must be 0/absent.
- Success shape: WIRE with `action_type:"KICK"`, `status:"APPLIED"`, `expires_at:null`. The service only inserts an audit/action row (interface doc: "State and audit only"); actual membership removal is not performed in this service (UNKNOWN elsewhere).
- Errors: same set as timeout.
- Idempotency/headers: same (guild_id, principal, request_id).
- iOS caller: Core/NativeChannelModerationFlow.swift:135; BusinessRuntimeConfiguration.swift:202.
- SYNTHETIC example: `POST /api/im/moderation/kick` body `{"guild_kind":1,"guild_id":42,"target_member_id":503,"request_id":"mod-0002","scope_type":"GUILD","scope_id":42,"reason_code":"ABUSE","reason_text":"harassment","duration_sec":0}` -> `data:{...,"action_type":"KICK","status":"APPLIED","expires_at":null,"replayed":false}`

### G21 POST /api/im/moderation/ban
- Controller: C/ApiImModerationG21Controller.java:34
- Auth: token required.
- Encoding: JSON body.
- Params (body): as kick (`scope_type` "GUILD", `scope_id`==guild_id) but `duration_sec` 60..7776000 (90d); optional `delete_message_sec` 0..604800 (only allowed for BAN).
- Success shape: WIRE with `action_type:"BAN"`, `status:"ACTIVE"`, `expires_at` set.
- Errors: same set plus MODERATION_ALREADY_ACTIVE 409 when an ACTIVE same-type/scope sanction exists for the target.
- Idempotency/headers: same.
- iOS caller: Core/NativeChannelModerationFlow.swift:135; BusinessRuntimeConfiguration.swift:202.
- SYNTHETIC example: `POST /api/im/moderation/ban` body `{"guild_kind":1,"guild_id":42,"target_member_id":503,"request_id":"mod-0003","scope_type":"GUILD","scope_id":42,"reason_code":"SPAM","reason_text":"repeat","duration_sec":86400,"delete_message_sec":3600}` -> `data:{...,"action_type":"BAN","status":"ACTIVE",...}`

### G21 POST /api/im/moderation/{actionId}/revoke
- Controller: C/ApiImModerationG21Controller.java:37
- Auth: token required.
- Encoding: JSON body (optional at binding; null -> 400 MODERATION_BODY_REQUIRED) + path variable.
- Params: `actionId` Long path; body `request_id` (same regex), `reason` string non-blank <=500, `version` non-negative integer (string or number; CAS against action version). Guild is read from the stored action, not the client.
- Success shape: WIRE for the new REVOKE row: `action_type:"REVOKE"`, `status:"APPLIED"`, `revoked_action_id:string`, `appealable:0`, `appeal_deadline:null`, `expires_at:null`.
- Errors: 400 MODERATION_BODY_REQUIRED, REQUEST_ID_INVALID, REASON_INVALID, VERSION_INVALID; 404 MODERATION_NOT_FOUND; 409 MODERATION_NOT_REVOCABLE (only TIMEOUT/BAN), MODERATION_VERSION_CONFLICT (stale version), REQUEST_ID_REUSED; 403 TARGET_PROTECTED; 403 club permission.
- Idempotency/headers: (guild_id, principal, request_id); replay requires action_type REVOKE and same revoked_action_id, returns `replayed:true`.
- iOS caller: Core/NativeChannelModerationFlow.swift:143 (`path:"api/im/moderation/\(action.id)/revoke"`), :215 (validates body has string `version`, `reason`); gating NativeChannelManagementRuntimeGateTests.swift:66.
- SYNTHETIC example: `POST /api/im/moderation/31/revoke` body `{"request_id":"mod-0004","reason":"appeal ok","version":"0"}` -> `data:{"request_id":"mod-0004","state":"APPLIED","replayed":false,...,"action_type":"REVOKE","status":"APPLIED","revoked_action_id":"31","appealable":0,...}`

### G21 GET /api/im/moderation/actions
- Controller: C/ApiImModerationG21Controller.java:44
- Auth: token required; needs MEMBER_MANAGE on the guild.
- Encoding: query params.
- Params: `guild_kind` Integer required (must be 1, else `{code:400,msg:"仅支持俱乐部频道"}` with no `err`); `guild_id` Long required (>0); `limit` int optional default 20 range 1..50; `cursor` Long optional >0 (action id; pages go to older rows).
- Success shape: `data:{list:[WIRE...], has_more:boolean, next_cursor:string|null}` (`next_cursor` = last `action_id` of the page).
- Errors: 400 GUILD_INVALID, LIMIT_INVALID, CURSOR_INVALID (with `err`); 403 permission.
- Idempotency/headers: read-only (note it also runs `expireStale` writes).
- iOS caller: Core/NativeChannelModerationFlow.swift:109; gating BusinessRuntimeConfiguration.swift:195.
- SYNTHETIC example: `GET /api/im/moderation/actions?guild_kind=1&guild_id=42&limit=20` -> `{"code":200,"msg":"操作成功","data":{"list":[],"has_more":false,"next_cursor":null}}`

### G21 GET /api/im/moderation/me
- Controller: C/ApiImModerationG21Controller.java:54
- Auth: token required. No club-membership or permission check in the service (rows are filtered to the token member).
- Encoding: query params.
- Params: `guild_kind` Integer required (==1 else 400 without `err`); `guild_id` Long required (>0 else 400 GUILD_INVALID).
- Success shape: `data:{list:[WIRE...]}` (the caller's own sanction rows, max 50, `selectMine`).
- Errors: 400 as above; `{code:500,msg:"请先登录"}`.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeChannelAppealFlow.swift:207,235; Core/NativeChannelAppealRuntime.swift:92,154; gating BusinessRuntimeConfiguration.swift:217.
- SYNTHETIC example: `GET /api/im/moderation/me?guild_kind=1&guild_id=42` -> `{"code":200,"msg":"操作成功","data":{"list":[]}}`

---
# G21 webhook management (class `@RequestMapping("/api/im/webhook")`, C/ApiImWebhookG21Controller.java:26)
Shared: token required, no flag; all via `run()` (lines 413-418): not logged in -> `{code:500,msg:"请先登录"}`; `ServiceException` -> `fail()` = `{code,msg,err}` (err top-level). Service: chengyinhub-system/.../service/impl/ImWebhookG21ServiceImpl.java. Club-only: `owner_type` must be "CLUB" (400 OWNER_INVALID). Permission is `ClubPermission.ROLE_MANAGE` on `owner_id` (the string "im:webhook:manage" is only echoed in context). `{code:403,msg:"俱乐部身份无效或权限不足"}` on denial (no `err`). Webhook calls only manage rows: no outbound HTTP, no inbound receiver (G21 report item 4). Mutation idempotency: `request_id` in body (regex `^[A-Za-z0-9_-]{1,64}$`), key (principal, request_id) in a request table with body_hash; same id+same hash -> stored resource returned with `replayed:true` and `secret_shown_once:false` (secrets never re-shown); different -> 409 REQUEST_ID_REUSED; replay whose resource vanished -> 409 WEBHOOK_REPLAY_UNAVAILABLE. Optimistic lock: `revision` (positive int) must equal stored, else 409 REVISION_CONFLICT. Resource wire (RES) common: `{id:string, channel_id:string, owner_type:string, owner_id:string, name, status:0|1, deleted:boolean, revision:int, key_version:int, created_at, updated_at (yyyy-MM-dd HH:mm:ss.SSS Asia/Shanghai)}`; subscription adds `{url_host, events:[string], event_count:int, fail_count:long, last_error, last_delivery_at}`; endpoint adds `{avatar_url, token_prefix(6 chars), rate_limit_per_min:int, allowed_ips:[string], last_called_at}`. Known event ids: message.created, message.deleted, member.joined, member.left, moderation.action. List page shape (PAGE) = `{list:[...], has_more:boolean, next_cursor:string|null}`. All iOS callers below are via Core/NativeWebhookRuntimeRoute.swift (route builders, lines 8-24) and Core/NativeWebhookHTTPService.swift.

### G21 GET /api/im/webhook/context
- Controller: C/ApiImWebhookG21Controller.java:32
- Auth: token required; ROLE_MANAGE on owner.
- Encoding: query.
- Params: `owner_id` Long required (>0), `channel_id` Long required (>0). Channel is not verified to belong to the club in this code.
- Success shape: `data:{actor_id:string, owner_type:"CLUB", owner_id:string, channel_id:string, authorization_version:string(32 hex, sha256 of roles|permissions|owner), management_permission:"im:webhook:manage", event_revision:"g21-1", events:[{id:string,title:string}]}`.
- Errors: 400 OWNER_INVALID/CHANNEL_INVALID; 403 permission; 500 not logged in.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookScopeProvider.swift:192 (`api/im/webhook/context`); gating App/NativeWebhookRuntimeConfiguration.swift:14, Core/NativeWebhookFinalForwardTransport.swift:24.
- SYNTHETIC example: `GET /api/im/webhook/context?owner_id=42&channel_id=900` -> `{"code":200,"msg":"操作成功","data":{"actor_id":"501","owner_type":"CLUB","owner_id":"42","channel_id":"900","authorization_version":"<32 hex>","management_permission":"im:webhook:manage","event_revision":"g21-1","events":[{"id":"message.created","title":"新消息"}]}}`

### G21 GET /api/im/webhook/subscriptions
- Controller: C/ApiImWebhookG21Controller.java:38
- Auth: token required; ROLE_MANAGE.
- Encoding: query.
- Params: `owner_type` String required (must be "CLUB", else 400 err OWNER_INVALID); `owner_id` Long required; `channel_id` Long required; `limit` int optional default 20, 1..100; `cursor` Long optional >0.
- Success shape: PAGE of subscription RES.
- Errors: 400 OWNER_INVALID/CHANNEL_INVALID/LIMIT_INVALID/CURSOR_INVALID; 403.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:27 (`collection(family)` read with query).
- SYNTHETIC example: `GET /api/im/webhook/subscriptions?owner_type=CLUB&owner_id=42&channel_id=900` -> `{"code":200,"msg":"操作成功","data":{"list":[],"has_more":false,"next_cursor":null}}`

### G21 POST /api/im/webhook/subscriptions
- Controller: C/ApiImWebhookG21Controller.java:44
- Auth: token required; ROLE_MANAGE on `owner_id`.
- Encoding: JSON `@RequestBody(required=false) Map`.
- Params (body): `request_id`; `owner_type` "CLUB"; `owner_id` >0; `channel_id` >0; `revision` must be ABSENT (else 409 REVISION_CONFLICT); `name` 1..64; `status` 0|1 optional default 1; `events` array 1..32 unique known event ids; `url` required, https only, port 443 or none, no credentials/fragment, no IP literal/localhost/.local/.internal/dotless host, <=1024 chars.
- Success shape: `data:` subscription RES + `replayed:false, secret_shown_once:true, secret:string` (43-char base64url token; shown once; only its SHA-256 is stored).
- Errors: 400 WEBHOOK_BODY_REQUIRED, REQUEST_ID_INVALID, OWNER_INVALID, CHANNEL_INVALID, NAME_INVALID, STATUS_INVALID, EVENT_UNKNOWN, URL_REQUIRED, URL_INVALID; 409 REVISION_CONFLICT, REQUEST_ID_REUSED, WEBHOOK_CREATE_FAILED.
- Idempotency/headers: body `request_id`.
- iOS caller: Core/NativeWebhookHTTPService.swift:105 (create path = `collection(family)` when no original resource).
- SYNTHETIC example: `POST /api/im/webhook/subscriptions` body `{"request_id":"wh-0001","owner_type":"CLUB","owner_id":42,"channel_id":900,"name":"CI","events":["message.created"],"url":"https://hooks.example.com/in"}` -> `data:{"id":"5","channel_id":"900","owner_type":"CLUB","owner_id":"42","name":"CI","status":1,"deleted":false,"revision":1,"key_version":1,"created_at":"...","updated_at":"...","url_host":"hooks.example.com","events":["message.created"],"event_count":1,"fail_count":0,"last_error":null,"last_delivery_at":null,"replayed":false,"secret_shown_once":true,"secret":"<token>"}` (revision/key_version initial values assumed from DB defaults: UNKNOWN)

### G21 GET /api/im/webhook/subscriptions/{id}
- Controller: C/ApiImWebhookG21Controller.java:48
- Auth: token required; ROLE_MANAGE on the stored resource's owner.
- Encoding: path.
- Params: `id` Long path.
- Success shape: subscription RES.
- Errors: 400 WEBHOOK_ID_INVALID; 404 WEBHOOK_NOT_FOUND; 403.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:33.
- SYNTHETIC example: `GET /api/im/webhook/subscriptions/5` -> `data:{<subscription RES>}`

### G21 PUT /api/im/webhook/subscriptions/{id}
- Controller: C/ApiImWebhookG21Controller.java:50
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body (optional at binding; null -> 400 WEBHOOK_BODY_REQUIRED).
- Params: `id` path; body `request_id`, `revision` (positive int, required), `owner_type`/`owner_id`/`channel_id` (must equal stored, else 400 SCOPE_IMMUTABLE), `name` (required), `status` optional (keeps current if absent), `events` required, `url` optional (keeps current if absent; revalidated if sent).
- Success shape: updated subscription RES + `replayed:false` (no secret).
- Errors: 400 REVISION_INVALID, SCOPE_IMMUTABLE, NAME_INVALID, EVENT_UNKNOWN, URL_INVALID; 404 WEBHOOK_NOT_FOUND; 409 REVISION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id` + `revision`.
- iOS caller: Core/NativeWebhookHTTPService.swift:105 (resource path when `original` exists).
- SYNTHETIC example: `PUT /api/im/webhook/subscriptions/5` body `{"request_id":"wh-0002","revision":1,"owner_type":"CLUB","owner_id":42,"channel_id":900,"name":"CI2","events":["message.created","member.joined"]}` -> `data:{<RES with revision 2>,"replayed":false}`

### G21 DELETE /api/im/webhook/subscriptions/{id}
- Controller: C/ApiImWebhookG21Controller.java:54
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body on DELETE (optional at binding).
- Params: `id` path; body `request_id`, `revision` (positive int).
- Success shape: `data:` RES snapshot + `deleted:true, status:0, revision:<old+1>, updated_at, replayed:false`. Soft delete. Replay of a delete after the row is gone: `{id:string, deleted:true, status:0, revision:int, replayed:true}`.
- Errors: 400 REQUEST_ID_INVALID/REVISION_INVALID; 404 WEBHOOK_NOT_FOUND (no row and no prior request); 409 REVISION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id`; hash `DELETE|family+id|revision`.
- iOS caller: Core/NativeWebhookHTTPService.swift:117 (`method = .delete`).
- SYNTHETIC example: `DELETE /api/im/webhook/subscriptions/5` body `{"request_id":"wh-0003","revision":2}` -> `data:{<RES>,"deleted":true,"status":0,"revision":3,"updated_at":"...","replayed":false}`

### G21 POST /api/im/webhook/subscriptions/{id}/rotate-secret
- Controller: C/ApiImWebhookG21Controller.java:58
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body.
- Params: `id` path; body `request_id`, `revision`.
- Success shape: subscription RES + `replayed:false, secret_shown_once:true, old_token_invalid_after:string(time), secret:string` (new secret).
- Errors: 400 REQUEST_ID_INVALID/REVISION_INVALID; 404; 409 REVISION_CONFLICT/REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id`; a replay returns RES with `secret_shown_once:false` and no secret.
- iOS caller: Core/NativeWebhookHTTPService.swift:120; route Core/NativeWebhookRuntimeRoute.swift:17.
- SYNTHETIC example: `POST /api/im/webhook/subscriptions/5/rotate-secret` body `{"request_id":"wh-0004","revision":2}` -> `data:{<RES>,"replayed":false,"secret_shown_once":true,"old_token_invalid_after":"2026-11-08 12:00:00.000","secret":"<token>"}`

### G21 GET /api/im/webhook/subscriptions/{id}/deliveries
- Controller: C/ApiImWebhookG21Controller.java:62
- Auth: token required; ROLE_MANAGE.
- Encoding: query.
- Params: `id` path; `state` optional one of PENDING, INFLIGHT, SENT, FAILED, DEAD, UNKNOWN, CANCELLED; `include_payload` optional string, only "1" includes payloads; `limit` default 20, 1..100; `cursor` Long optional (not range-checked here).
- Success shape: PAGE of delivery `{id:string, delivery_id:string, event_id, event_type, state, attempt:int, reason, response_snippet, http_status, latency_ms, next_retry_at, created_at, payload_json?:object (only with include_payload=1)}`.
- Errors: 400 STATE_INVALID, LIMIT_INVALID; 404; 403.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:42; route NativeWebhookRuntimeRoute.swift:19.
- SYNTHETIC example: `GET /api/im/webhook/subscriptions/5/deliveries?state=FAILED&limit=20` -> `{"code":200,"msg":"操作成功","data":{"list":[],"has_more":false,"next_cursor":null}}`

### G21 POST /api/im/webhook/subscriptions/{id}/test
- Controller: C/ApiImWebhookG21Controller.java:69
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body.
- Params: `id` path; body `request_id`, `event_type` (must be one of the subscription's subscribed events, else 400 EVENT_UNKNOWN).
- Success shape: delivery wire with `payload_json` (`{test:true, event_type, subscription_id}`); creates a PENDING delivery row only (no outbound HTTP).
- Errors: 400 REQUEST_ID_INVALID, EVENT_UNKNOWN; 409 WEBHOOK_PAUSED (status != 1), REQUEST_ID_REUSED, WEBHOOK_REPLAY_UNAVAILABLE; 404.
- Idempotency/headers: body `request_id`; hash `TEST|id|event_type`; replay returns the same delivery.
- iOS caller: Core/NativeWebhookHTTPService.swift:127; route NativeWebhookRuntimeRoute.swift:21.
- SYNTHETIC example: `POST /api/im/webhook/subscriptions/5/test` body `{"request_id":"wh-0005","event_type":"message.created"}` -> `data:{"id":"77","delivery_id":"77","event_id":"<uuid>","event_type":"message.created","state":"PENDING","attempt":0,...,"payload_json":{"test":true,"event_type":"message.created","subscription_id":"5"}}`

### G21 POST /api/im/webhook/subscriptions/{id}/deliveries/{deliveryId}/retry
- Controller: C/ApiImWebhookG21Controller.java:73
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body.
- Params: `id`, `deliveryId` Long path; body `request_id`.
- Success shape: delivery wire with payload_json (requeued to PENDING).
- Errors: 404 DELIVERY_NOT_FOUND / WEBHOOK_NOT_FOUND; 409 WEBHOOK_PAUSED, DELIVERY_NOT_RETRYABLE, REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id`; hash `RETRY|id|deliveryId`.
- iOS caller: Core/NativeWebhookHTTPService.swift:131; route NativeWebhookRuntimeRoute.swift:22-24.
- SYNTHETIC example: `POST /api/im/webhook/subscriptions/5/deliveries/77/retry` body `{"request_id":"wh-0006"}` -> `data:{<delivery wire>,"state":"PENDING"}`

### G21 GET /api/im/webhook/endpoints
- Controller: C/ApiImWebhookG21Controller.java:79
- Auth: token required; ROLE_MANAGE.
- Encoding: query.
- Params: same as subscriptions list (`owner_type` "CLUB" required, `owner_id`, `channel_id`, `limit` 1..100 default 20, `cursor`).
- Success shape: PAGE of endpoint RES.
- Errors: as subscriptions list.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:27 (family endpoint).
- SYNTHETIC example: `GET /api/im/webhook/endpoints?owner_type=CLUB&owner_id=42&channel_id=900` -> `data:{"list":[],"has_more":false,"next_cursor":null}`

### G21 POST /api/im/webhook/endpoints
- Controller: C/ApiImWebhookG21Controller.java:85
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body (optional at binding).
- Params (body): `request_id`, `owner_type`="CLUB", `owner_id`, `channel_id`, `revision` absent, `name` 1..64, `status` optional, `rate_limit_per_min` int 1..300 (required), `allowed_ips` array <=32 of IPv4/IPv6 addresses or CIDRs (required, may be empty), `avatar_url` optional https URL.
- Success shape: endpoint RES + `replayed:false, secret_shown_once:true, url_shown_once:true, signing_secret:string, url:"https://<public-base>/api/im/webhook/inbound/{id}/{token}"` (public base = `chengyin.im.webhook.public-base-url` if https, else request server name/port). That inbound URL is not served by any controller found.
- Errors: 400 ENDPOINT_SETTINGS_REQUIRED, RATE_LIMIT_INVALID, ALLOWED_IPS_INVALID, URL_INVALID, NAME_INVALID, etc.; 409 REVISION_CONFLICT, REQUEST_ID_REUSED.
- Idempotency/headers: body `request_id`.
- iOS caller: Core/NativeWebhookHTTPService.swift:105.
- SYNTHETIC example: `POST /api/im/webhook/endpoints` body `{"request_id":"wh-0007","owner_type":"CLUB","owner_id":42,"channel_id":900,"name":"Bot","rate_limit_per_min":60,"allowed_ips":["203.0.113.0/24"]}` -> `data:{"id":"6",...,"token_prefix":"abc123","rate_limit_per_min":60,"allowed_ips":["203.0.113.0/24"],"replayed":false,"secret_shown_once":true,"url_shown_once":true,"signing_secret":"<token>","url":"https://api.example.com/api/im/webhook/inbound/6/<token>"}`

### G21 GET /api/im/webhook/endpoints/{id}
- Controller: C/ApiImWebhookG21Controller.java:89
- Auth: token required; ROLE_MANAGE.
- Encoding: path.
- Params: `id` Long.
- Success shape: endpoint RES.
- Errors: 400 WEBHOOK_ID_INVALID; 404 WEBHOOK_NOT_FOUND; 403.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:33.
- SYNTHETIC example: `GET /api/im/webhook/endpoints/6` -> `data:{<endpoint RES>}`

### G21 PUT /api/im/webhook/endpoints/{id}
- Controller: C/ApiImWebhookG21Controller.java:91
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body.
- Params: `id` path; body `request_id`, `revision`, immutable scope fields (`owner_type`, `owner_id`, `channel_id` equal to stored), `name`, optional `status`, `rate_limit_per_min` and `allowed_ips` both required (no carry-over), optional `avatar_url`.
- Success shape: updated endpoint RES + `replayed:false`.
- Errors: as subscription PUT plus RATE_LIMIT_INVALID, ALLOWED_IPS_INVALID, ENDPOINT_SETTINGS_REQUIRED.
- Idempotency/headers: body `request_id` + `revision`.
- iOS caller: Core/NativeWebhookHTTPService.swift:105.
- SYNTHETIC example: `PUT /api/im/webhook/endpoints/6` body `{"request_id":"wh-0008","revision":1,"owner_type":"CLUB","owner_id":42,"channel_id":900,"name":"Bot2","rate_limit_per_min":30,"allowed_ips":[]}` -> `data:{<RES revision 2>,"replayed":false}`

### G21 DELETE /api/im/webhook/endpoints/{id}
- Controller: C/ApiImWebhookG21Controller.java:95
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body on DELETE.
- Params: `id` path; body `request_id`, `revision`.
- Success shape: same as subscription DELETE.
- Errors: same as subscription DELETE.
- Idempotency/headers: body `request_id`.
- iOS caller: Core/NativeWebhookHTTPService.swift:117.
- SYNTHETIC example: `DELETE /api/im/webhook/endpoints/6` body `{"request_id":"wh-0009","revision":2}` -> `data:{<RES>,"deleted":true,"status":0,"revision":3,"replayed":false}`

### G21 POST /api/im/webhook/endpoints/{id}/rotate-token
- Controller: C/ApiImWebhookG21Controller.java:99
- Auth: token required; ROLE_MANAGE.
- Encoding: JSON body.
- Params: `id` path; body `request_id`, `revision`.
- Success shape: endpoint RES + `replayed:false, secret_shown_once:true, old_token_invalid_after, url_shown_once:true, signing_secret, url`.
- Errors: as rotate-secret.
- Idempotency/headers: body `request_id`; replay shows no secret/url.
- iOS caller: Core/NativeWebhookHTTPService.swift:120; route NativeWebhookRuntimeRoute.swift:17.
- SYNTHETIC example: `POST /api/im/webhook/endpoints/6/rotate-token` body `{"request_id":"wh-0010","revision":2}` -> `data:{<RES>,"replayed":false,"secret_shown_once":true,"old_token_invalid_after":"...","url_shown_once":true,"signing_secret":"<token>","url":"https://.../api/im/webhook/inbound/6/<token>"}`

### G21 GET /api/im/webhook/endpoints/{id}/logs
- Controller: C/ApiImWebhookG21Controller.java:103
- Auth: token required; ROLE_MANAGE.
- Encoding: query.
- Params: `id` path; `result` optional one of RECEIVED, PENDING_REVIEW, ACCEPTED, REJECTED, BLOCKED, RATE_LIMITED, UNKNOWN; `limit` default 20, 1..100; `cursor` Long optional.
- Success shape: PAGE of `{id:string, result, state(=result), reason, message_id:string|null, created_at, create_time, request_hash, nonce, endpoint_id:string, sender_type, webhook_id:string|null, original_message_stored:boolean|null}`. Stays empty in practice: no inbound receiver exists (G21 report item 4).
- Errors: 400 STATE_INVALID, LIMIT_INVALID; 404; 403.
- Idempotency/headers: read-only.
- iOS caller: Core/NativeWebhookHTTPService.swift:52; route NativeWebhookRuntimeRoute.swift:20.
- SYNTHETIC example: `GET /api/im/webhook/endpoints/6/logs?limit=20` -> `{"code":200,"msg":"操作成功","data":{"list":[],"has_more":false,"next_cursor":null}}`

---
# Part C: G22-G25
# Part C: G22-G25 routes (backend branch cloud/rt-02; iOS ref origin/wip/wave5-build)

Paths: CTRL = chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ ; SVC = chengyinhub-system/src/main/java/com/chengyinhub/business/service/ ; iOS paths relative to repo root of chengyin-app.

## Shared facts (verified)
- **Envelope**: AjaxResult extends HashMap (chengyinhub-common/.../AjaxResult.java). `success(data)` = `{code:200, msg:"操作成功", data:<payload>}`; payload IS under `data` (data key omitted when null). Errors: `{code:<n>, msg:<text>}` (+ top-level `errorCode` string for G23/G24 only, via `result.put("errorCode", detailMessage)`). For code != 200 `msg` passes through `UserSafeMessage.of` (AjaxResult.java:204): msgs >120 chars or containing `/api/`, class names, `token=` etc. are replaced by "系统繁忙，请稍后重试".
- **HTTP status**: no controller here sets an HTTP status; business refusals are returned as AjaxResult with HTTP 200 and the code in the body (code 400/403/404/409/415/503 etc. are BODY codes). Missing/mistyped @RequestParam or unparsable JSON body would be handled by framework/GlobalExceptionHandler (shape UNKNOWN, not read).
- **Auth (all 29 routes)**: no `@Anonymous`, no `@ConditionalOnProperty`/`@Profile`/feature flag on any of the 5 controllers (grep clean). SecurityConfig.java:117 permits only PermitAllUrlProperties urls (from @Anonymous) and the explicit lists at :123-163 (none contains /api/friend, /api/im, /api/join-request); :166 `anyRequest().authenticated()`. So every route below = **token required**. Member id from `getAppUserId()` (BaseController:222), never from client.
- G25 video routes additionally need a bean `ImVideoPipelineG25`; G24 file/appeal routes need beans `ImFileBlobStoreG24` / `ImFileScannerG24` / `ImFilePreviewSignerG24` / `ChannelModerationActionReaderG24`. grep finds NO implementation of any of these in the repo (interfaces only), so those paths answer 503 (see per-route notes).

---
## G22 (ApiFriendG22Controller, class `@RequestMapping("/api/friend")`; service SVC/friendg22/FriendG22Service.java)
Refusal -> `AjaxResult.error(code,msg)` with msg = the string constant (e.g. "INVALID_REQUEST"); when refusal carries data (remove) -> `{code,msg,data}` (CTRL:G22 lines 18-22).

### G22 POST /api/friend/request
- Controller: ApiFriendG22Controller.java:27 (-> FriendG22Service.request -> command(action="request"))
- Auth: token required (see shared)
- Encoding: JSON `@RequestBody Map<String,Object>`; no `consumes` set
- Params (body): `peer_id` long, required, >0 and != viewer; `request_id` string, required, lowercase-or-any-case UUID (validated `UUID.fromString(s).toString().equalsIgnoreCase(s)`, FriendG22Service:52); `msg` string required for request, trimmed non-empty, <=60 code points (missing msg => "" => 400); `expected_version` and `review_id` must be ABSENT for request; optional source set `source_type` int 1-4, `source_id` long>0, `source_generation` (required iff source_type==4, forbidden otherwise). Other keys ignored. (FriendG22Service:88-98)
- Success shape (data): `{viewer_id:long, peer_id:long, action:"request", request_id:string(lowercased), outcome:"PENDING_REVIEW"|"APPLIED", payload_hash:string(sha256 hex), relationship:{viewer_id,peer_id,state:int(0 none/1 friend/2 outgoing/3 incoming),version:long}, review?:{id:long,peer_id,request_id,state:"PENDING_REVIEW",version,msg,expires_at_ms:long}}` (:138-140). APPLIED (and no `review`) when peer had already requested me (auto-friend, :115). Pending TTL 7d (:15).
- Errors (all body-code; msg == string): 400 INVALID_REQUEST (:94-98); 404 MEMBER_UNAVAILABLE (:73); 409 ALREADY_FRIEND (:113), REQUEST_PENDING (:114), REQUEST_ID_CONFLICT (:104)
- Idempotency/headers: body `request_id` per viewer (table friend_command_g22 unique viewer_id+request_id, row locked FOR UPDATE :101). Same id+same intent hash+action+peer => stored receipt_json replayed; different => 409 REQUEST_ID_CONFLICT. No special headers.
- iOS caller: Core/NativeFriendService.swift:96-103 (`write` -> `exchange(command.action.rawValue ...)` builds "api/friend/"+suffix at :127-128; `writePaths` :14 lists request/accept/reject/cancel; POST JSON)
- SYNTHETIC example: `POST /api/friend/request` body `{"peer_id":1002,"request_id":"3f2b8c1e-5a4d-4e0a-9b1c-7d6e5f4a3b2c","msg":"hi"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1001,"peer_id":1002,"action":"request","request_id":"3f2b8c1e-5a4d-4e0a-9b1c-7d6e5f4a3b2c","outcome":"PENDING_REVIEW","payload_hash":"<sha256>","relationship":{"viewer_id":1001,"peer_id":1002,"state":2,"version":1},"review":{"id":77,"peer_id":1002,"request_id":"3f2b8c1e-...","state":"PENDING_REVIEW","version":1,"msg":"hi","expires_at_ms":1763000000000}}}`

### G22 POST /api/friend/remove
- Controller: ApiFriendG22Controller.java:31
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `peer_id` long >0 !=viewer; `expected_version` long >0 (<Long.MAX); `request_id` UUID string (FriendG22Service:161-162)
- Success shape (data): `{viewer_id, peer_id, expected_version, request_id, action:"remove", payload_hash, outcome:"APPLIED", reason:"REMOVED", removed_version:long(=expected+1), current_relationship:{viewer_id,peer_id,state,version}}` (:182-183)
- Errors: 400 INVALID_REQUEST (:162); 409 REQUEST_ID_CONFLICT (:167); not-friend => code 404 msg "NOT_FRIEND" with `data`=REJECTED receipt `{...,outcome:"REJECTED",reason:"NOT_FRIEND",current_relationship}`; version mismatch => code 409 msg "VERSION_CONFLICT" with data likewise (:175-179); replay of a stored REJECTED => 409 msg "REMOVAL_REJECTED" with data (:169). Rejected receipts are stored (dedupe).
- Idempotency/headers: body `request_id`; friend_command_g22 (viewer_id, request_id), hash = sha256("friend-removal-v1\n"+peer+"\n"+ev) (:49); no headers.
- iOS caller: Core/NativeFriendRemovalService.swift:13 (removePath) used at :55 `send(command, path: removePath)`
- SYNTHETIC example: `POST /api/friend/remove` `{"peer_id":1002,"expected_version":3,"request_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"}` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1001,"peer_id":1002,"expected_version":3,"request_id":"aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee","action":"remove","payload_hash":"<sha256>","outcome":"APPLIED","reason":"REMOVED","removed_version":4,"current_relationship":{"viewer_id":1001,"peer_id":1002,"state":0,"version":4}}}`

### G22 GET /api/friend/requests
- Controller: ApiFriendG22Controller.java:35
- Auth: token required
- Encoding: query params (no body)
- Params: `cursor` long REQUIRED (no default; >=0); `limit` int REQUIRED (1..100, effective page = min(limit,50)); `review_cursor` long optional (default 0, >=0), param name `review_cursor`
- Success shape (data): `{viewer_id:long, incoming:[{peer_id,nickname,state:3,version,msg,expires_at_ms}], outgoing:[{...state:2}], friends:[] (always empty), has_more:bool, next_cursor:long|null, reviews:[{id,peer_id,request_id,state:"PENDING_REVIEW",version,msg,expires_at_ms}], review_has_more:bool, review_next_cursor:long|null}` (:202-213). Only pending (state=2, unexpired) pair rows; no friend list here.
- Errors: 400 INVALID_REQUEST when cursor<0, limit<1 or >100, review_cursor<0 (:190,:204). Missing required param => framework 400 (shape UNKNOWN).
- Idempotency/headers: none (read)
- iOS caller: Core/NativeFriendService.swift:53 (`page(requests:true...)` GET "api/friend/requests" with cursor,limit) and :70 (review_cursor)
- SYNTHETIC example: `GET /api/friend/requests?cursor=0&limit=50` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1001,"incoming":[{"peer_id":1003,"nickname":"小明","state":3,"version":1,"msg":"hello","expires_at_ms":1763000000000}],"outgoing":[],"friends":[],"has_more":false,"next_cursor":null,"reviews":[],"review_has_more":false,"review_next_cursor":null}}`

### G22 GET /api/friend/team-invite/picker
- Controller: ApiFriendG22Controller.java:40
- Auth: token required
- Encoding: query params
- Params: `team_id` long REQUIRED; `section` string REQUIRED, one of together|recent|all; `cursor` string optional, regex ^[0-9]{1,18}$ (FriendG22Service:219)
- Success shape (data): `{viewer_id, section, starred_only:false, revision:string(sha256), groups:{viewer_id,list:[{id:0,name:"默认",position:0,version:0,is_default:1}]}, counts:{all:int,recent:0,together:0}, total:int, items:[{peer_id,nickname,state:1,version,msg:"",expires_at_ms:0,already_member:bool}], has_more:bool, next_cursor:string|null, team_id:string, name:string}`; for section != "all" `items` is forced [] , has_more false, next_cursor null (:240). Friends of viewer only (state=1), page 50.
- Errors: 400 INVALID_REQUEST (:219); 403 NOT_TEAM_LEADER (viewer must be play_team.leader_member_id, :221)
- Idempotency/headers: none
- iOS caller: Core/NativeFriendTeamInviteService.swift:40 (`picker`, prefix defined :7)
- SYNTHETIC example: `GET /api/friend/team-invite/picker?team_id=9&section=all` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1001,"section":"all","starred_only":false,"revision":"<sha256>","groups":{"viewer_id":1001,"list":[{"id":0,"name":"默认","position":0,"version":0,"is_default":1}]},"counts":{"all":1,"recent":0,"together":0},"total":1,"items":[{"peer_id":1002,"nickname":"阿花","state":1,"version":2,"msg":"","expires_at_ms":0,"already_member":false}],"has_more":false,"next_cursor":null,"team_id":"9","name":"夜跑队"}}`

### G22 GET /api/friend/team-invite/landing
- Controller: ApiFriendG22Controller.java:44
- Auth: token required
- Encoding: query params
- Params: `offer_id` string REQUIRED, must be lowercase canonical UUID (:259)
- Success shape (data): `{viewer_id, offer_id, team_id:string, name:string(<=200), state:string (value of friend_team_offer_g22.state; known: "WAITING_CONFIRM"), recipient:bool, can_act:bool(recipient && state=="WAITING_CONFIRM"), join_mode:int, inviter?:{peer_id,nickname,state:1,version,msg:"",expires_at_ms:0}}` (inviter only when viewer is recipient) (:249-254)
- Errors: 400 INVALID_REQUEST (:259); 404 OFFER_UNAVAILABLE (no offer for viewer as recipient/inviter :261, or recipient and inviter no longer friends :253)
- Idempotency/headers: none
- iOS caller: Core/NativeFriendTeamInviteService.swift:51 (`landing`)
- SYNTHETIC example: `GET /api/friend/team-invite/landing?offer_id=0b9a6c7e-1d2f-4a3b-8c4d-5e6f7a8b9c0d` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1002,"offer_id":"0b9a6c7e-1d2f-4a3b-8c4d-5e6f7a8b9c0d","team_id":"9","name":"夜跑队","state":"WAITING_CONFIRM","recipient":true,"can_act":true,"join_mode":0,"inviter":{"peer_id":1001,"nickname":"阿明","state":1,"version":2,"msg":"","expires_at_ms":0}}}`

### G22 GET /api/friend/team-invite/mine
- Controller: ApiFriendG22Controller.java:48
- Auth: token required
- Encoding: query params
- Params: `before` string REQUIRED, regex ^[0-9]{1,18}$ ("0" = first page) (:265)
- Success shape (data): `{viewer_id, items:[<same offer view as landing>], next_before:string ("0" when no more)}`; offers whose inviter is no longer a friend are silently dropped (:270). Page 50.
- Errors: 400 INVALID_REQUEST
- Idempotency/headers: none
- iOS caller: Core/NativeFriendTeamInviteService.swift:55 (`mine(before:)`)
- SYNTHETIC example: `GET /api/friend/team-invite/mine?before=0` -> `{"code":200,"msg":"操作成功","data":{"viewer_id":1001,"items":[],"next_before":"0"}}`

---
## G23 (ApiImChainG23Controller, `@RequestMapping("/api/im/chain")`; service SVC/impl/ImChainG23ServiceImpl.java)
Errors for all G23 routes: ServiceException -> `{code:e.code, msg, errorCode:<detailMessage>}` (CTRL ApiImChainG23Controller:59-63); other exceptions -> `{code:500,msg:"操作失败，请稍后重试"}`. Group-chat gate `imService.requireActiveGroupMembership` (ImServiceImpl:1143) may throw ServiceException without errorCode: 401 "请先登录并选择群聊", 403 (IM member row missing, "无权操作该群聊"), 404 "群聊不存在或已结束" (conversation not an active GROUP), 403 "已退出群聊，无权操作投票".
Write routes share `apply()`; ALL keys are camelCase.

### G23 POST /api/im/chain/create
- Controller: ApiImChainG23Controller.java:23
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `operation` string REQUIRED must equal "CREATE" (case-insens.) else 400 INVALID_REQUEST; `requestId` lowercase UUID REQUIRED; `conversationId` positive long (number or canonical digit string) REQUIRED; `title` string REQUIRED: non-empty, trimmed, <=200 code points, no `<` `&` NUL; `maxSlots` integer JSON number REQUIRED >=0 (0 = unlimited); `deadlineAt` long ms optional (0..253402300799000); `chainId` and `content` must be ABSENT/null (ImChainG23ServiceImpl:37-62). Title also passes `imService.checkUserGeneratedText`.
- Success shape (data, receipt): `{source:"original-channel-chain-request-v1", actorId:string, conversationId:string, requestId, state:"APPLIED", operation:"CREATE", requestHash:string(sha256), resultRedacted:false, result:{chainId:string,messageId:string,creatorMemberId:string,chainVersion:string,status:"OPEN",activeCount:0}}` (:97-103,171-179). Side effect: posts IM message msgType 14 "[接龙] <title>" with card extra JSON (:114).
- Errors (code/errorCode): 401 UNAUTHORIZED; 400 INVALID_REQUEST; 409 CHAIN_CARD_FAILED (:116); 409 REQUEST_IN_PROGRESS (dup-key race :84); 409 REQUEST_ID_REUSED (:91); plus group-gate errors above.
- Idempotency/headers: body `requestId` stored with (conversationId, memberId, requestId) + requestHash (digest "chain-v1", length-prefixed, :246); replay returns stored result in a fresh receipt; same id different hash => 409 REQUEST_ID_REUSED. No headers.
- iOS caller: Core/NativeChannelChain.swift:34 (`path` = "api/im/chain/"+op.lowercased()), POST at :235; runtime allow-list Core/BusinessRuntimeConfiguration.swift:234
- SYNTHETIC example: `POST /api/im/chain/create` `{"operation":"CREATE","requestId":"11111111-2222-4333-8444-555555555555","conversationId":"501","title":"周六约饭","maxSlots":10}` -> `{"code":200,"msg":"操作成功","data":{"source":"original-channel-chain-request-v1","actorId":"1001","conversationId":"501","requestId":"11111111-2222-4333-8444-555555555555","state":"APPLIED","operation":"CREATE","requestHash":"<sha256>","resultRedacted":false,"result":{"chainId":"31","messageId":"9001","creatorMemberId":"1001","chainVersion":"0","status":"OPEN","activeCount":0}}}` (chainVersion initial value UNKNOWN: depends on DB default)

### G23 POST /api/im/chain/join
- Controller: ApiImChainG23Controller.java:26
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `operation`="JOIN"; `requestId` lowercase UUID; `conversationId`; `chainId` positive long REQUIRED; `content` string REQUIRED (non-empty, trimmed, <=2000 cp, no `<` `&` NUL; also checkUserGeneratedText); `title`,`maxSlots`,`deadlineAt` must be ABSENT
- Success shape (data): receipt as create, `operation:"JOIN"`, `result:{chainId,messageId,creatorMemberId,chainVersion,status,activeCount:int, entry:{id,chainId,memberId,position,version (all strings), status:"ACTIVE", content}}` (:139, entryView :182-189)
- Errors: 404 CHAIN_NOT_FOUND (chain missing or other conversation, :166); 409 CHAIN_CLOSED (:123); 409 CHAIN_EXPIRED (:124); 409 ALREADY_JOINED (:128); 409 CHAIN_FULL (:129); 409 CHAIN_CONFLICT (:136); 400 INVALID_REQUEST; 409 REQUEST_ID_REUSED / REQUEST_IN_PROGRESS; chain row locked FOR UPDATE; re-join after withdraw gets new position (:130-137)
- Idempotency/headers: same as create (`requestId` in body)
- iOS caller: Core/NativeChannelChain.swift:34/235 (same templated path), allow-list BusinessRuntimeConfiguration.swift:235
- SYNTHETIC example: `POST /api/im/chain/join` `{"operation":"JOIN","requestId":"22222222-2222-4333-8444-555555555555","conversationId":"501","chainId":"31","content":"我+1"}` -> `{"code":200,"msg":"操作成功","data":{"source":"original-channel-chain-request-v1","actorId":"1002","conversationId":"501","requestId":"2222...","state":"APPLIED","operation":"JOIN","requestHash":"<sha256>","resultRedacted":false,"result":{"chainId":"31","messageId":"9001","creatorMemberId":"1001","chainVersion":"1","status":"OPEN","activeCount":1,"entry":{"id":"5","chainId":"31","memberId":"1002","position":"1","version":"0","status":"ACTIVE","content":"我+1"}}}}`

### G23 POST /api/im/chain/withdraw
- Controller: ApiImChainG23Controller.java:29
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `operation`="WITHDRAW"; `requestId`; `conversationId`; `chainId` REQUIRED; `title`,`maxSlots`,`deadlineAt`,`content` must be ABSENT
- Success shape (data): receipt, `operation:"WITHDRAW"`, result as join but `entry` present with `status` != ACTIVE and NO `content` key (content only emitted when ACTIVE, :188); activeCount = current count
- Errors: 404 CHAIN_NOT_FOUND; 409 CHAIN_CLOSED (:144, status must be OPEN; note expiry not checked); 409 NOT_JOINED (:148); 400 INVALID_REQUEST; 409 REQUEST_ID_REUSED / REQUEST_IN_PROGRESS
- Idempotency/headers: same
- iOS caller: Core/NativeChannelChain.swift:34/235; allow-list BusinessRuntimeConfiguration.swift:236
- SYNTHETIC example: `POST /api/im/chain/withdraw` `{"operation":"WITHDRAW","requestId":"33333333-2222-4333-8444-555555555555","conversationId":"501","chainId":"31"}` -> data.result `{"chainId":"31","messageId":"9001","creatorMemberId":"1001","chainVersion":"2","status":"OPEN","activeCount":0,"entry":{"id":"5","chainId":"31","memberId":"1002","position":"1","version":"1","status":"WITHDRAWN"}}` (withdrawn status literal UNKNOWN; set by mapper SQL not read)

### G23 POST /api/im/chain/close
- Controller: ApiImChainG23Controller.java:32
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `operation`="CLOSE"; `requestId`; `conversationId`; `chainId` REQUIRED; others ABSENT
- Success shape (data): receipt `operation:"CLOSE"`, `result:{chainId,messageId,creatorMemberId,chainVersion,status (closed value set by mapper.closeChain, literal UNKNOWN),activeCount}` no `entry`
- Errors: 403 NOT_CREATOR (:157); 409 CHAIN_CLOSED (:159); 404 CHAIN_NOT_FOUND; 400 INVALID_REQUEST; 409 REQUEST_ID_REUSED / REQUEST_IN_PROGRESS
- Idempotency/headers: same
- iOS caller: Core/NativeChannelChain.swift:34/235; allow-list BusinessRuntimeConfiguration.swift:237
- SYNTHETIC example: `POST /api/im/chain/close` `{"operation":"CLOSE","requestId":"44444444-2222-4333-8444-555555555555","conversationId":"501","chainId":"31"}` -> `{"code":200,"msg":"操作成功","data":{...,"operation":"CLOSE","result":{"chainId":"31","messageId":"9001","creatorMemberId":"1001","chainVersion":"3","status":"CLOSED","activeCount":2}}}` (status literal "CLOSED" is a guess: UNKNOWN)

### G23 GET /api/im/chain/info
- Controller: ApiImChainG23Controller.java:35
- Auth: token required
- Encoding: query params
- Params: `conversation_id` string (positive canonical long) REQUIRED in practice (null => INVALID_REQUEST; annotation required=false); `chain_id` same; `cursor` optional numeric string (>=0, default 0 = position cursor); `limit` optional numeric string (default 50, >=1, capped at 50)
- Success shape (data): `{source:"original-channel-chain-v1", chain:{id:string,conversationId:string,messageId:string,creatorMemberId:string,title,status,version:string,maxSlots:int,activeCount:int,deadlineAt:long|null,accepting:bool,canParticipate:bool(=open),canClose:bool(open&&creator)}, list:[entry{id,chainId,memberId,position,version,status,content} (strings)], mine?:entry, hasMore:bool, nextCursor?:string(position of last list item; present only if hasMore)}` (:221-237). Lists ACTIVE entries only.
- Errors: 401 UNAUTHORIZED; 400 INVALID_REQUEST (bad/ missing params, non-numeric cursor/limit :203,:205); 404 CHAIN_NOT_FOUND; group-gate errors (no errorCode); unexpected -> code 500
- Idempotency/headers: none (read)
- iOS caller: Core/NativeChannelChain.swift:222-223 (GET api/im/chain/info with conversation_id, chain_id, cursor, limit="50"); allow-list BusinessRuntimeConfiguration.swift:232
- SYNTHETIC example: `GET /api/im/chain/info?conversation_id=501&chain_id=31&cursor=0&limit=50` -> `{"code":200,"msg":"操作成功","data":{"source":"original-channel-chain-v1","chain":{"id":"31","conversationId":"501","messageId":"9001","creatorMemberId":"1001","title":"周六约饭","status":"OPEN","version":"1","maxSlots":10,"activeCount":1,"deadlineAt":null,"accepting":true,"canParticipate":true,"canClose":false},"list":[{"id":"5","chainId":"31","memberId":"1002","position":"1","version":"0","status":"ACTIVE","content":"我+1"}],"mine":{"id":"5","chainId":"31","memberId":"1002","position":"1","version":"0","status":"ACTIVE","content":"我+1"},"hasMore":false}}`

---
## G24 (ApiImAppealFileG24Controller, `@RequestMapping("/api/im")`; services SVC/g24/ImAppealG24ServiceImpl.java, ImFileG24ServiceImpl.java)
Errors for all G24: ServiceException -> `{code:e.code,msg,errorCode:<detail>}` (CTRL:119-126); other Exception -> `{code:500,msg:"操作失败，请稍后重试"}`. Success payload is a Map under `data`.
Appeal routes: snake_case keys; appellant from token. Appeal mutation dedupe table via mapper.selectRequest(memberId, requestId).

### G24 POST /api/im/appeals
- Controller: ApiImAppealFileG24Controller.java:42
- Auth: token required
- Encoding: JSON @RequestBody Map
- Params (body): `submit_request_id` lowercase UUID REQUIRED; `action_id` positive int (number or canonical digit string) REQUIRED; `guild_id` same REQUIRED; `guild_kind` same REQUIRED; `reason_code` one of MISJUDGE|NOT_ME|EXCESSIVE|OTHER REQUIRED; `reason_text` string REQUIRED non-empty after trim, <=500 cp (ImAppealG24ServiceImpl:47-53,216)
- Success shape (data): `{request_id, state:"APPLIED", appeal_id:string, action_id:string, appellant_member_id:string, status:string (e.g. PENDING), can_add_evidence:1|0, decision_reason:string ("" default)}` (record() :150-165)
- Errors (code / errorCode): 400 REQUEST_ID_INVALID, APPEAL_FIELD_INVALID, APPEAL_REASON_INVALID, APPEAL_TEXT_REQUIRED, APPEAL_TEXT_TOO_LONG; 404 APPEAL_ACTION_NOT_FOUND (:65, includes other member's action); 409 APPEAL_ALREADY_EXISTS (:67); 409 APPEAL_WINDOW_CLOSED (:69); 409 REQUEST_ID_CONFLICT (:146); 409 REQUEST_IN_FLIGHT (:77); **503 APPEAL_ACTION_SOURCE_UNAVAILABLE (:60) whenever no `ChannelModerationActionReaderG24` bean exists (none implemented in repo => submit is always 503 as shipped)**
- Idempotency/headers: body `submit_request_id`; same id+op+body hash => stored result_json replayed, else 409 REQUEST_ID_CONFLICT; no headers
- iOS caller: Core/NativeChannelAppealFlow.swift:259 (path "api/im/appeals", body keys guild_kind, guild_id, action_id, reason_code, reason_text, submit_request_id at :259-261); allow-list Core/NativeChannelAppealRuntime.swift:97,129; BusinessRuntimeConfiguration.swift:220
- SYNTHETIC example: `POST /api/im/appeals` `{"guild_kind":1,"guild_id":"7","action_id":"88","reason_code":"MISJUDGE","reason_text":"误判","submit_request_id":"55555555-2222-4333-8444-555555555555"}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"5555...","state":"APPLIED","appeal_id":"12","action_id":"88","appellant_member_id":"1001","status":"PENDING","can_add_evidence":1,"decision_reason":""}}`

### G24 GET /api/im/appeals/{appealId}
- Controller: ApiImAppealFileG24Controller.java:49
- Auth: token required
- Encoding: path variable, no body
- Params: `appealId` Long path, required
- Success shape (data): `{appeal_id:string, action_id:string, appellant_member_id:string, status, decision_reason:string, reason_text, submitted_at, decided_at, withdrawn_at, due_at (types from DB timestamps: UNKNOWN serialization), can_add_evidence:1|0, evidence_json:{text}, supplements:[string (stored JSON text)], evidence_count:int, timeline:[{event,at,reason}]}` (view() :167-197)
- Errors: 404 APPEAL_NOT_FOUND (missing or not owner, :137); non-numeric appealId => framework type-mismatch (shape UNKNOWN)
- Idempotency/headers: none
- iOS caller: Core/NativeChannelAppealFlow.swift:196 and :218 (`exchange("GET","api/im/appeals/"+id)`)
- SYNTHETIC example: `GET /api/im/appeals/12` -> `{"code":200,"msg":"操作成功","data":{"appeal_id":"12","action_id":"88","appellant_member_id":"1001","status":"PENDING","decision_reason":"","reason_text":"误判","submitted_at":"2026-11-08 10:00:00","decided_at":null,"withdrawn_at":null,"due_at":"2026-11-15 10:00:00","can_add_evidence":1,"evidence_json":{"text":"误判"},"supplements":[],"evidence_count":1,"timeline":[{"event":"SUBMITTED","at":"2026-11-08 10:00:00","reason":"误判"}]}}` (date formats UNKNOWN)

### G24 POST /api/im/appeals/{appealId}/evidence
- Controller: ApiImAppealFileG24Controller.java:56
- Auth: token required
- Encoding: path var + JSON @RequestBody Map
- Params: `appealId` Long path; body `request_id` lowercase UUID REQUIRED; `evidence_json` object REQUIRED with `text` string non-empty <=500 cp (only `text` read, :88-90)
- Success shape (data): same `record()` shape as submit (request_id, state:"APPLIED", appeal_id, action_id, appellant_member_id, status, can_add_evidence, decision_reason)
- Errors: 400 REQUEST_ID_INVALID / APPEAL_EVIDENCE_INVALID / APPEAL_TEXT_REQUIRED / APPEAL_TEXT_TOO_LONG; 404 APPEAL_NOT_FOUND; 409 APPEAL_NOT_OPEN (status not PENDING/REVIEWING :96); 409 APPEAL_EVIDENCE_LIMIT (max 5 supplements :98); 409 REQUEST_ID_CONFLICT / REQUEST_IN_FLIGHT
- Idempotency/headers: body `request_id`, hash("evidence", appealId, text); replay as above
- iOS caller: Core/NativeChannelAppealFlow.swift:263 (body request_id, evidence_json:{text})
- SYNTHETIC example: `POST /api/im/appeals/12/evidence` `{"request_id":"66666666-2222-4333-8444-555555555555","evidence_json":{"text":"补充说明"}}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"6666...","state":"APPLIED","appeal_id":"12","action_id":"88","appellant_member_id":"1001","status":"PENDING","can_add_evidence":1,"decision_reason":""}}`

### G24 POST /api/im/appeals/{appealId}/withdraw
- Controller: ApiImAppealFileG24Controller.java:63
- Auth: token required
- Encoding: path var + JSON @RequestBody Map
- Params: `appealId` Long path; body `request_id` lowercase UUID REQUIRED; `reason` string REQUIRED non-empty <=500 cp
- Success shape (data): `record()` shape; status becomes "WITHDRAWN", can_add_evidence 0
- Errors: 400 REQUEST_ID_INVALID / APPEAL_TEXT_REQUIRED / APPEAL_TEXT_TOO_LONG; 404 APPEAL_NOT_FOUND; 409 APPEAL_NOT_OPEN (:117); 409 REQUEST_ID_CONFLICT / REQUEST_IN_FLIGHT
- Idempotency/headers: body `request_id`; hash("withdraw", appealId, reason)
- iOS caller: Core/NativeChannelAppealFlow.swift:266 (body request_id, reason)
- SYNTHETIC example: `POST /api/im/appeals/12/withdraw` `{"request_id":"77777777-2222-4333-8444-555555555555","reason":"不再申诉"}` -> `{"code":200,"msg":"操作成功","data":{"request_id":"7777...","state":"APPLIED","appeal_id":"12","action_id":"88","appellant_member_id":"1001","status":"WITHDRAWN","can_add_evidence":0,"decision_reason":""}}` (decision_reason may be the withdraw reason if updateAppealStatus stores it there: UNKNOWN)

### G24 POST /api/im/file/upload
- Controller: ApiImAppealFileG24Controller.java:70
- Auth: token required
- Encoding: multipart/form-data (@RequestParam + MultipartFile; no `consumes`)
- Params: `conversation_id` Long REQUIRED; `upload_request_id` string REQUIRED lowercase UUID; `source_sha256` string REQUIRED, 64 lowercase hex, must equal server-computed SHA-256 of file; `file` MultipartFile REQUIRED. Validation (ImFileG24ServiceImpl:67-101): filename non-empty, trimmed, <=240 bytes UTF-8, no `/ \` or control chars; extension in pdf,doc,docx,xls,xlsx,ppt,pptx,zip,txt; size 1..20MiB; magic-byte signature must match type. Member must be a non-deleted IM conversation member AND active group member.
- Success shape (data): `{source:"original-im-file-upload-v1", owner_member_id:string, conversation_id:string, upload_request_id, source_sha256, state:"UPLOADED", scan_state:string (initial value from DB; "PENDING" per scanner comment), review_state:string (e.g. HOLD/APPROVED/REJECTED), reference:{uploadRequestID,attachmentID:string,name,size:int,mime,ext,sha256}}` (receiptOf :206-215, reference :238-248)
- Errors (code/errorCode): 400 CONVERSATION_INVALID, REQUEST_ID_INVALID, FILE_HASH_INVALID, FILE_NAME_INVALID, FILE_SIZE_INVALID, FILE_HASH_MISMATCH, FILE_READ_FAILED (controller :84); 403 IM_FILE_ACCESS_DENIED (:261); 415 FILE_TYPE_UNSUPPORTED (:279), FILE_CONTENT_UNSUPPORTED (:78); 409 UPLOAD_REQUEST_CONFLICT (:209); **503 FILE_STORAGE_UNAVAILABLE (:84) when no `ImFileBlobStoreG24` bean (none implemented in repo)**. Note: replay of an existing upload_request_id returns the stored receipt BEFORE the storage check (:80-81).
- Idempotency/headers: form `upload_request_id` unique per owner; same id+same sha+same conversation => existing receipt; otherwise 409 UPLOAD_REQUEST_CONFLICT. Server storage key im-file/{member}/{requestId}.{ext}
- iOS caller: Core/IMFileService.swift:40 (`makeFormRequest`, multipart, fields conversation_id/upload_request_id/source_sha256); allow-list BusinessRuntimeConfiguration.swift:238
- SYNTHETIC example: `POST /api/im/file/upload` multipart conversation_id=501, upload_request_id=88888888-2222-4333-8444-555555555555, source_sha256=<64hex>, file=report.pdf -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-file-upload-v1","owner_member_id":"1001","conversation_id":"501","upload_request_id":"8888...","source_sha256":"<64hex>","state":"UPLOADED","scan_state":"PENDING","review_state":"HOLD","reference":{"uploadRequestID":"8888...","attachmentID":"3","name":"report.pdf","size":1024,"mime":"application/pdf","ext":"pdf","sha256":"<64hex>"}}}` (initial review_state literal UNKNOWN: DB default)

### G24 GET /api/im/file/receipt
- Controller: ApiImAppealFileG24Controller.java:85
- Auth: token required
- Encoding: query params
- Params: `conversation_id` Long REQUIRED; `upload_request_id` string REQUIRED; `source_sha256` string REQUIRED (same validators)
- Success shape (data): if upload exists: same as upload receipt; if none: `{source:"original-im-file-upload-v1", owner_member_id, conversation_id, upload_request_id, source_sha256, state:"NOT_FOUND", reference:null}` (notFound :218-223)
- Errors: 400 CONVERSATION_INVALID / REQUEST_ID_INVALID / FILE_HASH_INVALID; 403 IM_FILE_ACCESS_DENIED; 409 UPLOAD_REQUEST_CONFLICT
- Idempotency/headers: none (read)
- iOS caller: Core/IMFileService.swift:52; allow-list BusinessRuntimeConfiguration.swift:239
- SYNTHETIC example: `GET /api/im/file/receipt?conversation_id=501&upload_request_id=8888...&source_sha256=<64hex>` -> same data shape as upload with `state:"UPLOADED"`, or `{"state":"NOT_FOUND","reference":null,...}`

### G24 POST /api/im/file/scan
- Controller: ApiImAppealFileG24Controller.java:95
- Auth: token required
- Encoding: @RequestParam (form-urlencoded or query; no body JSON). iOS sends makeFormRequest fields.
- Params: `conversation_id` Long, `upload_request_id` string, `source_sha256` string, all REQUIRED
- Success shape (data): upload receipt shape, `state:"UPLOADED"`, with refreshed `scan_state` (CLEAN|INFECTED|UNKNOWN|PENDING) and `review_state` (REJECTED if INFECTED; APPROVED if CLEAN and `chengyin.im-file.auto-approve-clean=true` (default false) else HOLD). If no scanner bean (none implemented) scan_state stays unchanged (PENDING). NOT_FOUND shape if no upload. (:114-133)
- Errors: as receipt (400/403/409)
- Idempotency/headers: only re-scans rows in PENDING/UNKNOWN
- iOS caller: Core/IMFileService.swift:62-63; allow-list BusinessRuntimeConfiguration.swift:240
- SYNTHETIC example: `POST /api/im/file/scan` form conversation_id=501&upload_request_id=8888...&source_sha256=<64hex> -> data as upload receipt with `"scan_state":"CLEAN","review_state":"HOLD"` (only if a scanner bean were present)

### G24 GET /api/im/file/message/{messageId}/authorization
- Controller: ApiImAppealFileG24Controller.java:105
- Auth: token required
- Encoding: path var
- Params: `messageId` Long path
- Success shape (data): `{source:"original-im-file-authorization-v1", message:{id,conversationId,senderId,msgType,content,extraJson,status,createTime:string|null,senderName,senderAvatar}}` camelCase (messageView :196-204). Returned only if message msgType==12, status 0, extra_json.source=="original-im-file-v1", upload matches (request id, sha, conversation, owner==sender), scan_state CLEAN and review_state APPROVED.
- Errors: 404 FILE_NOT_FOUND (missing / non-file / not member / mismatched ref, :174,:180,:189); 409 FILE_MESSAGE_WITHHELD (status != 0, :176); 409 FILE_NOT_READY (:191)
- Idempotency/headers: none
- iOS caller: Core/IMFileService.swift:70 (GET, `request.httpMethod="GET"` :71); allow-list BusinessRuntimeConfiguration.swift:244
- SYNTHETIC example: `GET /api/im/file/message/9100/authorization` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-file-authorization-v1","message":{"id":9100,"conversationId":501,"senderId":1001,"msgType":12,"content":"[文件]","extraJson":"{...}","status":0,"createTime":"2026-11-08T10:00","senderName":"阿明","senderAvatar":null}}}`

### G24 GET /api/im/file/message/{messageId}/preview
- Controller: ApiImAppealFileG24Controller.java:112
- Auth: token required
- Encoding: path var
- Params: `messageId` Long path
- Success shape (data): `{source:"original-im-file-preview-v1", message_id:string, conversation_id:string, reference:{uploadRequestID,attachmentID,name,size,mime,ext,sha256}, state:"READY", url:string(https://...), expires_in_seconds:120}` (:154-162)
- Errors: same authorize() set as authorization (404 FILE_NOT_FOUND, 409 FILE_MESSAGE_WITHHELD, 409 FILE_NOT_READY); **503 FILE_PREVIEW_UNAVAILABLE (:150,:153) when no `ImFilePreviewSignerG24` bean (none implemented) or URL not https**
- Idempotency/headers: none
- iOS caller: Core/IMFileService.swift:89; allow-list BusinessRuntimeConfiguration.swift:244-247
- SYNTHETIC example: `GET /api/im/file/message/9100/preview` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-file-preview-v1","message_id":"9100","conversation_id":"501","reference":{"uploadRequestID":"8888...","attachmentID":"3","name":"report.pdf","size":1024,"mime":"application/pdf","ext":"pdf","sha256":"<64hex>"},"state":"READY","url":"https://signed.example/...","expires_in_seconds":120}}`

---
## G25 video (ApiImVideoG25Controller, `@RequestMapping("/api/im/video")`; service SVC/g25/ImVideoG25Service.java)
Errors for all video routes: ServiceException -> `{code:e.code,msg}` only (NO errorCode field; CTRL:56-57); other -> `{code:500,msg:"操作失败，请稍后重试"}`. Group-chat gate = requireActiveGroupMembership (401/403/404 as in G23 note). No `ImVideoPipelineG25` bean exists in repo => policy/upload/receipt/preview answer `{code:503,msg:"VIDEO_PIPELINE_UNAVAILABLE"}` as shipped (ImVideoG25Service:205-207). authorization does not call pipeline().

### G25 GET /api/im/video/policy
- Controller: ApiImVideoG25Controller.java:24
- Auth: token required
- Encoding: query params
- Params: `conversation_id` Long REQUIRED
- Success shape (data): `{source:"original-im-video-policy-v1", maximumSourceBytes:int(<=64MiB), maximumOutputBytes:int(<=64MiB), maximumDurationMS:30000, outputMIME:"video/mp4"}`
- Errors: 503 VIDEO_PIPELINE_UNAVAILABLE (checked first); 401 "请先登录"; group-gate 401/403/404
- Idempotency/headers: none
- iOS caller: Core/IMVideoService.swift:62 (policy GET); allow-list BusinessRuntimeConfiguration.swift:251
- SYNTHETIC example: `GET /api/im/video/policy?conversation_id=501` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-video-policy-v1","maximumSourceBytes":67108864,"maximumOutputBytes":16777216,"maximumDurationMS":30000,"outputMIME":"video/mp4"}}` (values depend on pipeline impl; none ships)

### G25 POST /api/im/video/upload
- Controller: ApiImVideoG25Controller.java:29
- Auth: token required
- Encoding: multipart/form-data (@RequestParam + MultipartFile)
- Params: `conversation_id` Long REQUIRED; `upload_request_id` canonical lowercase UUID (UUID.fromString(x).toString().equals(x)) REQUIRED; `source_sha256` 64 lowercase hex REQUIRED; `file` REQUIRED non-empty, <= min(pipeline.maximumSourceBytes, 64MiB), sha256 must match
- Success shape (data): receipt: `{source:"original-im-video-upload-v1", owner_member_id:string, conversation_id:string, upload_request_id, source_sha256, state:"UPLOADED", video_review_state:"HOLD"|"APPROVED"|"REJECTED", cover_review_state:same, reference:{uploadRequestID,attachmentID:string,sha256,coverSHA256,size,coverSize,durationMS,width,height}}` (:82-103,180-191). Pipeline output must have duration 1..30000ms, cover <=10MiB, else 502 "视频处理失败" (:68-72).
- Errors (code, msg only): 503 VIDEO_PIPELINE_UNAVAILABLE; 400 "upload_request_id 或 source_sha256 无效" / "视频为空" / "source_sha256 与内容不一致" / "读取上传内容失败"(controller :36); 413 "视频过大"; 409 "upload_request_id 已被不同视频占用"; 502 "视频处理失败"; 401 / group-gate
- Idempotency/headers: form `upload_request_id` per (owner, conversation) in im_video_upload_g25 (insert RESERVED, DuplicateKey ignored; processed once while video_sha256 null); different source_sha256 => 409. Not @Transactional.
- iOS caller: Core/IMVideoService.swift:40 (multipart via makeFormRequest); allow-list BusinessRuntimeConfiguration.swift:249
- SYNTHETIC example: `POST /api/im/video/upload` multipart conversation_id=501, upload_request_id=99999999-2222-4333-8444-555555555555, source_sha256=<64hex>, file=clip.mp4 -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-video-upload-v1","owner_member_id":"1001","conversation_id":"501","upload_request_id":"9999...","source_sha256":"<64hex>","state":"UPLOADED","video_review_state":"HOLD","cover_review_state":"HOLD","reference":{"uploadRequestID":"9999...","attachmentID":"4","sha256":"<64hex>","coverSHA256":"<64hex>","size":2048000,"coverSize":30000,"durationMS":12000,"width":720,"height":1280}}}`

### G25 GET /api/im/video/receipt
- Controller: ApiImVideoG25Controller.java:42
- Auth: token required
- Encoding: query params
- Params: `conversation_id` Long, `upload_request_id` string, `source_sha256` string; all REQUIRED
- Success shape (data): as upload receipt; when no row or not yet processed: `{source,owner_member_id,conversation_id,upload_request_id,source_sha256,state:"NOT_FOUND"}` (no reference key) (:94-97)
- Errors: 503 VIDEO_PIPELINE_UNAVAILABLE; 400 "upload_request_id 或 source_sha256 无效"; 409 "upload_request_id 已被不同视频占用"; 401/group-gate
- Idempotency/headers: none
- iOS caller: Core/IMVideoService.swift:52; allow-list BusinessRuntimeConfiguration.swift:250
- SYNTHETIC example: `GET /api/im/video/receipt?conversation_id=501&upload_request_id=9999...&source_sha256=<64hex>` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-video-upload-v1","owner_member_id":"1001","conversation_id":"501","upload_request_id":"9999...","source_sha256":"<64hex>","state":"NOT_FOUND"}}`

### G25 GET /api/im/video/message/{id}/authorization
- Controller: ApiImVideoG25Controller.java:48
- Auth: token required
- Encoding: path var
- Params: `id` Long path (message id)
- Success shape (data): `{source:"original-im-video-authorization-v1", message:{id:long,conversationId,senderId,msgType:11,content,extraJson,status:0}}` (:106-120). Requires im_message msg_type 11, status 0, check_status != 2, extra_json.source=="original-im-video-v1", matching im_video_upload_g25 row (state UPLOADED, reference fields equal), and video+cover review APPROVED.
- Errors: 401 "请先登录"; 404 "消息不存在"/"消息不可用"/"视频引用无效"/"视频不存在"; 409 "视频引用不匹配"; 403 "视频审核未通过"; group-gate errors. Does NOT need pipeline bean.
- Idempotency/headers: none
- iOS caller: Core/IMVideoService.swift:74 (GET); allow-list BusinessRuntimeConfiguration.swift:255
- SYNTHETIC example: `GET /api/im/video/message/9200/authorization` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-video-authorization-v1","message":{"id":9200,"conversationId":501,"senderId":1001,"msgType":11,"content":"[视频]","extraJson":"{...}","status":0}}}`

### G25 GET /api/im/video/message/{id}/preview
- Controller: ApiImVideoG25Controller.java:51
- Auth: token required
- Encoding: path var
- Params: `id` Long path
- Success shape (data): `{source:"original-im-video-preview-v1", message_id:string, conversation_id:string, reference:{uploadRequestID,attachmentID,sha256,coverSHA256,size,coverSize,durationMS,width,height}, state:"READY", videoURL:string, coverURL:string, expires_in_seconds:120}` (:133-142); both URLs must start with https://
- Errors: 503 VIDEO_PIPELINE_UNAVAILABLE (first); same visibleMessage/approvedUpload errors as authorization (404/409/403); 502 "预览地址不可用"
- Idempotency/headers: none
- iOS caller: Core/IMVideoService.swift:93; allow-list BusinessRuntimeConfiguration.swift:255
- SYNTHETIC example: `GET /api/im/video/message/9200/preview` -> `{"code":200,"msg":"操作成功","data":{"source":"original-im-video-preview-v1","message_id":"9200","conversation_id":"501","reference":{"uploadRequestID":"9999...","attachmentID":"4","sha256":"<64hex>","coverSHA256":"<64hex>","size":2048000,"coverSize":30000,"durationMS":12000,"width":720,"height":1280},"state":"READY","videoURL":"https://cdn.example/v.mp4?sig=x","coverURL":"https://cdn.example/c.jpg?sig=x","expires_in_seconds":120}}`

---
## G25 join-request (ApiJoinRequestG25Controller, `@RequestMapping("/api/join-request")`; service SVC/g25/JoinRequestG25Service.java)
All four: JSON @RequestBody Map; Auth token required; success `data` = view map; errors `{code,msg}` only (no errorCode; CTRL:38-39), other exceptions `{code:500,msg:"操作失败，请稍后重试"}`; idempotency by body `request_id` (regex ^[A-Za-z0-9:._-]{1,64}$, NOT necessarily UUID) in table join_request_action_g25 unique (actor_id, request_id): same action+hash replays stored response_json, different => 409 "request_id 已被不同请求占用". `@Transactional`. Common view shape: `{id:long, guild_kind:long, guild_id:long, applicant_id:long, invite_id?:long (only if non-null), status:int(0 pending/1 approved/2 rejected/3 cancelled), join_state:"PENDING"|"APPROVED"|"REJECTED"|"CANCELLED", request_id:string}` (view() :153-166). Invalid numeric/text fields => 400 "<name> 无效". 401 "请先登录" if actor missing. NOTE: different contract from existing ApiClubController `/api/club/join-request/*` (not covered).

### G25 POST /api/join-request/submit
- Controller: ApiJoinRequestG25Controller.java:24
- Auth: token required
- Encoding: JSON
- Params (body): `guild_kind` int REQUIRED (1 club, 3 team; else 400 "guild_kind 无效"); `guild_id` long>0 REQUIRED; `request_id` REQUIRED; `invite_id` long>0 optional; `message` string optional (trimmed; empty=>null; <=60 cp else 400 "message 不能超过60字")
- Success shape (data): common view with status 0 / join_state "PENDING"
- Errors: 400 as above; 409 "TEAM_ADMISSION_UNAVAILABLE" for guild_kind 3 (:46, after replay check); 404 "空间不存在或未开放" (club missing or status!=1 :49); 409 "已是该空间成员" (owner or active member :50,:52); 403 "该成员已被封禁" (:140); 409 "已有待审核的申请" (dup open request :58); 409 "request_id 已被不同请求占用"
- Idempotency/headers: body `request_id`; hash("submit",kind,guild,invite,message)
- iOS caller: Core/ChannelAdmissionGovernanceClient.swift:9 (submitPath), body built :36-42, POST JSON `post()` :131-136
- SYNTHETIC example: `POST /api/join-request/submit` `{"guild_kind":1,"guild_id":7,"request_id":"req-001","message":"想加入"}` -> `{"code":200,"msg":"操作成功","data":{"id":15,"guild_kind":1,"guild_id":7,"applicant_id":1002,"status":0,"join_state":"PENDING","request_id":"req-001"}}`

### G25 POST /api/join-request/cancel
- Controller: ApiJoinRequestG25Controller.java:27
- Auth: token required
- Encoding: JSON
- Params (body): `id` long>0 REQUIRED (join request id); `request_id` REQUIRED
- Success shape (data): common view, status 3 / "CANCELLED"
- Errors: 404 "申请不存在" (:133); 403 "无权操作该申请" (not applicant :74); 409 "申请已处理" (:75); 400; 409 request_id conflict
- Idempotency/headers: body `request_id`; hash("cancel", id)
- iOS caller: Core/ChannelAdmissionGovernanceClient.swift:10 (cancelPath), post at :50
- SYNTHETIC example: `POST /api/join-request/cancel` `{"id":15,"request_id":"req-002"}` -> data `{"id":15,"guild_kind":1,"guild_id":7,"applicant_id":1002,"status":3,"join_state":"CANCELLED","request_id":"req-002"}`

### G25 POST /api/join-request/approve
- Controller: ApiJoinRequestG25Controller.java:30
- Auth: token required
- Encoding: JSON
- Params (body): `id` long>0 REQUIRED; `request_id` REQUIRED; `remark` string optional (<=200 cp else 400 "remark 不能超过200字")
- Success shape (data): common view, status 1 / "APPROVED". Side effect: writes club_member (insert role 0 status 1, or restore status 0 row) (:98-105).
- Errors: 404 "申请不存在"/"空间不存在"; 403 "不能审核自己的申请" (:145), 403 "无权审核该申请" (reviewer must be club owner or active club_member with role>0, :150); 409 "申请已处理"; 403 "该成员已被封禁"; 409 "该成员当前状态无法通过申请恢复" (:104); 400; 409 request_id conflict
- Idempotency/headers: body `request_id`; hash("approve", id, remark)
- iOS caller: Core/ChannelAdmissionGovernanceClient.swift:11 (approvePath), post at :61
- SYNTHETIC example: `POST /api/join-request/approve` `{"id":15,"request_id":"req-003","remark":"欢迎"}` -> data `{"id":15,"guild_kind":1,"guild_id":7,"applicant_id":1002,"status":1,"join_state":"APPROVED","request_id":"req-003"}`

### G25 POST /api/join-request/reject
- Controller: ApiJoinRequestG25Controller.java:33
- Auth: token required
- Encoding: JSON
- Params (body): `id` long>0 REQUIRED; `request_id` REQUIRED; `reject_reason_code` int REQUIRED in {1,2,3,4,5,9}; `reject_note` string optional (<=200 cp; REQUIRED when code==9)
- Success shape (data): common view, status 2 / "REJECTED"
- Errors: 400 "reject_reason_code 无效" / "其他原因需填写说明" / "reject_note 不能超过200字"; 404 "申请不存在"/"空间不存在"; 403 "不能审核自己的申请" / "无权审核该申请"; 409 "申请已处理"; 409 request_id conflict
- Idempotency/headers: body `request_id`; hash("reject", id, code, note)
- iOS caller: Core/ChannelAdmissionGovernanceClient.swift:12 (rejectPath), post at :76
- SYNTHETIC example: `POST /api/join-request/reject` `{"id":15,"request_id":"req-004","reject_reason_code":9,"reject_note":"名额已满"}` -> data `{"id":15,"guild_kind":1,"guild_id":7,"applicant_id":1002,"status":2,"join_state":"REJECTED","request_id":"req-004"}`

---
NOTE: be-g22 report says G22 team-invite offer WRITES live at `/api/team/original-request` (non-G22 controller, not covered here). iOS NativeFriendService.writePaths also uses `/api/friend/accept|reject|cancel`, which are in ApiFriendG08Controller (not in this part; ApiFriendG09Controller also maps /api/friend). be-g25 report notes club `/api/club/join-request/*` exists in ApiClubController (different contract). be-g22 also lists city-game routes (CityOrderedMap/TaskHistory/Participation MVC adapters) as non-G22 unwired adapters.
