# 普通消息回执的组合层放行（未应用）

`c08-im-send-receipt-composition.diff` 只给已登录用户的 `POST api/im/send-receipt` 开口，查询和片段必须为空。不改 `api/im/send`。未套用时，组合层不放行这条回执，读取失败就停在未知，不再发送。

`BusinessRuntimeFeature.imSend` 现在可以把 `api/im/send-receipt` 和 `api/im/send` 放在同一项里。这不是九字段发送证明。
