import AppKit
import TbledCore

/// A single rounded Touch Bar tile: a state-coloured rectangle with the session
/// name. Tapping it asks the FocusService to bring the owning terminal forward.
final class SessionTileView: NSButton {

    private(set) var rendered: RenderedSession

    init(rendered: RenderedSession) {
        self.rendered = rendered
        super.init(frame: .zero)
        self.isBordered = false
        self.bezelStyle = .rounded
        self.title = ""
        self.wantsLayer = true
        self.layer?.cornerRadius = 6
        self.target = self
        self.action = #selector(tapped)
        apply(rendered)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func apply(_ r: RenderedSession) {
        self.rendered = r
        let color = Theme.color(for: r.display)
        layer?.backgroundColor = color.cgColor
        let text = truncate(r.label, maxLength: 12)
        let attr = NSAttributedString(string: text, attributes: [
            .foregroundColor: Theme.textColor(for: r.display),
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
        ])
        self.attributedTitle = attr
    }

    @objc private func tapped() {
        FocusService.focus(session: rendered.session)
    }

    override var intrinsicContentSize: NSSize {
        var s = super.intrinsicContentSize
        s.width = max(s.width + 24, 72)
        return s
    }
}
