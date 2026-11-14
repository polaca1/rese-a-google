// swift-tools-version: 5.9
// SPDX-License-Identifier: MIT
import PackageDescription
let package = Package(name: "ReviewNfcGoServices", platforms: [.iOS(.v16)],
    products: [.library(name: "ReviewNfcGoServices", targets: ["ReviewNfcGoServices"])],
    targets: [.target(name: "ReviewNfcGoServices", resources: [.process("PrivacyInfo.xcprivacy"), .process("ThirdPartyNotices.txt")])])
