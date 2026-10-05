#!/usr/bin/env python3
"""Offline SOURCE checks only: these do not compile Swift or execute authentication."""
import base64
import hashlib
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(name):
    return (ROOT / name).read_text()


class USAppleClientSourceChecks(unittest.TestCase):
    def test_production_host_does_not_construct_us_apple_adapter(self):
        # Integrated modules legitimately change shared files. Preserve the actual
        # security invariant rather than pinning the entire App to an old commit.
        for name in ["App/AppSession.swift", "App/QuestifyApp.swift"]:
            for symbol in ["USAppleService(", "USAppleCoordinator(", "USAppleSignInModel("]:
                self.assertNotIn(symbol, read(name))
        self.assertIn("verifiedCapabilities:[]", read("App/RegionalLaunchConfiguration.swift"))

    def test_production_gate_and_no_provider_scopes(self):
        self.assertIn("public static let enabled = false", read("Core/USAppleContracts.swift"))
        native = read("App/USAppleNativeAuthorizer.swift")
        self.assertIn("guard USAppleProductionGate.enabled else", native)
        self.assertIn("appleRequest.requestedScopes = []", native)
        self.assertIn("appleRequest.nonce = request.nonce", native)
        self.assertIn("appleRequest.state = request.state", native)
        self.assertIn("guard self.controller === controller else", native)

    def test_exact_routes_empty_challenge_and_three_exchange_fields(self):
        service = read("Core/USAppleService.swift")
        self.assertEqual(re.findall(r'"(api/us/auth/[^"]+)"', service),
                         ["api/us/auth/apple/challenges", "api/us/auth/apple/exchange", "api/us/auth/session"])
        self.assertIn('body: Data("{}".utf8)', service)
        declaration = re.search(r"struct ExchangeBody: Encodable \{([^}]+)\}", service).group(1)
        self.assertEqual(re.findall(r"let (\w+):", declaration), ["challengeId", "state", "identityToken"])
        post_adapter = service.split("public func currentAccount(", 1)[0]
        self.assertNotIn('forHTTPHeaderField: "Authorization"', post_adapter)
        self.assertNotIn("AuthService(", service)
        self.assertNotIn("AuthChannelService(", service)
        self.assertIn("request.httpShouldHandleCookies = false", service)

    def test_protected_session_get_bearer_server_realm_and_null_avatar_contract(self):
        service = read("Core/USAppleService.swift")
        proof = service.split("public func currentAccount(", 1)[1]
        self.assertIn('guard admitted else', proof)
        self.assertIn('request.httpMethod = "GET"', proof)
        self.assertIn('request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")', proof)
        self.assertNotIn('request.httpBody =', proof)
        self.assertIn('response.data.market == "US"', proof)
        self.assertIn('response.data.realm == deployment.realm', proof)
        self.assertIn('realm: response.data.realm', proof)
        self.assertIn('response.data.account.id > 0', proof)
        self.assertIn('if status == 401 { throw USAppleError.invalidIdentity }', proof)
        self.assertIn('"US_SESSION_UNAVAILABLE"', proof)
        self.assertIn('guard status == 200, envelope.errorCode == nil', proof)
        self.assertIn('guard values.contains(.avatar)', service)
        self.assertIn('decodeIfPresent(String.self, forKey: .avatar) ?? ""', service)

    def test_nonce_fixture_is_real_lowercase_sha256_of_raw_nonce(self):
        fixtures = read("Tests/CoreTests/USAppleServiceTests.swift")
        expected = re.search(r'static let digest = "([0-9a-f]{64})"', fixtures).group(1)
        raw_nonce = base64.urlsafe_b64encode(bytes([2]) * 32).decode().rstrip("=")
        self.assertEqual(len(raw_nonce), 43)
        self.assertEqual(hashlib.sha256(raw_nonce.encode()).hexdigest(), expected)
        self.assertIn("SHA256.hash(data: Data(rawNonce.utf8))", read("Core/USAppleContracts.swift"))

    def test_all_issue_keys_have_bilingual_client_only_entries(self):
        contract = read("Core/USAppleContracts.swift")
        keys = set(re.findall(r'return "(usApple\.[^"]+)"', contract))
        entries = json.loads(read("docs/us-apple-client-localizations.json"))
        self.assertTrue(keys.issubset(entries))
        for key, localized in entries.items():
            self.assertTrue(key.startswith("usApple."))
            self.assertEqual(set(localized), {"en", "zh-Hans"})
            self.assertTrue(all(value.strip() for value in localized.values()))

    def test_only_client_allowlisted_profile_is_reconstructed(self):
        service = read("Core/USAppleService.swift")
        fields = re.search(r"struct SafeProfile: Codable \{([^}]+)\}", service).group(1)
        self.assertEqual(re.findall(r"let (\w+):", fields), ["id", "userType", "avatar", "nickname", "role"])
        self.assertIn("JSONEncoder().encode(response.data)", service)
        coordinator = read("Core/USAppleCoordinator.swift")
        self.assertLess(coordinator.index("credential.state == attempt.state"), coordinator.index("await service.exchange("))
        self.assertLess(coordinator.index("await verifyCurrentAccount("), coordinator.index("try commitLogin("))
        self.assertIn("verified.realm == deployment.realm", coordinator)
        self.assertIn("verified.account.id == candidate.account.id", coordinator)
        self.assertIn("currentSession() == snapshot", coordinator)

    def test_no_persistence_or_actual_provider_configuration_in_slice(self):
        source = "\n".join(p.read_text() for directory in ["Core", "App"] for p in (ROOT / directory).glob("USApple*.swift"))
        for forbidden in ["UserDefaults.standard", "SecItemAdd(", "SecItemUpdate(", "print(", "Logger(", "os_log(",
                          "appleid.apple.com", "api/login/apple", "api/userInfo", "api/login/phone"]:
            self.assertNotIn(forbidden, source)
        self.assertIn("#if DEBUG", read("Core/USAppleCoordinator.swift"))
        self.assertIn("#if DEBUG", read("Core/USAppleService.swift"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
