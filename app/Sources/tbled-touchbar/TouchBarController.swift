import AppKit
import TbledCore
import CDFR

/// Owns the persistent control-strip item and the expanded session strip.
///
/// Following the Pock/MTMR recipe: a single `NSCustomTouchBarItem` is registered
/// as a system-tray item and made persistently present in the Control Strip.
/// Its view is a compact summary of coloured dots; tapping it presents a
/// system-modal Touch Bar containing one `SessionTileView` per session.
///
/// All private-API calls route through the CDFR shim, which no-ops if the
/// entry points are unavailable — so on a Mac without a Touch Bar (or a macOS
/// where these are gone) this class simply does nothing and the menu-bar
/// mirror remains authoritative.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    static let trayIdentifier = NSTouchBarItem.Identifier("com.tbled.controlStrip")
    static let stripIdentifier = NSTouchBarItem.Identifier("com.tbled.strip")

    private var sessions: [RenderedSession] = []
    private var summaryView: NSStackView?
    private lazy var trayItem = makeTrayItem()

    /// Whether the Touch Bar path is even usable on this machine.
    let available: Bool = TBLEDDFRAvailable()

    func install() {
        guard available else { return }
        TBLEDAddSystemTrayItem(trayItem)
        TBLEDSetControlStripPresence(Self.trayIdentifier.rawValue, true)
    }

    /// Re-assert control-strip presence — the DFR handle goes stale across sleep
    /// and TouchBarServer restarts (same failure mode cled handles for OpenRGB).
    func reassert() {
        guard available else { return }
        TBLEDSetControlStripPresence(Self.trayIdentifier.rawValue, true)
    }

    func update(_ sessions: [RenderedSession]) {
        self.sessions = sessions
        rebuildSummary()
    }

    // MARK: control-strip summary (always visible)

    private func makeTrayItem() -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        summaryView = stack

        let button = NSButton(title: "", target: self, action: #selector(present))
        button.isBordered = false
        button.imagePosition = .imageOnly
        // Wrap the stack in a clickable button-like container.
        let container = NSStackView(views: [stack])
        container.orientation = .horizontal
        let gesture = NSClickGestureRecognizer(target: self, action: #selector(present))
        container.addGestureRecognizer(gesture)
        item.view = container
        return item
    }

    private func rebuildSummary() {
        guard let stack = summaryView else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if sessions.isEmpty {
            let dot = dotView(color: .systemGray)
            stack.addArrangedSubview(dot)
            return
        }
        for r in sessions.prefix(6) {
            stack.addArrangedSubview(dotView(color: Theme.color(for: r.display)))
        }
    }

    private func dotView(color: NSColor) -> NSView {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.layer?.backgroundColor = color.cgColor
        v.widthAnchor.constraint(equalToConstant: 10).isActive = true
        v.heightAnchor.constraint(equalToConstant: 10).isActive = true
        return v
    }

    // MARK: expanded modal strip (on tap)

    @objc private func present() {
        guard available else { return }
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.stripIdentifier]
        TBLEDShowCloseBox(true)
        TBLEDPresentSystemModal(bar, Self.trayIdentifier.rawValue)
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.stripIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        if sessions.isEmpty {
            let label = NSTextField(labelWithString: "no active Claude sessions")
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        } else {
            for r in sessions {
                stack.addArrangedSubview(SessionTileView(rendered: r))
            }
        }
        item.view = stack
        return item
    }
}
