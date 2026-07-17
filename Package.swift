// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SJMediaCacheServer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SJMediaCacheServer",
            targets: ["SJMediaCacheServer"]
        )
    ],
    targets: [
        .target(
            name: "SJSQLite3",
            path: "Sources/SJSQLite3",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("Core"),
                .headerSearchPath("Protocol")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "SJMediaCacheServer",
            dependencies: ["SJSQLite3"],
            path: "SJMediaCacheServer",
            exclude: ["Assets"],
            publicHeadersPath: "SPMInclude",
            cSettings: [
                .headerSearchPath("Core"),
                .headerSearchPath("Core/Asset"),
                .headerSearchPath("Core/Asset/FILE"),
                .headerSearchPath("Core/Asset/HLS"),
                .headerSearchPath("Core/Asset/LocalFile"),
                .headerSearchPath("Core/Cache"),
                .headerSearchPath("Core/Common"),
                .headerSearchPath("Core/Download"),
                .headerSearchPath("Core/Export"),
                .headerSearchPath("Core/Prefetch"),
                .headerSearchPath("Core/TcpSocketServer"),
                .headerSearchPath("Core/Task")
            ]
        ),
        .testTarget(
            name: "SJMediaCacheServerTests",
            dependencies: ["SJMediaCacheServer"]
        )
    ]
)
