// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZipPeekCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ZipPeekCore", targets: ["ZipPeekCore"])
    ],
    dependencies: [
        // 取り出し処理に使う。版は固定（勝手に上げない）
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(
            name: "ZipPeekCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .testTarget(
            name: "ZipPeekCoreTests",
            dependencies: ["ZipPeekCore", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        )
    ]
)
