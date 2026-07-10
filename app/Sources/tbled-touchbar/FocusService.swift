import AppKit
import ApplicationServices
import TbledCore

/// Tap-to-focus: bring the app hosting a session to the front, crossing Spaces
/// / fullscreen, and — for Terminal & iTerm — selecting the exact tab.
///
/// The owning app is found by walking up the session's process tree until we
/// hit a regular GUI application. This works uniformly for Terminal, iTerm,
/// VS Code, IntelliJ, and any other terminal host — including synced sessions
/// that carry no `term.app` — where scripting the specific inner terminal isn't
/// possible, so we focus the app window (the best achievable) rather than
/// nothing.
///
/// Permissions: **Automation** for the Terminal/iTerm tab-selection AppleScript
/// (prompted on first use), and **Accessibility** for the `AXRaise` that pulls
/// a window out of another Space / fullscreen. Grant both to `tbled.app`.
enum FocusService {

    private static var promptedAX = false

    static func focus(session: Session) {
        // ps / AppleScript / AX are blocking; keep them off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let app = owningApp(forPID: session.pid) ?? fallbackApp(for: session)
            else { return }

            // For scriptable terminals, select the exact tab first so the right
            // window is fronted; then raise + activate handles Spaces/fullscreen.
            switch app.bundleIdentifier {
            case "com.apple.Terminal":
                if let tty = tty(forPID: session.pid) { selectTerminalTab(tty: tty) }
            case "com.googlecode.iterm2":
                selectITermSession(session)
            default:
                break   // VS Code / IntelliJ / etc — app-level focus only
            }

            raiseAndActivate(app)
        }
    }

    // MARK: - Find the owning GUI app via the process tree

    /// Walk parents from `pid` until we reach a regular (Dock-having) GUI app —
    /// Terminal, iTerm2, Code, IntelliJ, … — and return it.
    private static func owningApp(forPID pid: Int) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<16 {
            if current <= 1 { break }
            if let app = NSRunningApplication(processIdentifier: pid_t(current)),
               app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        return nil
    }

    /// Fallback when the process walk finds nothing: map the recorded term app.
    private static func fallbackApp(for session: Session) -> NSRunningApplication? {
        let bundle: String
        switch session.term?.app {
        case "iTerm.app":     bundle = "com.googlecode.iterm2"
        case "Apple_Terminal": bundle = "com.apple.Terminal"
        case "vscode":        bundle = "com.microsoft.VSCode"
        default:              return nil
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    }

    // MARK: - Raise across Spaces / fullscreen

    private static func raiseAndActivate(_ app: NSRunningApplication) {
        if AXIsProcessTrusted() {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            var win: CFTypeRef?
            var err = AXUIElementCopyAttributeValue(ax, kAXMainWindowAttribute as CFString, &win)
            if err != .success || win == nil {
                err = AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win)
            }
            if err == .success, let w = win {
                AXUIElementPerformAction(w as! AXUIElement, kAXRaiseAction as CFString)
            }
        } else if !promptedAX {
            promptedAX = true
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        DispatchQueue.main.async { app.activate(options: [.activateAllWindows]) }
    }

    // MARK: - Terminal / iTerm tab selection

    private static func selectTerminalTab(tty: String) {
        runAppleScript("""
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
                return
              end if
            end repeat
          end repeat
        end tell
        """)
    }

    private static func selectITermSession(_ session: Session) {
        let raw = session.term?.itermSessionId ?? ""
        let uuid = raw.split(separator: ":").last.map(String.init) ?? raw
        guard !uuid.isEmpty else { return }
        runAppleScript("""
        tell application "iTerm2"
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
        """)
    }

    // MARK: - Helpers

    private static func parentPID(of pid: Int) -> Int? {
        guard let out = runProcess("/bin/ps", ["-o", "ppid=", "-p", String(pid)]) else { return nil }
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The controlling TTY of a process, as a `/dev/ttysNNN` path.
    private static func tty(forPID pid: Int) -> String? {
        guard pid > 0, let out = runProcess("/bin/ps", ["-o", "tty=", "-p", String(pid)]) else { return nil }
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "??", t != "?" else { return nil }
        return t.hasPrefix("/dev/") ? t : "/dev/\(t)"
    }

    private static func runProcess(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private static func runAppleScript(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error, ProcessInfo.processInfo.environment["TBLED_DIAG"] != nil {
            FileHandle.standardError.write("focus AppleScript error: \(error)\n".data(using: .utf8)!)
        }
    }
}
