// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PokecaRecords",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PokecaRecords", targets: ["PokecaRecords"])
    ],
    targets: [
        .executableTarget(
            name: "PokecaRecords",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
