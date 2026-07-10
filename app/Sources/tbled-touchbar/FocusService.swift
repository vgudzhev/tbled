import AppKit
import ApplicationServices
import TbledCore

/// Tap-to-focus: bring the terminal running a session to the front, selecting
/// the exact window/tab — so each tile behaves like a link back to its session.
///
///  * Terminal.app — match the tab by its TTY (derived from the session PID).
///  * iTerm2       — match the session by the recorded ITERM_SESSION_ID UUID.
///  * VS Code / other — activate the app (best effort).
///
/// Two macOS permissions are involved:
///  * **Automation** — the AppleScript that finds/selects the tab (prompted on
///    first tap).
///  * **Accessibility** — needed to `AXRaise` the window. Plain activation and
///    AppleScript cannot pull a window out of another Space or a *fullscreen*
///    Space (nor switch between two fullscreen windows of the same app); only
///    the Accessibility API can. Grant it under System Settings → Privacy &
///    Security → Accessibility (add `~/.tbled/bin/tbled-touchbar`). Without it,
///    focus still works within the current Space but can't cross fullscreen.
enum FocusService {

    private static var promptedAX = false

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
                    raiseMainWindowAndActivate(bundleId: "com.apple.Terminal")
                }
            case "vscode":
                raiseMainWindowAndActivate(bundleId: "com.microsoft.VSCode")
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
        // Select the tab and make its window Terminal's ordered-front window,
        // then report whether we matched ("1") so we only raise on a hit.
        let script = """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
                return "1"
              end if
            end repeat
          end repeat
          return "0"
        end tell
        """
        if runAppleScript(script) == "1" {
            raiseMainWindowAndActivate(bundleId: "com.apple.Terminal")
        } else if activateOnMiss {
            raiseMainWindowAndActivate(bundleId: "com.apple.Terminal")
        }
    }

    // MARK: - iTerm2 (match by session UUID)

    private static func focusITerm(_ session: Session) {
        let raw = session.term?.itermSessionId ?? ""
        let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
        guard !uuid.isEmpty else {
            raiseMainWindowAndActivate(bundleId: "com.googlecode.iterm2"); return
        }
        let script = """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if id of s is "\(uuid)" then
                  select w
                  tell t to select
                  return "1"
                end if
              end repeat
            end repeat
          end repeat
          return "0"
        end tell
        """
        _ = runAppleScript(script)
        raiseMainWindowAndActivate(bundleId: "com.googlecode.iterm2")
    }

    // MARK: - Accessibility raise (crosses Spaces / fullscreen)

    /// Raise the app's main (front) window via the Accessibility API and
    /// activate it. AXRaise is the only reliable way to switch to a window in
    /// another Space or a fullscreen Space — including another window of the
    /// same app, which app activation alone can't do. Falls back to plain
    /// activation (prompting for Accessibility once) when not yet trusted.
    private static func raiseMainWindowAndActivate(bundleId: String) {
        guard let app = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleId).first else { return }

        if AXIsProcessTrusted() {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var win: CFTypeRef?
            var err = AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &win)
            if err != .success || win == nil {
                err = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &win)
            }
            if err == .success, let w = win {
                AXUIElementPerformAction(w as! AXUIElement, kAXRaiseAction as CFString)
            }
        } else if !promptedAX {
            // Ask once; until granted, we can still activate within the Space.
            promptedAX = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }

        DispatchQueue.main.async {
            app.activate(options: [.activateAllWindows])
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

    @discardableResult
    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error, ProcessInfo.processInfo.environment["TBLED_DIAG"] != nil {
            FileHandle.standardError.write("focus AppleScript error: \(error)\n".data(using: .utf8)!)
        }
        return result?.stringValue
    }
}
