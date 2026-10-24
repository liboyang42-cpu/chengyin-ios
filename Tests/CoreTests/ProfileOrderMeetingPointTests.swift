import XCTest
@testable import QuestifyCore

@MainActor final class ProfileOrderMeetingPointTests: XCTestCase {
    @MainActor private final class Reader: ProfileReading {
        var identity: ProfileReadIdentity? = .init(accountID: 81, epoch: 1, viewerRevision: 2, approvalRevision: UUID())
        var isConfigured = true
        var requests = 0
        func profileOrders() async throws -> [ProfileOrder] { requests += 1; throw APIError.notConfigured }
        func profileOrder(id: Int) async throws -> ProfileOrder { requests += 1; throw APIError.notConfigured }
        func profileParticipants() async throws -> [ProfileParticipant] { requests += 1; throw APIError.notConfigured }
        func profileParticipant(id: Int) async throws -> ProfileParticipant { requests += 1; throw APIError.notConfigured }
        func profileBadges() async throws -> ProfileBadgeWall { requests += 1; throw APIError.notConfigured }
    }
    private func order(id: Int = 41, member: Any = 81, name: Any = "Meeting point", lat: Any = 31.2, lon: Any = 121.5) throws -> ProfileOrder {
        let raw: [String: Any] = ["id":id,"memberId":member,"omsTicket":["meetingPoint":name,"gatherLat":lat,"gatherLng":lon]]
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(ProfileOrder.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private func context(_ reader: Reader, _ value: ProfileOrder? = nil) throws -> ProfileOrderMeetingPointContext {
        try XCTUnwrap(ProfileOrderMeetingPointContext.capture(order: value ?? order(), requestedID: 41, reader: reader))
    }
    private func prepared(_ context: ProfileOrderMeetingPointContext) throws -> (ProfileOrderMeetingPointModel, ProfileOrderMeetingPointReview) {
        let model = ProfileOrderMeetingPointModel(context: context)
        model.appear(current: context, sceneActive: true); model.prepare(current: context)
        return (model, try XCTUnwrap(model.review))
    }
    func testCaptureAndReviewDoNotReadOrOpenAnything() throws {
        let reader = Reader(), context = try context(reader)
        let model = ProfileOrderMeetingPointModel(context: context)
        XCTAssertNil(model.review); XCTAssertFalse(model.canPrepare(current: context))
        model.appear(current: context, sceneActive: true); model.prepare(current: context)
        XCTAssertNotNil(model.review); XCTAssertEqual(reader.requests, 0)
        XCTAssertEqual(context.destination.latitude, 31.2); XCTAssertEqual(context.destination.longitude, 121.5)
    }
    func testMissingZeroNonfiniteAndOutOfRangeCoordinatesHaveNoReview() throws {
        let reader = Reader()
        let coordinates: [(Any, Any)] = [(NSNull(), 121.5 as Any), (0 as Any,121.5 as Any), (31.2 as Any,0 as Any),
                           (91 as Any,121.5 as Any), (31.2 as Any,-181 as Any), ("inf" as Any,121.5 as Any),
                           (31.2 as Any,"nan" as Any)]
        for (lat, lon) in coordinates {
            XCTAssertNil(ProfileOrderMeetingPointContext.capture(order: try order(lat: lat, lon: lon), requestedID: 41, reader: reader))
        }
        XCTAssertNotNil(try context(reader, order(lat: -90, lon: 180)))
        XCTAssertEqual(reader.requests, 0)
    }
    func testWrongOrderMemberMissingOwnerAndDisabledReaderAreRejected() throws {
        let reader = Reader()
        for value in [try order(id: 42), try order(member: 82), try order(member: NSNull())] {
            XCTAssertNil(ProfileOrderMeetingPointContext.capture(order: value, requestedID: 41, reader: reader))
        }
        XCTAssertNil(ProfileOrderMeetingPointContext.capture(order: try order(), requestedID: 0, reader: reader))
        reader.isConfigured = false; XCTAssertNil(ProfileOrderMeetingPointContext.capture(order: try order(), requestedID: 41, reader: reader))
        reader.isConfigured = true; reader.identity = nil
        XCTAssertNil(ProfileOrderMeetingPointContext.capture(order: try order(), requestedID: 41, reader: reader))
    }
    func testSourceTextBytesArePreservedAndNilNameDoesNotInventAddress() throws {
        let reader = Reader(), first = try context(reader, order(name: " e\u{301} "))
        let equivalent = try context(reader, order(name: " é "))
        XCTAssertNotEqual(first, equivalent)
        XCTAssertEqual(Array(first.destination.name.utf8), Array(" e\u{301} ".utf8))
        let unnamed = try context(reader, order(name: NSNull()))
        XCTAssertEqual(unnamed, unnamed); XCTAssertEqual(unnamed.destination.name, ""); XCTAssertNil(unnamed.destination.address)
    }
    func testCurrentExplicitReviewDispatchesExactlyOnce() async throws {
        let reader = Reader(), c = try context(reader), (model, review) = try prepared(c)
        var sent: [PlatformMapDestination] = []
        await model.confirm(review, current: { c }, open: { sent.append($0); return true })
        await model.confirm(review, current: { c }, open: { sent.append($0); return true })
        XCTAssertEqual(sent, [c.destination]); XCTAssertEqual(model.outcome, .opened)
        XCTAssertNil(model.review); XCTAssertFalse(model.isOpening); XCTAssertEqual(reader.requests, 0)
    }
    func testCancelOldReviewCannotCancelOrConfirmReopenedReview() async throws {
        let reader = Reader(), c = try context(reader), (model, old) = try prepared(c)
        XCTAssertTrue(model.cancel(id: old.id)); model.prepare(current: c)
        let fresh = try XCTUnwrap(model.review); XCTAssertNotEqual(old.id, fresh.id)
        XCTAssertFalse(model.cancel(id: old.id)); var calls = 0
        await model.confirm(old, current: { c }, open: { _ in calls += 1; return true })
        XCTAssertEqual(model.review, fresh); XCTAssertEqual(calls, 0)
        await model.confirm(fresh, current: { c }, open: { _ in calls += 1; return true })
        XCTAssertEqual(calls, 1)
    }
    func testWholeIdentityAndReaderReplacementRejectOldReviewBeforeDispatch() async throws {
        let reader = Reader(), value = try order(), initial = try XCTUnwrap(reader.identity)
        let replacements: [ProfileReadIdentity?] = [nil, .init(accountID:82,epoch:1),
            .init(accountID:81,epoch:2,viewerRevision:2,approvalRevision:initial.approvalRevision),
            .init(accountID:81,epoch:1,viewerRevision:3,approvalRevision:initial.approvalRevision),
            .init(accountID:81,epoch:1,viewerRevision:2,approvalRevision:UUID())]
        var calls = 0
        for changed in replacements {
            reader.identity = initial; let c = try context(reader, value), (model, review) = try prepared(c)
            reader.identity = changed
            await model.confirm(review, current: { .capture(order:value,requestedID:41,reader:reader) }, open: { _ in calls += 1; return true })
        }
        reader.identity = initial; let c = try context(reader), (model, review) = try prepared(c)
        let replacement = Reader(); replacement.identity = initial
        await model.confirm(review, current: { .capture(order:value,requestedID:41,reader:replacement) }, open: { _ in calls += 1; return true })
        XCTAssertEqual(calls, 0)
    }
    func testConfigLossAndChangedDestinationRejectOldConfirmation() async throws {
        let reader = Reader(), c = try context(reader), (model, review) = try prepared(c)
        reader.isConfigured = false; var calls = 0
        await model.confirm(review, current: { nil }, open: { _ in calls += 1; return true })
        reader.isConfigured = true; let changed = try context(reader, order(lat: 32.2))
        await model.confirm(review, current: { changed }, open: { _ in calls += 1; return true })
        XCTAssertEqual(calls, 0); XCTAssertNil(model.outcome)
    }
    func testBackgroundAndHiddenReturnNeverReviveAnOldReview() async throws {
        let reader = Reader(), c = try context(reader)
        for hidden in [false,true] {
            let (model, old) = try prepared(c); var calls = 0
            if hidden { model.disappear(); model.sceneChanged(active:true,current:c) }
            else { model.sceneChanged(active:false,current:c); model.sceneChanged(active:true,current:c) }
            await model.confirm(old,current:{c},open:{_ in calls += 1;return true})
            XCTAssertNil(model.review); XCTAssertEqual(calls,0)
            model.appear(current:c,sceneActive:true); model.prepare(current:c)
            let fresh = try XCTUnwrap(model.review); XCTAssertNotEqual(old.id,fresh.id)
        }
    }
    func testLateCompletionAfterOwnerRetirementCannotPublishOrReopen() async throws {
        let reader = Reader(), c = try context(reader), (model, review) = try prepared(c)
        var pending: CheckedContinuation<Bool,Never>?, calls = 0
        let task = Task { await model.confirm(review,current:{c},open:{_ in
            calls += 1; return await withCheckedContinuation { pending = $0 }
        }) }
        for _ in 0..<100 where pending == nil { await Task.yield() }
        let continuation = try XCTUnwrap(pending); model.retire()
        continuation.resume(returning:true); await task.value
        XCTAssertEqual(calls,1); XCTAssertNil(model.outcome); XCTAssertNil(model.review)
        model.appear(current:c,sceneActive:true); XCTAssertFalse(model.canPrepare(current:c))
    }
    func testFailedLaunchRequiresAnotherExplicitReviewAndNeverRetriesItself() async throws {
        let reader = Reader(), c = try context(reader), (model, first) = try prepared(c); var calls = 0
        await model.confirm(first,current:{c},open:{_ in calls += 1;return false})
        XCTAssertEqual(calls,1); XCTAssertEqual(model.outcome,.failed); XCTAssertNil(model.review)
        await model.confirm(first,current:{c},open:{_ in calls += 1;return true}); XCTAssertEqual(calls,1)
        model.prepare(current:c); let next = try XCTUnwrap(model.review)
        XCTAssertNotEqual(first.id,next.id); XCTAssertNil(model.outcome)
        await model.confirm(next,current:{c},open:{_ in calls += 1;return true}); XCTAssertEqual(calls,2)
    }
    func testQueuedCancelledTaskCannotDispatchEvenWithCurrentOwner() async throws {
        let reader = Reader(), c = try context(reader), (model, review) = try prepared(c); var calls = 0
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.confirm(review,current:{c},open:{_ in calls += 1;return true})
        }
        await task.value; XCTAssertEqual(calls,0); XCTAssertNil(model.outcome)
    }
}
