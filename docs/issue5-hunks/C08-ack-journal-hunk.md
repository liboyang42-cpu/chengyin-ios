# C08 ACK journal hunk for dot

Not applied. This exclusive tree does not contain `NativeChannelNotificationJournal.swift` or `NativeChannelNotificationContracts.swift`. Do not copy those files into this PR. Do not encode ACK as `PREFERENCE` or `MUTE`.

Source read for the insertion point: e47 `Core/NativeChannelNotificationContracts.swift` operation enum and `validate()`, and `Core/NativeChannelNotificationCoordinator.swift` `retryOriginal()` around the `allows(...)` choice.

## Keep

- `NativeChannelNotificationJournal.persist`, `restore`, `settle`, `rememberFailure` stay the only storage. No second ledger.
- Restart restores the same command and reads the original receipt. It does not mint a new request id.
- Revoke does not `settle` or delete an unknown command.
- `POST api/im/read` stays the ack write. `GET api/im/notification-requests/{requestId}` stays the receipt read.

## Add, as its own operation

In `NativeChannelNotificationCommand.Operation`:

```swift
case ack = "ACK"
```

Add an initializer that sets `operation = .ack` and rejects preference or mute fields. The body keys are only `request_id`, `scope_type`, `scope_id`, and `last_message_id`. `scope_type` is the integer 1. `scope_id` is the channel id. `last_message_id` is `>= 0`.

In `validate()`, handle `.ack` before the preference branch. An ACK body that contains `level`, `minutes`, `muted_until`, or `conversation_id` is invalid.

## Permission

`NativeChannelNotificationCoordinator.retryOriginal()` currently does:

```swift
client.allows(original.operation == .mute ? .mute : .save, scope: original.scope)
```

ACK must not use `.save` or `.mute`. Add a distinct allow case for `.ack` and require that approval, plus `resumeSameRequest` on the original receipt, plus the explicit retry. A receipt read alone does not dispatch.

## This candidate

`MessageHistoryAckEntry` keeps the in-memory intent only. A failed precheck does not keep a request id. UNKNOWN does not send again. A new instance does not mint an id to bypass UNKNOWN. Durable ACK storage is the hunk above and is not installed here. Swift was not compiled.
