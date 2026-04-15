// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "TimeCalculatorMenuBar",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "TimeCalculatorMenuBar",
            targets: ["TimeCalculatorMenuBar"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "TimeCalculatorMenuBar"
        ),
    ]
)
