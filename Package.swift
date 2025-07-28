// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Position",
    platforms: [
      .iOS(.v15),
      .macOS(.v11)
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
