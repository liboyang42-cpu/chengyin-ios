# Registration contracts and native scanner integration

This slice contains no order creation or payment execution. Registration contract models preserve quote signatures, retry-stable request IDs, waitlist pairs and nullable Decimal amounts. Missing payParams never proves a paid/free success; authoritative order readback remains mandatory.

The scanner is an Apple VisionKit / UIKit controller hosted in SwiftUI. It remains outside production navigation pending business validation of QR payloads. A DEBUG-only UI-test launch argument presents it only to test Simulator's unsupported state and cancellation. Real QR recognition, permission grant/denial and foreground/background capture require supported physical hardware.

The project includes English/Chinese scanner copy and localized InfoPlist camera purpose text. In-app language controls app-owned screens; system permission dialogs follow iOS language settings. No tool requested camera permission during development.

Entry UI tests now wait for a hittable Settings button and the expected Settings navigation bar before selecting language, and add repeated cold-launch presentation coverage. A previous otherwise identical activity-model run failed once because the Settings sheet did not open after a synthesized tap. The rerun and stronger synchronization must be tracked, rather than silently describing the original run as successful.

Validation at authoring time: Python structure/resource checks and six importer tests pass. New Swift tests, VisionKit compilation and five simulator UI scenarios await exact-revision CI. No scanner, registration or real-backend completion claim is made.
