import Foundation

/// State a session reports, as written by the `tbled-hook` shell hook.
public enum SessionState: String, Codable {
    case working   // 🔴 mid-turn (prompt submitted, tools running)
    case waiting   // 🟡 blocked on the user (permission prompt / question)
    case ready     // 🟢 turn finished, idle
}

/// The state actually rendered, after applying stale/liveness rules.
public enum DisplayState: String {
    case working
    case waiting
    case ready
    case stale     // ⚪ no activity for a while, probably abandoned
}

public struct TermInfo: Codable, Equatable {
    public var app: String
    public var itermSessionId: String
    public var termSessionId: String

    enum CodingKeys: String, CodingKey {
        case app
        case itermSessionId = "iterm_session_id"
        case termSessionId = "term_session_id"
    }

    // Tolerate missing sub-fields (older/partial records).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = (try? c.decode(String.self, forKey: .app)) ?? ""
        itermSessionId = (try? c.decode(String.self, forKey: .itermSessionId)) ?? ""
        termSessionId = (try? c.decode(String.self, forKey: .termSessionId)) ?? ""
    }
}

/// One `~/.tbled/sessions/<id>.json` record.
public struct Session: Codable, Equatable {
    public let sessionId: String
    public let name: String
    public let cwd: String
    public let pid: Int
    public let state: SessionState
    public let createdAt: Date
    public let updatedAt: Date
    public let term: TermInfo?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case name, cwd, pid, state, term
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Decoder configured for the hook's `2026-07-08T14:22:31Z` timestamps.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func decode(from data: Data) throws -> Session {
        try decoder().decode(Session.self, from: data)
    }
}

/// Time-since-update thresholds, in seconds.
public struct StaleThresholds {
    public var stale: TimeInterval
    public var hide: TimeInterval
    public init(stale: TimeInterval = 1200, hide: TimeInterval = 7200) {
        self.stale = stale
        self.hide = hide
    }
}

/// A session resolved to a display state and a disambiguated label.
public struct RenderedSession: Equatable {
    public let session: Session
    public let label: String
    public let display: DisplayState
}

/// True if `pid` names a live process. We proved (see README verification) that
/// the hook records the durable Claude Code process PID, so this is reliable —
/// not merely advisory. `kill(pid, 0)` returns 0 when alive, and EPERM means
/// the process exists but is owned by someone else (also "alive").
public func pidIsAlive(_ pid: Int) -> Bool {
    if pid <= 0 { return false }
    let result = kill(pid_t(pid), 0)
    if result == 0 { return true }
    return errno == EPERM
}

/// Resolve a batch of sessions into the tiles to display:
///   1. drop dead (PID gone) and expired (older than `hide`) sessions,
///   2. sort by `createdAt` (then id) so tiles never jump around,
///   3. mark anything older than `stale` as `.stale`,
///   4. disambiguate duplicate names as `name`, `name·2`, `name·3`, …
public func render(
    sessions: [Session],
    now: Date,
    thresholds: StaleThresholds = StaleThresholds(),
    isAlive: (Int) -> Bool = pidIsAlive
) -> [RenderedSession] {
    // 1. filter + resolve display state
    let live: [(Session, DisplayState)] = sessions.compactMap { s in
        guard isAlive(s.pid) else { return nil }
        let age = now.timeIntervalSince(s.updatedAt)
        if age > thresholds.hide { return nil }
        let display: DisplayState
        if age > thresholds.stale {
            display = .stale
        } else {
            switch s.state {
            case .working: display = .working
            case .waiting: display = .waiting
            case .ready:   display = .ready
            }
        }
        return (s, display)
    }

    // 2. deterministic order
    let sorted = live.sorted { a, b in
        if a.0.createdAt != b.0.createdAt { return a.0.createdAt < b.0.createdAt }
        return a.0.sessionId < b.0.sessionId
    }

    // 3. disambiguate duplicate names
    var counts: [String: Int] = [:]
    for (s, _) in sorted { counts[s.name, default: 0] += 1 }
    var seen: [String: Int] = [:]

    return sorted.map { (s, display) in
        let label: String
        if (counts[s.name] ?? 0) > 1 {
            seen[s.name, default: 0] += 1
            label = "\(s.name)·\(seen[s.name]!)"
        } else {
            label = s.name
        }
        return RenderedSession(session: s, label: label, display: display)
    }
}

/// Truncate a tile label to `maxLength` glyphs with an ellipsis.
public func truncate(_ name: String, maxLength: Int = 10) -> String {
    guard name.count > maxLength, maxLength > 1 else { return name }
    return String(name.prefix(maxLength - 1)) + "…"
}
