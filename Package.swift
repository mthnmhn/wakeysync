// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WakeySync",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "wakeyctl", targets: ["WakeySync"]),
    ],
    targets: [
        .executableTarget(
            name: "WakeySync",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOBluetooth"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "WakeySync-Info.plist",
                ]),
            ]
        ),
    ]
)
