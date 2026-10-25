// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DeskNames", platforms: [.macOS(.v13)], products: [.executable(name: "DeskNames", targets: ["DeskNames"])], targets: [.executableTarget(name: "DeskNames")])
