// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Pagecase",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "PagecaseCore", targets: ["PagecaseCore"]),
    .executable(name: "PagecaseApp", targets: ["PagecaseApp"]),
    .executable(name: "PagecaseBridge", targets: ["PagecaseBridge"]),
    .executable(name: "PagecaseCoreChecks", targets: ["PagecaseCoreChecks"])
  ],
  targets: [
    .target(name: "PagecaseCore"),
    .executableTarget(
      name: "PagecaseApp",
      dependencies: ["PagecaseCore"]
    ),
    .executableTarget(
      name: "PagecaseBridge",
      dependencies: ["PagecaseCore"]
    ),
    .executableTarget(
      name: "PagecaseCoreChecks",
      dependencies: ["PagecaseCore"]
    ),
    .testTarget(
      name: "PagecaseCoreTests",
      dependencies: ["PagecaseCore"],
      swiftSettings: [
        .unsafeFlags([
          "-F",
          "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
        ])
      ],
      linkerSettings: [
        .unsafeFlags([
          "-F",
          "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
          "-Xlinker",
          "-rpath",
          "-Xlinker",
          "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
          "-Xlinker",
          "-rpath",
          "-Xlinker",
          "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
        ])
      ]
    )
  ]
)
