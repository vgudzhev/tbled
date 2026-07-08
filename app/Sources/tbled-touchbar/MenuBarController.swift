import AppKit
import TbledCore

/// The menu-bar mirror: a coloured dot per session in an NSStatusItem, with a
/// drop-down listing each session. This is the always-works fallback — it needs
/// no private API and is useful on Macs without a Touch Bar.
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private var sessions: [RenderedSession] = []

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.font = .systemFont(ofSize: 13)
        rebuild()
    }

    func update(_ sessions: [RenderedSession]) {
        self.sessions = sessions
        rebuild()
    }

    private func rebuild() {
        // Title: one coloured dot per session (max 8), or a dim dot when idle.
        let title = NSMutableAttributedString()
        if sessions.isEmpty {
            title.append(NSAttributedString(string: "○", attributes: [
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        } else {
            for (i, r) in sessions.prefix(8).enumerated() {
                if i > 0 { title.append(NSAttributedString(string: " ")) }
                title.append(NSAttributedString(string: Theme.glyph(for: r.display), attributes: [
                    .foregroundColor: Theme.color(for: r.display),
                ]))
            }
        }
        statusItem.button?.attributedTitle = title

        let menu = NSMenu()
        if sessions.isEmpty {
            let item = NSMenuItem(title: "No active Claude sessions", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for r in sessions {
                let title = "\(Theme.glyph(for: r.display))  \(r.label)  —  \(r.display.rawValue)"
                let item = NSMenuItem(title: title, action: #selector(focusSession(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = r.session
                item.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: Theme.color(for: r.display),
                ])
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit tbled", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func focusSession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? Session else { return }
        FocusService.focus(session: session)
    }
}
