import AppKit
import TbledCore
import CDFR

/// Owns the tbled Touch Bar presence. Two modes (env `TBLED_TOUCHBAR_MODE`):
///
///  * `app`  (default) — take over the **app region** (the left/main part of the
///    Touch Bar), persistently, *instead of* each focused app's own Touch Bar
///    (Terminal's colours, VS Code's debug buttons, …). This is the Pock
///    mechanism: present a system-modal Touch Bar and re-claim it whenever
///    another app activates and tries to install its own bar.
///  * `strip` — just a compact dot cluster in the **Control Strip** (right side,
///    by brightness); tap to expand the full named strip.
///
/// All private-API calls route through the CDFR shim, which no-ops if the entry
/// points are unavailable — so on a Mac without a Touch Bar (or a macOS where
/// these are gone) this class does nothing and the menu-bar mirror stays
/// authoritative.
final class TouchBarController: NSObject, NSTouchBarDelegate {

    enum Mode { case appRegion, controlStrip }

    static let trayIdentifier = NSTouchBarItem.Identifier("com.tbled.controlStrip")
    static let stripIdentifier = NSTouchBarItem.Identifier("com.tbled.strip")

    private var sessions: [RenderedSession] = []
    private var summaryView: NSStackView?      // control-strip dot cluster
    private var stripView: NSStackView?        // app-region named tiles
    private lazy var trayItem = makeTrayItem()
    private lazy var modalBar: NSTouchBar = makeModalBar()

    let mode: Mode
    /// Whether the Touch Bar path is even usable on this machine.
    let available: Bool = TBLEDDFRAvailable()

    override init() {
        switch ProcessInfo.processInfo.environment["TBLED_TOUCHBAR_MODE"] {
        case "strip": mode = .controlStrip
        default:      mode = .appRegion
        }
        super.init()
    }

    func install() {
        guard available else { return }
        TBLEDAddSystemTrayItem(trayItem)
        switch mode {
        case .controlStrip:
            // A persistent dot cluster on the right; tap expands the full strip.
            TBLEDSetControlStripPresence(Self.trayIdentifier.rawValue, true)
        case .appRegion:
            // Occupy the app region persistently. Keep the tray registration as
            // the anchor but don't light up the strip dot; no close box.
            TBLEDSetControlStripPresence(Self.trayIdentifier.rawValue, false)
            TBLEDShowCloseBox(false)
            presentAppRegion()
            // Re-claim the app region whenever another app takes focus (and thus
            // installs its own Touch Bar), or after wake — same as Pock.
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(presentAppRegion),
                name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }
    }

    /// Re-assert presence — the DFR handle goes stale across sleep and
    /// TouchBarServer restarts (same failure mode cled handles for OpenRGB).
    func reassert() {
        guard available else { return }
        switch mode {
        case .controlStrip: TBLEDSetControlStripPresence(Self.trayIdentifier.rawValue, true)
        case .appRegion:    presentAppRegion()
        }
    }

    func update(_ sessions: [RenderedSession]) {
        self.sessions = sessions
        rebuildSummary()
        rebuildStrip()
    }

    // MARK: - Control-strip dot cluster

    private func makeTrayItem() -> NSCustomTouchBarItem {
        let item = NSCustomTouchBarItem(identifier: Self.trayIdentifier)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        summaryView = stack
        let gesture = NSClickGestureRecognizer(target: self, action: #selector(present))
        stack.addGestureRecognizer(gesture)
        item.view = stack
        return item
    }

    private func rebuildSummary() {
        guard let stack = summaryView else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if sessions.isEmpty {
            stack.addArrangedSubview(dotView(color: .systemGray))
        } else {
            for r in sessions.prefix(6) {
                stack.addArrangedSubview(dotView(color: Theme.color(for: r.display)))
            }
        }
    }

    private func dotView(color: NSColor) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 5
        v.layer?.backgroundColor = color.cgColor
        v.widthAnchor.constraint(equalToConstant: 10).isActive = true
        v.heightAnchor.constraint(equalToConstant: 10).isActive = true
        return v
    }

    // MARK: - App-region named strip (persistent modal bar)

    private func makeModalBar() -> NSTouchBar {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.defaultItemIdentifiers = [Self.stripIdentifier]
        return bar
    }

    /// Present (or re-present) the modal bar in the app region. Cheap to call
    /// repeatedly — the system replaces the current presentation.
    @objc private func presentAppRegion() {
        guard available, mode == .appRegion else { return }
        TBLEDPresentSystemModal(modalBar, Self.trayIdentifier.rawValue)
    }

    /// Control-strip mode: tap the dot cluster to expand the full strip.
    @objc private func present() {
        guard available, mode == .controlStrip else { return }
        TBLEDShowCloseBox(true)
        TBLEDPresentSystemModal(modalBar, Self.trayIdentifier.rawValue)
    }

    /// Update the live strip view in place, so we don't have to re-present on
    /// every session change (which would flicker).
    private func rebuildStrip() {
        guard let stack = stripView else { return }
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if sessions.isEmpty {
            let label = NSTextField(labelWithString: "no active Claude sessions")
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(label)
        } else {
            for r in sessions { stack.addArrangedSubview(SessionTileView(rendered: r)) }
        }
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == Self.stripIdentifier else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        // Reuse one long-lived stack view so updates apply to the presented bar.
        let stack = stripView ?? {
            let s = NSStackView()
            s.orientation = .horizontal
            s.spacing = 8
            stripView = s
            return s
        }()
        rebuildStrip()
        item.view = stack
        return item
    }
}
