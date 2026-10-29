# 角色页接入知识审核作者流（未应用）

`docs/c06-character-author-flow.diff` 对着本分支的 `App/AppSession.swift`，dry-run 已过。它没有写入文件。

角色目的地改为带上现有的 `MerchantNPCKnowledgeAuthorFlow` 和 `MerchantOperationsSessionReader`。请求号写进保存日记的另一把钥匙。不改 PBX。Swift 和 HTTP 未跑。
