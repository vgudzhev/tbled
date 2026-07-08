import AppKit
import TbledCore

/// Phase 4: tap-to-focus. Best-effort activation of the terminal running a
/// session, using the terminal metadata captured by the hook at SessionStart.
///
///  * iTerm2  — match on the recorded ITERM_SESSION_ID via AppleScript.
///  * Terminal.app / VS Code / unknown — activate the app by bundle id.
enum FocusService {

    static func focus(session: Session) {
        let app = session.term?.app ?? ""
        switch app {
        case "iTerm.app":
            focusITerm(session)
        case "Apple_Terminal":
            activate(bundleId: "com.apple.Terminal")
        case "vscode":
            activate(bundleId: "com.microsoft.VSCode")
        default:
            // Unknown terminal: nothing reliable to do.
            break
        }
    }

    private static func focusITerm(_ session: Session) {
        // ITERM_SESSION_ID looks like "w0t2p0:UUID"; iTerm's AppleScript exposes
        // the trailing UUID as each session's `id`.
        let raw = session.term?.itermSessionId ?? ""
        let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
        guard !uuid.isEmpty else { activate(bundleId: "com.googlecode.iterm2"); return }
        let script = """
        tell application "iTerm2"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if id of s is "\(uuid)" then
                  select w
                  tell t to select
                  return
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
        runAppleScript(script)
    }

    private static func activate(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func runAppleScript(_ source: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
    }
}
