// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Pulse",
            targets: ["Pulse"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Pulse",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SystemConfiguration")
            ]
        )
    ]
)
