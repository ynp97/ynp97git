// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DiaryViewer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DiaryViewer",
            dependencies: [],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "DiaryViewerTests",
            dependencies: ["DiaryViewer"],
            resources: [
                .copy("Fixtures")]
        )
    ]
)
