// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription

let package = Package(
    name: "ReviewNfcGoViews",
    platforms: [.iOS(.v16)],
    products: [.library(name: "ReviewNfcGoViews", targets: ["ReviewNfcGoViews"])],
    targets: [.target(name: "ReviewNfcGoViews", resources: [
        .process("Assets.xcassets"), .process("PrivacyInfo.xcprivacy"),
        .process("ThirdPartyNotices.txt")
    ])]
)
