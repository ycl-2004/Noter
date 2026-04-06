// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NotesCurator",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "NotesCurator"),
        .testTarget(
            name: "NotesCuratorTests",
            dependencies: ["NotesCurator"]
        ),
    ]
)
