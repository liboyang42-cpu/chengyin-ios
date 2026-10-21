"""Executable mirror of Core/RewardPledge.swift plus source anchors. Swift itself is NOT_RUN here."""
import hashlib
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SEP = "\x1e"
DIGEST = "4519c0b051d2fda04db36e4e9e7042d27ab76f0746807aed50f34c1308eb0494"


def request_id(business_key):
    return hashlib.sha256(business_key.encode()).hexdigest()


def business_key(rule, eligibility, beneficiary, scope):
    return SEP.join([rule, eligibility, beneficiary, scope])


class Machine:
    def __init__(self, account, store, policy):
        self.account = account
        self.store = store
        self.policy = dict(policy)
        self.generation = 1
        self.unknowns = []
        self.grant = None
        self.draft = None
        self.frozen = None
        self.case = None
        self.confirmed = None
        self.preview = None
        self.routes = []

    def scope(self):
        return (self.account, self.store, self.generation)

    def read_terms(self, seen, **server):
        if seen != self.scope():
            return "stale"
        if server.get("client_complete"):
            return "clientComplete"
        caps = server["capabilities"]
        if caps["cash"] or caps["random"] or caps["guaranteed"]:
            return "switches"
        if not caps["nonCash"] or self.policy.get("nonCashEnabled") is not True:
            return "nonCashEnabled"
        if not server["rule"] or server["rule"] != self.policy.get("ruleVersion"):
            return "ruleVersion"
        if not server["validity"] or server["validity"] != self.policy.get("validity"):
            return "validity"
        if server["quota"] is None or server["quota"] != self.policy.get("quota"):
            return "quota"
        if not server["limit"] or not server["eligibility"] or server["eligibility"] == "true":
            return "eligibility" if not server["eligibility"] or server["eligibility"] == "true" else "quota"
        if server["beneficiary"] != self.account or server["store"] != self.store:
            return "owner" if server["beneficiary"] != self.account else "store"
        self._terms = server
        return None

    def confirm(self, seen):
        if seen != self.scope():
            return "stale", None
        key = business_key(self._terms["rule"], self._terms["eligibility"], self._terms["beneficiary"], self._terms["scope"])
        intent = {"owner": self.account, "store": self.store, "key": key, "requestID": request_id(key), "kind": "claim"}
        self.confirmed = key
        return None, intent

    def lose(self, intent, seen):
        if seen != self.scope() or intent["requestID"] != request_id(intent["key"]):
            return "requestID"
        if any(row["key"] == intent["key"] and row["requestID"] != intent["requestID"] for row in self.unknowns):
            return "requestID"
        if not any(row["key"] == intent["key"] for row in self.unknowns):
            self.unknowns.append(dict(intent))
        return None

    def recover(self, proposed, seen):
        if seen != self.scope():
            return "stale", None
        row = self.unknowns[-1]
        if proposed != row["requestID"] or row["requestID"] != request_id(row["key"]):
            return "requestID", None
        return None, dict(row)

    def accept(self, award, terms_version, terms_text, intent, seen):
        if seen != self.scope() or not terms_text or intent["requestID"] != request_id(intent["key"]):
            return "requestID"
        if self.confirmed != intent["key"] and not any(row["requestID"] == intent["requestID"] for row in self.unknowns):
            return "confirm"
        self.grant = {"award": award, "terms": terms_text, "version": terms_version, "state": "GRANTED_UNREDEEMED"}
        self.unknowns = [row for row in self.unknowns if row["requestID"] != intent["requestID"]]
        return None

    def refresh(self):
        source = self.policy.get("readSource")
        if source == "plannedController":
            return "api/rewards/noncash"
        if source == "couponHistory":
            return "api/coupon/myrecvlist"
        return None


def approved():
    return {"ruleVersion": "rule-a", "validity": "server-window", "quota": 2, "nonCashEnabled": True,
            "readSource": "plannedController", "merchantEvidence": "evidence-1", "serviceCapacity": 4, "refusalPolicy": "manual"}


def caps(cash=False, random=False, guaranteed=False, non_cash=True):
    return {"cash": cash, "random": random, "guaranteed": guaranteed, "nonCash": non_cash}


class RewardPledgeContractChecks(unittest.TestCase):
    def test_request_id_vector_matches_the_swift_fixture(self):
        key = business_key("rule-a", "fact-9", "42", "scope-theme")
        self.assertEqual(request_id(key), DIGEST)
        swift = (ROOT / "Tests/CoreTests/RewardPledgeTests.swift").read_text()
        self.assertIn(DIGEST, swift)

    def test_same_event_does_not_mint_a_new_request_and_recovery_queries_it(self):
        machine = Machine("42", "7", approved())
        seen = machine.scope()
        self.assertIsNone(machine.read_terms(seen, rule="rule-a", limit="two left", validity="server-window",
                                              eligibility="fact-9", beneficiary="42", store="7", scope="scope-theme",
                                              quota=2, client_complete=False, capabilities=caps()))
        _, first = machine.confirm(seen)
        _, second = machine.confirm(seen)
        self.assertEqual(first["requestID"], second["requestID"])
        self.assertIsNone(machine.lose(first, seen))
        self.assertEqual(machine.recover("b" * 64, seen)[0], "requestID")
        error, recovered = machine.recover(first["requestID"], seen)
        self.assertIsNone(error)
        self.assertEqual(recovered["requestID"], DIGEST)
        self.assertIsNone(machine.accept("award-1", "t1", "frozen terms", recovered, seen))
        self.assertEqual(machine.grant["state"], "GRANTED_UNREDEEMED")
        self.assertEqual(machine.unknowns, [])
        self.assertEqual(machine.refresh(), "api/rewards/noncash")

    def test_unset_policy_and_switches_fail_closed(self):
        machine = Machine("42", "7", {})
        seen = machine.scope()
        fields = dict(rule="rule-a", limit="two left", validity="server-window", eligibility="fact-9",
                      beneficiary="42", store="7", scope="scope-theme", quota=2, client_complete=False, capabilities=caps())
        self.assertEqual(machine.read_terms(seen, **fields), "nonCashEnabled")
        machine.policy = approved()
        fields["capabilities"] = caps(cash=True)
        self.assertEqual(machine.read_terms(seen, **fields), "switches")
        fields["capabilities"] = caps()
        fields["client_complete"] = True
        self.assertEqual(machine.read_terms(seen, **fields), "clientComplete")
        fields["client_complete"] = False
        fields["quota"] = None
        self.assertEqual(machine.read_terms(seen, **fields), "quota")
        self.assertIsNone(Machine("42", "7", {}).policy.get("quota"))

    def test_account_generation_and_coupon_source_are_isolated(self):
        machine = Machine("42", "7", approved())
        seen = machine.scope()
        machine.read_terms(seen, rule="rule-a", limit="two left", validity="server-window", eligibility="fact-9",
                           beneficiary="42", store="7", scope="scope-theme", quota=2, client_complete=False, capabilities=caps())
        _, intent = machine.confirm(seen)
        machine.lose(intent, seen)
        machine.generation += 1
        self.assertEqual(machine.recover(intent["requestID"], seen)[0], "stale")
        machine.policy["readSource"] = None
        self.assertIsNone(machine.refresh())
        machine.policy["readSource"] = "couponHistory"
        self.assertEqual(machine.refresh(), "api/coupon/myrecvlist")
        self.assertNotEqual(machine.refresh(), "api/rewards/noncash")

    def test_swift_source_keeps_the_contract(self):
        source = (ROOT / "Core/RewardPledge.swift").read_text()
        pool = (ROOT / "Core/SponsoredRewardPool.swift").read_text()
        service = (ROOT / "Core/NonCashRewardService.swift").read_text()
        city = (ROOT / "Core/CityNodeRedemption.swift").read_text()
        reward = (ROOT / "Core/NonCashReward.swift").read_text()
        for name in ["ruleVersion", "validity", "quota", "reserveShare", "serviceCapacity", "merchantEvidence",
                     "minorEligible", "antiAbuseReview", "returnToPool", "topUp", "refusalPolicy", "nonCashEnabled", "readSource"]:
            self.assertIn("public var " + name + ":", source)
        self.assertIn("public static let unset = RewardPledgePolicy()", source)
        self.assertNotIn("= true", source.split("struct RewardPledgePolicy", 1)[1].split("public enum RewardPledgeDependency", 1)[0])
        for forbidden in ["30天", "每季", "30 days", "validDays", "quota = 1", "cash = true", "random = true", "guaranteed = true", "URLSession"]:
            self.assertNotIn(forbidden, source)
            self.assertNotIn(forbidden, pool)
        self.assertIn("capabilities.cash == false && capabilities.random == false && capabilities.guaranteed == false", pool)
        self.assertIn('public var nonCash = false', pool)
        self.assertIn('public var cash = false', pool)
        self.assertIn('public var random = false', pool)
        self.assertIn('public var guaranteed = false', pool)
        self.assertIn("ApiRewardPledgeController", source)
        self.assertIn("ApiNonCashRewardController", source)
        self.assertIn("cursor/w17-i-reward-pledge", source)
        self.assertIn('stockReservationOwner = "W06"', source)
        self.assertEqual(re.findall(r'public static let staffRedeem = \[(.*?)\]', source, re.S)[0].replace(" ", "").split(","),
                         ["couponQRToken", "couponStatus", "couponVerification", "couponRecvList"])
        self.assertIn('case .plannedController: return plannedNonCashList', source)
        self.assertIn('case .couponHistory: return couponRecvList', source)
        self.assertIn('case nil: return nil', source)
        self.assertIn('public let ownerID: String', source)
        self.assertNotIn("token", source[source.index("struct RewardPledgeUnknown"):source.index("public struct RewardPledgeTerms")])
        self.assertIn('state: "GRANTED_UNREDEEMED"', source)
        self.assertIn('status: "DRAFT"', source)
        self.assertIn('status: "SUBMITTED"', source)
        self.assertIn('status: "FROZEN"', source)
        self.assertIn('status: "WITHDRAWN"', source)
        self.assertIn('reason: "EXPIRED"', source)
        self.assertIn('reason: "REFUSED"', source)
        self.assertIn("generation &+ 1", source)
        self.assertIn("proposedRequestID == row.requestID", source)
        self.assertIn("clientComplete", source)
        self.assertIn('.closed("W06")', source)
        self.assertIn('.closed("reserveShare")', source)
        self.assertIn("api/verify/citynode/redeem", city)
        self.assertNotIn("api/verify/citynode/redeem", source)
        self.assertIn("public static func acceptsPledgeRedeem(_ path: String) -> Bool { false }", city)
        self.assertIn('get(path: "api/rewards/noncash"', service)
        self.assertIn('RewardPledgeRoutes.listPath(source) == "api/rewards/noncash"', service)
        self.assertNotIn("qr-token", service)
        self.assertIn("isGrantedUnredeemed", reward)
        self.assertIn("matchesPledgeRefresh", reward)
        self.assertIn("rewards.pledge.confirm", (ROOT / "App/RewardPledgeViews.swift").read_text())
        self.assertIn("rewards.pledge.recover", (ROOT / "App/RewardPledgeViews.swift").read_text())
        project = (ROOT / "Questify.xcodeproj/project.pbxproj").read_text()
        self.assertIn("Core/RewardPledge.swift", project)
        self.assertIn("App/RewardPledgeViews.swift", project)
        self.assertIn("api/rewards/noncash/claims", source)
        self.assertIn("api/rewards/noncash/claims/recover", source)
        self.assertIn("api/rewards/noncash/versions/", source)
        self.assertIn("api/reward-pledge/fulfilment/redeem", source)
        self.assertIn("api/reward-pledge/fulfilment/preview", source)
        self.assertNotIn("ownerId", source)
        self.assertIn('"confirm": "true"', source)
        views = (ROOT / "App/RewardPledgeViews.swift").read_text()
        self.assertNotIn("Not open", views)
        self.assertNotIn('Text(verbatim: "Claim")', views)
        self.assertIn("rewards.unavailable", views)
        self.assertIn("rewards.pledge.noSubject", views)
        self.assertIn("entry.current() == caller", views)
        session = (ROOT / "App/AppSession.swift").read_text()
        self.assertNotIn("permitsWrites: true", session)
        self.assertIn("nonCashRewardClaimApproved", session)
        self.assertIn("nonCashRewardPreviewApproved", session)
        self.assertIn("nonCashRewardRedeemApproved", session)
        self.assertNotIn('Text(verbatim: "Redeem voucher")', (ROOT / "App/NativeVerificationView.swift").read_text())
        self.assertIn("pledge.current()?.preview == true", (ROOT / "App/NativeVerificationView.swift").read_text())
        rewards = (ROOT / "App/NonCashRewardViews.swift").read_text()
        self.assertIn("if !reader.isOfflineExample", rewards)
        self.assertIn("RewardPledgeClaimHost(entry: pledge)", rewards)
        self.assertNotIn("rewards.pledge.list", rewards)
        staff = (ROOT / "App/RewardPledgeViews.swift").read_text()
        source = (ROOT / "Core/RewardPledge.swift").read_text()
        self.assertIn("api/reward-pledge/fulfilment/awards", source)
        self.assertIn("api/reward-pledge/drafts", source)
        self.assertNotIn("api/rewards/pledge/draft", source)
        self.assertNotIn("api/rewards/pledge/submit", source)
        draft = source.split("func draft(", 1)[1].split("func submit(", 1)[0]
        self.assertNotIn("storeId", draft)
        self.assertNotIn("merchantMemberId", draft)
        self.assertIn('"rewardKind": "NON_CASH"', draft)
        self.assertIn("loadStoreAwards", staff)
        self.assertNotIn('TextField("rewards.pledge.award"', staff)
        self.assertNotIn('TextField("rewards.pledge.pledgeID"', staff)
        self.assertIn("rewardPledgePermit", (ROOT / "App/AppCompositionRoot.swift").read_text())
        self.assertIn("nonCashRewardDraftApproved", session)
        self.assertIn("nonCashRewardCaseApproved", session)
        self.assertIn("nonCashRewardStatsApproved", session)
        self.assertIn('allows("merchant:coupon:manage")', (ROOT / "App/NativeVerificationView.swift").read_text())

    def test_unknown_record_persists_only_the_minimal_fields(self):
        body = (ROOT / "Core/RewardPledge.swift").read_text()
        struct = body.split("public struct RewardPledgeUnknown", 1)[1].split("public struct RewardPledgeTerms", 1)[0]
        fields = re.findall(r"public let (\w+):", struct)
        self.assertEqual(fields, ["ownerID", "storeID", "businessKey", "requestID", "kind"])


if __name__ == "__main__":
    unittest.main()
