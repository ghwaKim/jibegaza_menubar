// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TimeCalculatorMenuBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "TimeCalculatorMenuBar", targets: ["TimeCalculatorMenuBar"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .executableTarget(
            name: "TimeCalculatorMenuBar",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TimeCalculatorMenuBarTests", dependencies: ["TimeCalculatorMenuBar"]),
    ]
)
