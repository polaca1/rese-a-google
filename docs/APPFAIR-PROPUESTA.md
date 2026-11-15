# Proposed app: reviewNfcGo — business visits, NFC review links and sales

Hello App Fair community,

I maintain **reviewNfcGo** (GitHub: **@polaca1**) and would like to introduce it for initial eligibility feedback before preparing a catalog submission.

The app helps independent businesses and field sellers select nearby venues, open their Google review pages, prepare NFC review links, plan return visits, and manage inventory, sales and quotations for physical NFC cards and stands. Sales are bookkeeping for physical products, rather than in-app purchases. The app has no advertising, tracking SDKs or paid feature unlocks.

## Source and current candidate

- Public source: https://github.com/polaca1/rese-a-google/tree/day/native-ui
- iPhone candidate, version 7.3.1 (47): https://github.com/polaca1/rese-a-google/releases/tag/reviewnfcgo-day-7.3.1-build47
- App source is MIT licensed; dependencies retain their own license notices, including Day's MPL-2.0 components.
- The main screens and navigation use **Day/UIKit**. Existing headless Swift services handle accounts, persistence and business rules; MapKit is mounted through a native Day renderer. The old SwiftUI application package is not linked. Widgets and Live Activities use Apple's WidgetKit APIs.
- The client uses Supabase for account access and account-scoped synchronization. NFC writing currently hands the review URL to **Simply NFC**, an external app that is not bundled with the project.

## Readiness and remaining work

This is an introductory proposal, rather than a release-ready catalog request. Native/Rust checks pass, and an unsigned arm64 iPhone archive has been compiled with Xcode 26.3 using a temporary XcodeGen host with the real Day Runner. Browser walkthroughs use synthetic data and are not iPhone screenshots. Physical installation and the complete iPhone flows remain to be verified.

Before a formal submission, the remaining work includes:

- Completing a functional Android version with equivalent features; the current native services are iOS-specific.
- Validating the conventional Day publication build and native walkthroughs for both targets.
- Completing server-side account deletion, privacy/retention details, the final dependency/asset review, and any authentication changes needed for Apple's review rules.
- Setting up the dedicated organization/repository, App Fair Publisher and project website required by the submission process.

Would this type of business utility fit App Fair's inclusion criteria? In particular, should the external Simply NFC handoff be replaced with an in-app native NFC implementation before submission, and is the documented Day/native-services approach acceptable once both platforms are supported?

Thank you for considering the proposal.

— @polaca1, reviewNfcGo maintainer
