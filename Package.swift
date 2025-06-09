// swift-tools-version: 5.8

import PackageDescription

let package = Package(
  name: "vz-nixos",
  platforms: [
    .macOS(.v13)
  ],
  targets: [
    .executableTarget(
      name: "vz-nixos",
      linkerSettings: [.linkedFramework("Virtualization")]
    )
  ]
)
