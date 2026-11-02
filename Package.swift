// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClearStuffCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CleanupCore", targets: ["CleanupCore"])],
    targets: [
        .target(name: "CleanupCore", path: "Clear Stuff", exclude: [
            "Assets.xcassets", "Clear Stuff.entitlements", "ContentView.swift", "Clear_StuffApp.swift", "Views", "Models/CleanupModel.swift"
        ], sources: ["Models/CleanupItem.swift", "Services/CleanupScanner.swift", "Services/BrowserCacheCatalog.swift", "Services/DownloadCleanupCatalog.swift", "Services/TrashService.swift"]),
        .testTarget(name: "CleanupCoreTests", dependencies: ["CleanupCore"], path: "Tests")
    ]
)
