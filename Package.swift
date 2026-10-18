// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Tangerine", platforms: [.macOS(.v13)], products: [.executable(name: "Tangerine", targets: ["Tangerine"])], targets: [.executableTarget(name: "Tangerine")])
