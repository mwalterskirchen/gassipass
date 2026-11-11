// swift-tools-version: 6.2
import PackageDescription

/// The settings of the app target: Swift 6, the main actor by default, and
/// the "approachable concurrency" features of Xcode.
let settings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "GassiPassCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GassiPassCore", targets: ["GassiPassCore"]),
        .library(name: "GassiPassWalkActivity", targets: ["GassiPassWalkActivity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.55.0"),
    ],
    targets: [
        // Everything of the app that is not a screen: the store, the
        // collections, the goals, the walk and the server.
        .target(
            name: "GassiPassCore",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            resources: [.process("Store/CoreDataImport/gassipass.xcdatamodeld")],
            swiftSettings: settings),
        // The data of the Live Activity, which the widget extension also uses.
        .target(name: "GassiPassWalkActivity", swiftSettings: settings),
        .testTarget(
            name: "GassiPassCoreTests",
            dependencies: ["GassiPassCore", "GassiPassWalkActivity"],
            resources: [.copy("Resources/fixture.sqlite")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]),
    ]
)
