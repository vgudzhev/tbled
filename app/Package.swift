// swift-tools-version:5.7
import PackageDescription

// tbled — native Touch Bar status app for Claude Code sessions.
//
// Three targets:
//   CDFR            — ObjC shim isolating the private DFRFoundation / NSTouchBar
//                     control-strip API (dlopen'd, guarded by respondsToSelector).
//   TbledCore       — pure-Foundation model + parsing + stale/PID/dedup logic.
//                     No AppKit, so it is unit-testable headlessly.
//   tbled-touchbar  — the AppKit executable (menu-bar item + Touch Bar tiles).
//
// Requires a working Swift toolchain (full Xcode, or a repaired Command Line
// Tools install).
//   Build:      swift build -c release
//   Test:       swift test              (needs full Xcode — XCTest)
//   Self-test:  swift run tbled-selftest (runs the same checks under CLT-only)
let package = Package(
    name: "tbled",
    platforms: [.macOS(.v11)],
    targets: [
        .target(name: "CDFR"),
        .target(name: "TbledCore"),
        .executableTarget(
            name: "tbled-touchbar",
            dependencies: ["CDFR", "TbledCore"]
        ),
        // XCTest-free runner so the logic can be verified without Xcode.
        .executableTarget(
            name: "tbled-selftest",
            dependencies: ["TbledCore"]
        ),
        .testTarget(
            name: "TbledCoreTests",
            dependencies: ["TbledCore"]
        ),
    ]
)
