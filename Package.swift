// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "Nook", targets: ["Nook"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "NookCore"),
        .target(
            name: "NookRuntime",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc"])],
            linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("ApplicationServices")]
        ),
        .executableTarget(
            name: "Nook",
            dependencies: ["NookCore", "NookRuntime", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "NookCoreTests", dependencies: ["NookCore"])
    ],
    swiftLanguageModes: [.v5]
)
