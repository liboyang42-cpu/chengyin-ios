# C08 ACK command patch for dot

Not installed. `NativeChannelNotificationJournal.swift` is not in this exclusive tree. `persist`, `restore`, and `settle` stay the original methods. ACK is not `PREFERENCE` or `MUTE`.

The installable diff is `C08-ack-command.patch`, read from the e47 copies of:

- `Core/NativeChannelNotificationAuthority.swift`
- `Core/NativeChannelNotificationContracts.swift`
- `Core/NativeChannelNotificationService.swift`
- `Core/NativeChannelNotificationCoordinator.swift`

`POST api/im/read` uses `conversation_id`, `request_id`, and `last_message_id` (`read_to` is the same cursor). `scope_type` and `scope_id` stay on the local intent and the receipt. They are not the HTTP body.

`MessageHistoryAckEntry.originalReadBody()` is the caller in this tree. It does not send. A failed precheck does not rewrite a kept intent. An applied receipt sets the terminal phase and does not write again. UNKNOWN does not send again unless `resumeSameRequest`, the current write approval, and an explicit retry all hold, and then only with the same id and the same intent.

Swift was not compiled. This patch is not applied here.
