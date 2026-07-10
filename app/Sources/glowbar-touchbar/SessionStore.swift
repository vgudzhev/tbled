import Foundation
import GlowbarCore

/// Watches the `~/.glowbar/sessions` directory and publishes the rendered set of
/// sessions. Uses a kqueue directory source (fires when hooks `mv` a file in or
/// out) plus a 2-second timer that both serves as a fallback and re-evaluates
/// time-based stale transitions. Callbacks are debounced ~120 ms and delivered
/// on the main queue.
final class SessionStore {

    var onChange: (([RenderedSession]) -> Void)?

    private let sessionsDir: URL
    private let thresholds: StaleThresholds
    private var dirFD: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var debounce: DispatchWorkItem?
    private var last: [RenderedSession] = []
    private let queue = DispatchQueue(label: "glowbar.sessionstore")

    init(root: URL? = nil, thresholds: StaleThresholds = StaleThresholds()) {
        let base = root ?? URL(fileURLWithPath: NSString(string: "~/.glowbar").expandingTildeInPath)
        self.sessionsDir = base.appendingPathComponent("sessions")
        self.thresholds = thresholds
    }

    func start() {
        try? FileManager.default.createDirectory(at: sessionsDir,
                                                 withIntermediateDirectories: true)
        startDirectorySource()
        startTimer()
        reload()
    }

    func stop() {
        source?.cancel(); source = nil
        timer?.cancel(); timer = nil
    }

    // Re-arm the directory watch (needed after the directory is recreated).
    private func startDirectorySource() {
        source?.cancel()
        dirFD = open(sessionsDir.path, O_EVTONLY)
        guard dirFD >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirFD,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .link],
            queue: queue)
        src.setEventHandler { [weak self] in self?.scheduleReload() }
        src.setCancelHandler { [weak self] in
            if let fd = self?.dirFD, fd >= 0 { close(fd); self?.dirFD = -1 }
        }
        src.resume()
        source = src
    }

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2.0)
        t.setEventHandler { [weak self] in
            guard let self = self else { return }
            // If the directory vanished/was recreated, re-arm the source.
            if self.dirFD < 0 || !FileManager.default.fileExists(atPath: self.sessionsDir.path) {
                self.startDirectorySource()
            }
            // Pull in any sessions Claude knows about but hooks missed (e.g.
            // started before install). `glowbar sync` writes them into our dir.
            self.runSync()
            self.reload()
        }
        t.resume()
        timer = t
    }

    private func scheduleReload() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        debounce = work
        queue.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// Run `glowbar sync` (best effort) to import Claude's own live sessions.
    private func runSync() {
        let glowbar = (("~/.glowbar/bin/glowbar") as NSString).expandingTildeInPath
        guard FileManager.default.isExecutableFile(atPath: glowbar) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: glowbar)
        p.arguments = ["sync"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { /* best effort */ }
    }

    private func reload() {
        let sessions = loadSessions()
        let rendered = render(sessions: sessions, now: Date(), thresholds: thresholds)
        guard rendered != last else { return }
        last = rendered
        DispatchQueue.main.async { [weak self] in self?.onChange?(rendered) }
    }

    private func loadSessions() -> [Session] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir, includingPropertiesForKeys: nil) else { return [] }
        var result: [Session] = []
        for url in entries where url.pathExtension == "json" {
            if url.lastPathComponent.hasPrefix(".tmp.") { continue }
            // The hook writes atomically (mv), but retry once on a torn read.
            for attempt in 0..<2 {
                guard let data = try? Data(contentsOf: url) else { break }
                if let s = try? Session.decode(from: data) {
                    result.append(s); break
                }
                if attempt == 0 { usleep(20_000) }
            }
        }
        return result
    }
}
