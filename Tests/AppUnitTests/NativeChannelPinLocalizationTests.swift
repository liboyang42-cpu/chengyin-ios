import XCTest
@testable import Questify

@MainActor final class NativeChannelPinLocalizationTests: XCTestCase {
    private let en = NativeChannelPinLocalization(locale: Locale(identifier: "en"))
    private let zh = NativeChannelPinLocalization(locale: Locale(identifier: "zh-Hans"))
    func testTypedPinOperationsUseSelectedLanguageWithoutChangingWireValues() {
        XCTAssertEqual(en.operation(.pin), "Pin"); XCTAssertEqual(zh.operation(.pin), "置顶")
        XCTAssertEqual(en.operation(.unpin), "Unpin"); XCTAssertEqual(zh.operation(.unpin), "取消置顶")
        XCTAssertEqual(en.operation(.sort), "Reorder pinned messages")
        XCTAssertEqual(NativeChannelMessageOperation.pin.rawValue, "PIN")
        XCTAssertEqual(NativeChannelMessageOperation.unpin.rawValue, "UNPIN")
        XCTAssertEqual(NativeChannelMessageOperation.sort.rawValue, "PIN_SORT")
    }
    func testUnrelatedOriginalOperationsAreNotReinterpreted() {
        for operation in [NativeChannelMessageOperation.edit, .recall] {
            XCTAssertEqual(en.operation(operation), operation.rawValue)
            XCTAssertEqual(zh.operation(operation), operation.rawValue)
        }
    }
    func testOriginalIDsAndVersionKeepExactDecimalBytesInBothLanguages() {
        let id = "9007199254740993", message = "9007199254740995", version = "9007199254740997"
        XCTAssertEqual(en.format("p23.confirm.detail", id, message, version), "Channel \(id) · Message \(message) · Version \(version). This only unpins the message; it does not delete it. If the outcome is unknown, only look up the original request.")
        XCTAssertEqual(zh.format("p23.confirm.detail", id, message, version), "频道 \(id) · 消息 \(message) · 版本 \(version)。仅取消置顶，不删除原消息；结果不明时只查询原请求。")
    }
    func testOriginalUUIDDoesNotBecomeFormatSyntaxOrNewRequest() {
        let uuid = "original-%@-0001"
        XCTAssertEqual(en.format("p23.receipt", uuid), "Receipt for the same UUID: \(uuid)")
        XCTAssertEqual(zh.format("p23.pending", uuid, zh.operation(.unpin), "42"), "待核原请求：\(uuid) · 取消置顶 · 消息 42")
    }
    func testCurrentReadbackStatesKeepReceiptAndCurrentDistinct() {
        XCTAssertEqual(en.text("p23.current.reading"), "Current pinned list: an independent read is in progress.")
        XCTAssertEqual(en.text("p23.current.matches"), "Current pinned list: matches this operation’s target; this is not the original request receipt.")
        XCTAssertEqual(en.text("p23.current.differs"), "Current pinned list: differs from this operation’s target, possibly due to later changes; the original request outcome remains confirmed.")
        XCTAssertEqual(en.text("p23.current.failed"), "Current pinned list: a valid readback is not yet available; the original request outcome is unchanged.")
        XCTAssertEqual(en.text("p23.pending.explanation"), "The current list cannot establish whether the request was applied. Look up its receipt using the original UUID; do not resend.")
    }
    func testLanguageVariantsDoNotRetainPreviousLanguage() {
        XCTAssertEqual(NativeChannelPinLocalization(locale: Locale(identifier: "en_US")).text("p23.reload"), "Reload pinned messages")
        XCTAssertEqual(NativeChannelPinLocalization(locale: Locale(identifier: "zh-Hans-CN")).text("p23.reload"), "重新读取置顶")
        XCTAssertEqual(NativeChannelPinLocalization(locale: Locale(identifier: "en_GB")).text("p23.reload"), "Reload pinned messages")
    }
}
