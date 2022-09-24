// swift-tools-version:5.0
import PackageDescription

let package = Package(
    name: "Position",
    platforms: [
      .iOS(.v14)
    ],
    products: [
      .library(name: "Position", targets: ["Position"])
    ],
    targets: [
      .target(
          name: "Position",
          path: "Sources"
      )
    ],
    swiftLanguageVersions: [.v5]
)
