// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiaryViewer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .target(name: "DiaryCore"),
        .executableTarget(
            name: "DiaryViewer",
            dependencies: ["DiaryCore"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(name: "DiaryCoreTests", dependencies: ["DiaryCore"]),
        .testTarget(
            name: "DiaryViewerTests",
            dependencies: ["DiaryViewer"],
            resources: [
                .copy("Fixtures")]
        )
    ]
)
