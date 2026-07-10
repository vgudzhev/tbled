import AppKit
import GlowbarCore

/// Maps a display state to its tile colour and menu-bar glyph.
enum Theme {
    static func color(for state: DisplayState) -> NSColor {
        switch state {
        case .working: return NSColor.systemRed
        case .waiting: return NSColor.systemYellow
        case .ready:   return NSColor.systemGreen
        case .stale:   return NSColor.systemGray
        }
    }

    /// Filled dot for active states, hollow for stale — used in the menu bar.
    static func glyph(for state: DisplayState) -> String {
        state == .stale ? "○" : "●"
    }

    static func textColor(for state: DisplayState) -> NSColor {
        state == .waiting ? .black : .white
    }
}
