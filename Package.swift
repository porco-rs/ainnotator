// swift-tools-version: 6.2
// AInnotator: a pure core with three thin shells. No external dependencies.
import PackageDescription

let package = Package(
    name: "AInnotator",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "AInnotator", targets: ["AInnotator"]),
    ],
    targets: [
        // State, reducer, marks, payload. Foundation only, testable anywhere in seconds.
        .target(name: "AICore"),
        // Layer tree per display and the card. No AppKit.
        .target(name: "AIRender", dependencies: ["AICore"]),
        // Capture, hotkeys, clipboard, files, context. Talks to the system, so it needs a real macOS session.
        .target(name: "AIPlatform", dependencies: ["AICore"]),
        // Status menu, panels, input, wiring.
        .executableTarget(
            name: "AInnotator",
            dependencies: ["AICore", "AIRender", "AIPlatform"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "AICoreTests", dependencies: ["AICore"], exclude: ["Fixtures"]),
        .testTarget(name: "AIRenderTests", dependencies: ["AIRender"]),
        .testTarget(name: "AIPlatformTests", dependencies: ["AIPlatform", "AICore"]),
    ]
)
