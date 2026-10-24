# C08 ACK command patch for dot

Not installed. `NativeChannelNotificationJournal.swift` is not in this exclusive tree. `persist`, `restore`, and `settle` stay the original methods. ACK is not `PREFERENCE` or `MUTE`.

The installable diff is `C08-ack-command.patch`. `git apply --check` passed on a copy of these same-hash e47 members. It is not installed on this exclusive tree and was not written into the e47 tree.

Signed package `ios-e2-to-e47-reviewed-source.zip` is 3216447 bytes, SHA256 `821d56d453fcdcff673d21012d9651471fffc8478ba293b026d9d6c182852f20`. These members matched the package manifest:

- `Core/NativeChannelNotificationJournal.swift` `9ea128bb639bbb9e7ec04160ac2ca37fcd22a7f092701721d1af46c8c575da63`
- `Core/NativeChannelNotificationCoordinator.swift` `40050026bccca88463382b86490c114d48ef0138d7be655a38030dee37c38466`
- `Core/NativeChannelNotificationContracts.swift` `a26c148f58a5a5fec084de35e16c380c6f46d26cead0de2f64dd21ffbd98b028`
- `Core/NativeChannelNotificationService.swift` `ebdf7ce5efc17a89df5614b1f8b0c81816bac35d333051b7b3280a545686a281`
- `Core/NativeChannelNotificationAuthority.swift` `5e6932682ec7470fa238014dff3c93f6e3344a15f5da5b069e48e9b43f461deb`
- `App/NativeChannelNotificationBinding.swift` `b229aedb10c1a77e1e2ee7f420256b2f26092b1810a00997d603aca3070e9d31`

The source command is still only `PREFERENCE` and `MUTE`. The patch adds `ACK`. Binding was read and not changed: it does not grant a new write. No private class was copied into this PR.

- `Core/NativeChannelNotificationAuthority.swift`
- `Core/NativeChannelNotificationContracts.swift`
- `Core/NativeChannelNotificationService.swift`
- `Core/NativeChannelNotificationCoordinator.swift`

`POST api/im/read` uses `conversation_id`, `request_id`, and `last_message_id` (`read_to` is the same cursor). `scope_type` and `scope_id` stay on the local intent and the receipt. They are not the HTTP body.

`MessageHistoryAckEntry.originalReadBody()` is the caller in this tree. It does not send. A failed precheck does not rewrite a kept intent. An applied receipt sets the terminal phase and does not write again. UNKNOWN does not send again unless `resumeSameRequest`, the current write approval, and an explicit retry all hold, and then only with the same id and the same intent.

Swift was not compiled. This patch is not applied here.
