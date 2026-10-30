// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pitchside",
    platforms: [.macOS("14.4")],
    targets: [
        // Pure model/logic code — no UI imports, so it is unit-testable anywhere.
        .target(name: "PitchsideCore", path: "Sources/PitchsideCore"),
        .executableTarget(
            name: "Pitchside",
            dependencies: ["PitchsideCore"],
            path: "Sources/Pitchside"
        ),
        .testTarget(name: "PitchsideCoreTests", dependencies: ["PitchsideCore"], path: "Tests/PitchsideCoreTests"),
    ]
)
