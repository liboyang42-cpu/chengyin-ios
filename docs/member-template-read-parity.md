# Member-template read namespace

`scope=my` uses a `cms_member_template` ID and form POST `/api/template/myinfo` with `id`; it is not the public library `/api/template/info` namespace. A distinct MemberPlayTemplateID and exact returned-ID check prevent accidental substitution. The read-only projection deliberately excludes answers, hidden verification fields and authoring secrets. Draft state is not treated as publish/review success.

Normal entries: Template authoring → My shelf → template detail, and the source-provided template row in participation detail (closing its sheet before navigation). Existing source readers already own `/api/template/my-list`; this packet does not add a duplicate shelf. No public-template fallback is used when myinfo refuses a private/deleted/unavailable record.

Source authority, inspected 2026-10-02: mini pages/templatedetail/templatedetail.js:200–204,317–320,475–485; backend ApiTemplateController.java:608–671. The backend allows the owner to read a draft and allows another viewer only a nondeleted published/approved/listed record, stripping secrets for that other viewer. A `scope=my` navigation value is never client-side proof of ownership. Player participation's top-level templateId is optional and is only used when actually supplied; normal own-shelf IDs come from my-list.

The native page is a pushed read-only destination with refresh/retry, current account-epoch fences, plain server refusal text, gallery/story/instruction metadata and gated media. Existing saved-template editing/adoption is not fabricated from a public-library reader. That downstream editor remains distinct and unclaimed.

Default history/private-template reads remain off; no real backend requests performed. Six domain tests are authored. Project and catalog structural checks pass; Swift/Apple/simulator/visual/accessibility acceptance remain NOT_RUN because this executor has no Swift/Xcode toolchain.
