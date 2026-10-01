# Activity read / registration contract review

Source: retained Flutter public client at `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`, `lib/data/api/activity_api.dart` and `lib/data/models/activity.dart`. Client evidence must still be verified against a non-production backend.

- List: POST `/api/activity/list`, multipart `is_my`, filters and `pageNum` / `pageSize`. Nested `data.rows` with legacy top-level `rows`
- Details: POST `/api/activity/info`, multipart `id`, detail under `data`
- Quote: POST `/api/registration/quote`, JSON `ownerType:2`, ownerId, ticketId, isUsePoint
- Create: POST `/api/registration/create`, JSON with quoteSign and an idempotent requestId. A new click/retry must not casually mint a new requestId for an uncertain prior submission
- App payment channel is specified at order creation; do not create a different-channel order and pretend it can be converted later

The foundation now preserves the literal `minAmout` wire spelling with Decimal precision. Missing price is not zero, minimum zero is not all tickets free, unknown inventory is not sold out, missing coordinates are not a default map location. Both product types remain representable, and dislike is distinct from no interaction.

Currency and date timezone are not established by the inspected fields. Do not infer USD from English locale or parse unspecified timezone as if it were approved business time. Define a verified region/currency/time contract before presenting transactions.

No activity network client, detail view, quote request or registration write is implemented in this model-only slice. No business API calls were made.
