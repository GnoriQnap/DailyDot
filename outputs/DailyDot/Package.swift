// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "DailyDot", platforms: [.macOS(.v13)], products: [.executable(name: "DailyDot", targets: ["DailyDot"])], targets: [.executableTarget(name: "DailyDot"), .testTarget(name: "DailyDotTests", dependencies: ["DailyDot"])])
