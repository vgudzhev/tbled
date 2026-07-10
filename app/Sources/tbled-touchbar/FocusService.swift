import AppKit
import TbledCore

/// Tap-to-focus: bring the terminal running a session to the front, selecting
/// the exact window/tab — so each tile behaves like a link back to its session.
///
///  * Terminal.app — match the tab by its TTY (derived from the session PID).
///  * iTerm2       — match the session by the recorded ITERM_SESSION_ID UUID,
///                   falling back to TTY.
///  * VS Code / other — activate the app (best effort).
///
/// The AppleScript that drives Terminal/iTerm needs Automation permission;
/// macOS prompts the first time the user taps a tile.
enum FocusService {

    static func focus(session: Session) {
        // ps + AppleScript are blocking; keep them off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let app = session.term?.app ?? ""
            switch app {
            case "iTerm.app":
                focusITerm(session)
            case "Apple_Terminal":
                if let tty = tty(forPID: session.pid) {
                    focusTerminalTab(tty: tty)
                } else {
                    activate(bundleId: "com.apple.Terminal")
                }
            case "vscode":
                activate(bundleId: "com.microsoft.VSCode")
            default:
                // Synced sessions (from `tbled sync`) carry no terminal app.
                // Best effort: if it's a Terminal.app tab, focus it by TTY;
                // otherwise do nothing (don't raise the wrong app).
                if let tty = tty(forPID: session.pid) {
                    focusTerminalTab(tty: tty, activateOnMiss: false)
                }
            }
        }
    }

    // MARK: - Terminal.app (match by tty)

    private static func focusTerminalTab(tty: String, activateOnMiss: Bool = true) {
        let onMiss = activateOnMiss ? "activate" : ""
        let script = """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
                activate
                return
              end if
            end repeat
          end repeat
          \(onMiss)
        end tell
        """
        runAppleScript(script)
    }

    // MARK: - iTerm2 (match by session UUID, tty fallback)

    private static func focusITerm(_ session: Session) {
        let raw = session.term?.itermSessionId ?? ""
        let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
        if !uuid.isEmpty {
            let script = """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if id of s is "\(uuid)" then
                      select w
                      tell t to select
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
              activate
            end tell
            """
            runAppleScript(script)
        } else {
            activate(bundleId: "com.googlecode.iterm2")
        }
    }

    // MARK: - Helpers

    /// The controlling TTY of a process, as a `/dev/ttysNNN` path.
    private static func tty(forPID pid: Int) -> String? {
        guard pid > 0 else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !out.isEmpty, out != "??", out != "?" else { return nil }
        return out.hasPrefix("/dev/") ? out : "/dev/\(out)"
    }

    private static func activate(bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error, ProcessInfo.processInfo.environment["TBLED_DIAG"] != nil {
            FileHandle.standardError.write("focus AppleScript error: \(error)\n".data(using: .utf8)!)
        }
    }
}
