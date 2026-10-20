// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SunucuDurum",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "SunucuDurum",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
