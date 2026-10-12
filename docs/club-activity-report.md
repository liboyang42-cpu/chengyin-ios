# P045 contextual activity report

Base: f329ff5180551ef3956b2718cb9ef071e2635409 / e5a30ae239ec9f4cdf0576cab3d685b2189d2cdd.

Normal entry: ClubDetail → original activity calendar/list → report beside a topic card → fresh club membership, topic membership/author and concrete activities → singleton or explicit choice → original immutable ACTIVITY report form → original review/confirmation/receipt → close to the same calendar and refresh. Date is label only; topic ID is never substituted for activity ID.

Unique master P045 reportTopicActivity and P050 reportTarget. Mini f859 detail.js2342–2393, wxml216/233/245. Existing MEMBER report remains independent. Unknown author is fail-closed; current reader response must identify a non-self author. Reads use existing ClubReading and governance topic list/overview. Every prepare/confirm repeats membership and selected target validation; no new transport or command. Default-nil form callback leaves all other forms unchanged.

Account, epoch, reader/access instance, namespace, authorization generation, viewer revision, source snapshot generation, target UUID, scene/background and dismissal fence stale work. Permission errors and missing/duplicate/mismatched targets do not dispatch. Existing report coordinator preserves review, exact request ID, receipt and unknown-outcome locks. Failure while revalidating keeps the immutable draft but clears choices; a later review/confirm must freshly validate.

Registration: three new Xcode source entries and eight EN/zh-Hans catalog keys included. Core tests auto-discovered by Package.swift.

Configuration remains PARTIAL: approved existing club detail/access/topics/topicOverview/cases reads and a matching existing administrative ACTIVITY report grant/durable journal are prerequisites. No configuration, grant or credential is created; canDispatch remains original gate. No backend reads or reports were performed. XCTest/Apple build/UI NOT_RUN in this environment.
