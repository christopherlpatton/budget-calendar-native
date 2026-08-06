// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BudgetCalendarNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BudgetCalendarCore", targets: ["BudgetCalendarCore"]),
        .executable(name: "BudgetCalendarApp", targets: ["BudgetCalendarApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "BudgetCalendarCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(
            name: "BudgetCalendarApp",
            dependencies: ["BudgetCalendarCore"]
        ),
        .testTarget(
            name: "BudgetCalendarCoreTests",
            dependencies: ["BudgetCalendarCore", .product(name: "GRDB", package: "GRDB.swift")],
            resources: [.process("../../Fixtures")]
        )
    ]
)
