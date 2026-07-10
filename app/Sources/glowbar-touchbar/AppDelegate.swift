import AppKit
import ApplicationServices
import GlowbarCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let store = SessionStore()
    private let menuBar = MenuBarController()
    private let touchBar = TouchBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        touchBar.install()

        store.onChange = { [weak self] rendered in
            self?.menuBar.update(rendered)
            self?.touchBar.update(rendered)
            if ProcessInfo.processInfo.environment["GLOWBAR_DIAG"] != nil {
                FileHandle.standardError.write(
                    "diag: rendered \(rendered.count) session(s): "
                    .appending(rendered.map { "\($0.label)=\($0.display.rawValue)" }.joined(separator: ", "))
                    .appending("\n").data(using: .utf8)!)
            }
        }
        store.start()

        if ProcessInfo.processInfo.environment["GLOWBAR_DIAG"] != nil {
            let msg = "diag: launched. menuBarButton=\(menuBar.hasStatusButton) "
                + "touchBarDFR=\(touchBar.available) "
                + "accessibilityTrusted=\(AXIsProcessTrusted()) "
                + "bundleID=\(Bundle.main.bundleIdentifier ?? "none")\n"
            FileHandle.standardError.write(msg.data(using: .utf8)!)
        }

        // Re-assert control-strip presence after wake / display changes — the
        // DFR handle goes stale otherwise (cled hits the same issue for OpenRGB).
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(reassert),
                         name: NSWorkspace.didWakeNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(reassert),
                         name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(reassert),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func reassert() {
        touchBar.reassert()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.stop()
    }
}
