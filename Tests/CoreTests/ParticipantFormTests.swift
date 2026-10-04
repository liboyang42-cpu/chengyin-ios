import XCTest
@testable import QuestifyCore

final class ParticipantFormTests: XCTestCase {
    func testCreateOnlySendsSourceFields() throws {
        var draft = ParticipantFormDraft()
        draft.fullName = "  Fixture Name\n"; draft.mobilePhone = " 13800000000 "
        XCTAssertEqual(try draft.fields(), ["fullName": "Fixture Name", "mobilePhone": "13800000000", "isDefault": "0"])
    }
    func testEditingContactPreservesHiddenMetadataFromDetail() throws {
        let detail = try participantFixture(#"{"id":7,"fullName":"Old","mobilePhone":"13900000000","province":"Fixture Province City District","detailAddress":"Fixture Street","isDefault":"1"}"#)
        var draft = ParticipantFormDraft(detail: detail)
        draft.fullName = "Updated Fixture"; draft.mobilePhone = "13800000000"
        XCTAssertEqual(try draft.fields(), ["id": "7", "fullName": "Updated Fixture", "mobilePhone": "13800000000", "province": "Fixture Province City District", "detailAddress": "Fixture Street", "isDefault": "1"])
        XCTAssertEqual(draft.province, detail.province)
        XCTAssertEqual(draft.detailAddress, detail.detailAddress)
        XCTAssertEqual(draft.isDefault, detail.isDefault)
    }
    func testHiddenFieldsFollowSourceTrimAndOmitEmptyRules() throws {
        let detail = try participantFixture(#"{"id":8,"fullName":"Fixture","mobilePhone":"13800000000","province":"  Region  ","detailAddress":"  ","isDefault":false}"#)
        let fields = try ParticipantFormDraft(detail: detail).fields()
        XCTAssertEqual(fields["province"], "Region")
        XCTAssertNil(fields["detailAddress"])
        XCTAssertNil(fields["address"]); XCTAssertNil(fields["city"]); XCTAssertNil(fields["area"])
        XCTAssertEqual(fields["isDefault"], "0")
    }
    func testSourceValidationRejectsEmptyNameMaskedNonASCIIPrefixedAndMalformedPhone() throws {
        var draft = ParticipantFormDraft()
        draft.fullName = " \n"; draft.mobilePhone = "13800000000"
        XCTAssertEqual(draft.validation, .nameRequired)
        XCTAssertThrowsError(try draft.fields())
        draft.fullName = "Fixture"
        for phone in ["", "123", "138****0000", "+8613800000000", "23800000000", "138000000000", "1３８００００００００", "138 0000000", "1380000000\n0", "10000000000", "11000000000", "12000000000"] {
            draft.mobilePhone = phone
            XCTAssertEqual(draft.validation, .invalidPhone, phone)
            XCTAssertThrowsError(try draft.fields(), phone)
        }
        for prefix in 3...9 {
            draft.mobilePhone = " \t1\(prefix)000000000\n"
            XCTAssertNil(draft.validation)
            XCTAssertEqual(try draft.fields()["mobilePhone"], "1\(prefix)000000000")
        }
    }
    func testDeleteAndDefaultRequestFieldsAreNarrow() throws {
        XCTAssertEqual(try ParticipantMutation.delete(id: 7).fields(), ["id": "7"])
        XCTAssertEqual(try ParticipantMutation.setDefault(id: 7).fields(), ["id": "7", "isDefault": "1"])
        XCTAssertThrowsError(try ParticipantMutation.delete(id: 0).fields())
        XCTAssertThrowsError(try ParticipantMutation.setDefault(id: -1).fields())
    }
}

func participantFixture(_ json: String = #"{"id":7,"fullName":"Fixture Person","mobilePhone":"13800000000","province":"Fixture Region","detailAddress":"Fixture Address","isDefault":true}"#) throws -> ProfileParticipant {
    try JSONDecoder().decode(ProfileParticipant.self, from: Data(json.utf8))
}

func participantDraftFixture() -> ParticipantFormDraft {
    var result = ParticipantFormDraft()
    result.fullName = "Fixture Person"; result.mobilePhone = "13800000000"
    return result
}
