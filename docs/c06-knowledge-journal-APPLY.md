# C06 知识审核身份

本分支改了作者流、审核 writer、gate 和编辑页。磁盘记录只有请求号、成员、owner、商家行号，不记名称、问候、人设、知识正文。写入发生在原提交回执的请求号与传入请求号相同之后。npc/save 用的是另一把 journal 钥匙，成功清理不会删这条。

`docs/c06-knowledge-journal-appsession.diff` 未写入 `AppSession.swift`。它只对 pending 里已经创建 `MerchantNPCKnowledgeAuthorFlow` 的那一处，把 `sessionDefaults` 注进 `MerchantNPCKnowledgeRecoveryStore`。基准 AppSession SHA256 `408eb0bc858db060b05022de0525afe3962a24ed3062bfdf7e9fa13d273d1ef8`。dry-run 已过。不改 PBX。

编辑页在本分支已改。若另一棵 pending 编辑页仍是同一函数（SOURCE-INDEX `9f137353fac22396`），`docs/c06-knowledge-journal-editor.diff` 可对上，不要打两次。

页面内存和 flow 内存都空、且成员与商家对得上时，才读这条身份并走一次原 GET。缺行就停。不发布。Swift / HTTP 未跑。重启后的全链要等 AppSession 那一处注入装上。
