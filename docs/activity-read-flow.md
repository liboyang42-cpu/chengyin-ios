# Native activity read slice

The signed-in app now has an Activities tab and Account tab. The full original navigation is not yet migrated.

Implemented source:
- Multipart list and detail client, preserving gateway prefix and captured raw authorization
- Native searchable/paged list, refresh, loading, empty, error/retry and deduplication
- Read-only detail with native MapKit only for valid coordinates, ticket prices/inventory as nullable values, and an explicit club gate
- Session-stamp checks discard results from an obsolete account context
- Registration remains visibly pending; no quote/order/payment request is sent

Safety and scope:
- No endpoint is configured by default. These views have not been validated against a real backend
- Currency is explicitly unconfirmed rather than inferred from English or Chinese language. Time strings are preserved pending an authoritative timezone contract
- No real user content, account or coordinate was used in tests
- Ticket selection, quote/create/payment, clubs joining, comments, reactions, host actions, media-rich content, the other original home sections and full navigation remain to be migrated
- Core fixture tests verify requests and decoding. Existing XCUITests cover entry/language only, not these new activity screens. Separate activity UI scenarios and screenshots are still needed
