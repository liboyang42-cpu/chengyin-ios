"""Source-shape regression only; Apple Swift compilation remains authoritative."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]


class CreatorObservationContracts(unittest.TestCase):
    def test_observable_lifecycle_state_uses_single_variable_declarations(self):
        # ObservationTracked accessor macros reject a multi-binding var declaration.
        for kind in ("Consent", "Pending"):
            with self.subTest(controller=kind):
                name = f"WorkshopCreator{kind}Controller"
                source = (ROOT / "Core" / f"{name}.swift").read_text()
                marker = f"@MainActor @Observable public final class {name} {{"
                self.assertIn(marker, source)
                body = source.split(marker, 1)[1]
                self.assertNotIn("@ObservationIgnored", body)
                for field, swift_type in (
                    ("appearance", f"WorkshopCreator{kind}Appearance"),
                    ("lifetime", "WorkshopCreatorConsentLifetime"),
                ):
                    declaration = f"    private var {field}: {swift_type}?"
                    self.assertEqual(body.splitlines().count(declaration), 1)


if __name__ == "__main__":
    unittest.main()
