import AppKit

// Entry point. A plain SwiftPM executable (no .xib / Info.plist bundle), so we
// build the NSApplication by hand and run as an accessory (menu-bar) agent.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
