// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "avocr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "avocr",
            targets: ["avocr-cli"]
        ),
        .library(
            name: "AVOCRLib",
            targets: ["AVOCRLib"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "AVOCRLib",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/AVOCRLib"
        ),
        .executableTarget(
            name: "avocr-cli",
            dependencies: ["AVOCRLib"],
            path: "Sources/avocr-cli"
        ),
        .testTarget(
            name: "AVOCRTests",
            dependencies: ["AVOCRLib"],
            path: "Tests",
            exclude: [
                "README.md",
                "TEST_IMPROVEMENT_PLAN.md"
            ]
        )
    ]
)
