// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Ynp97TodoInbox",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Ynp97TodoInbox", targets: ["Ynp97TodoInbox"])
    ],
    targets: [
        .executableTarget(name: "Ynp97TodoInbox")
    ]
)
