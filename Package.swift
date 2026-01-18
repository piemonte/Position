// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Position",
    platforms: [
      .iOS(.v16),
      .macOS(.v13)
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
    swiftLanguageModes: [.v5, .v6]
)
