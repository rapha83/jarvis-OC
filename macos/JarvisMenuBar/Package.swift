// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JarvisMenuBar",
    platforms: [
        .macOS("15.0")
    ],
    products: [
        .executable(name: "JARVIS", targets: ["JARVIS"]),
        .executable(name: "JarvisTTSHelper", targets: ["JarvisTTSHelper"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "JARVIS",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/Jarvis"
        ),
        .executableTarget(
            name: "JarvisTTSHelper",
            dependencies: [
                .product(name: "TTSKit", package: "argmax-oss-swift")
            ],
            path: "Sources/JarvisTTSHelper"
        )
    ]
)
