// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NozokiCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NozokiCore", targets: ["NozokiCore"])
    ],
    dependencies: [
        // 取り出し処理に使う。版は固定（勝手に上げない）
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "NozokiCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .testTarget(
            name: "NozokiCoreTests",
            dependencies: ["NozokiCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        )
    ]
)
