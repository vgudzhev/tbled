import Foundation
import GlowbarCore

// A dependency-free mirror of GlowbarCoreTests, runnable under Command Line Tools
// (which lack XCTest). Exercises the same parsing / stale / dedup / PID logic
// through GlowbarCore's public API. Exits non-zero on the first failure.

var failures = 0
func check(_ label: String, _ cond: Bool) {
    if cond { print("  ok   \(label)") }
    else { print("  FAIL \(label)"); failures += 1 }
}

func makeJSON(id: String, name: String, state: String,
              created: String, updated: String, pid: Int, term: Bool = true) -> Data {
    let termPart = term
        ? #","term":{"app":"iTerm.app","iterm_session_id":"w0","term_session_id":"y"}"#
        : ""
    return """
    {"session_id":"\(id)","name":"\(name)","cwd":"/x/\(name)","pid":\(pid),\
    "state":"\(state)","created_at":"\(created)","updated_at":"\(updated)"\(termPart)}
    """.data(using: .utf8)!
}

func session(id: String, name: String, state: SessionState,
             created: TimeInterval, ageSecs: TimeInterval, now: Date, pid: Int = 999) -> Session {
    Session(sessionId: id, name: name, cwd: "/x", pid: pid, state: state,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: now.addingTimeInterval(-ageSecs), term: nil)
}

// 1. decode matches hook output
do {
    let s = try Session.decode(from: makeJSON(id: "a1", name: "webapp", state: "working",
        created: "2026-07-08T13:00:00Z", updated: "2026-07-08T13:05:00Z", pid: 123))
    check("decode: fields", s.sessionId == "a1" && s.name == "webapp"
        && s.state == .working && s.pid == 123 && s.term?.app == "iTerm.app")
} catch { check("decode: fields (threw \(error))", false) }

// 2. decode tolerates missing term
do {
    let s = try Session.decode(from: makeJSON(id: "a1", name: "x", state: "ready",
        created: "2026-07-08T13:00:00Z", updated: "2026-07-08T13:00:00Z", pid: 1, term: false))
    check("decode: missing term ok", s.term == nil && s.state == .ready)
} catch { check("decode: missing term (threw \(error))", false) }

let now = Date(timeIntervalSince1970: 1_000_000)

// 3. render maps states and orders by createdAt
do {
    let out = render(sessions: [
        session(id: "c", name: "infra",  state: .ready,   created: 30, ageSecs: 1, now: now),
        session(id: "a", name: "my-api", state: .working, created: 10, ageSecs: 1, now: now),
        session(id: "b", name: "webapp", state: .waiting, created: 20, ageSecs: 1, now: now),
    ], now: now, isAlive: { _ in true })
    check("render: order by created", out.map { $0.label } == ["my-api", "webapp", "infra"])
    check("render: state mapping", out.map { $0.display } == [.working, .waiting, .ready])
}

// 4. render marks stale, drops expired + dead
do {
    let out = render(sessions: [
        session(id: "live",    name: "a", state: .ready,   created: 1, ageSecs: 10,   now: now),
        session(id: "stale",   name: "b", state: .ready,   created: 2, ageSecs: 1300, now: now),
        session(id: "expired", name: "c", state: .ready,   created: 3, ageSecs: 8000, now: now),
        session(id: "dead",    name: "d", state: .working, created: 4, ageSecs: 1, now: now, pid: 1),
    ], now: now, isAlive: { $0 != 1 })
    check("render: drops expired+dead", out.map { $0.session.sessionId } == ["live", "stale"])
    check("render: stale marked", out.map { $0.display } == [.ready, .stale])
}

// 5. duplicate names disambiguated
do {
    let out = render(sessions: [
        session(id: "x", name: "webapp", state: .ready,   created: 10, ageSecs: 1, now: now),
        session(id: "y", name: "webapp", state: .working, created: 20, ageSecs: 1, now: now),
        session(id: "z", name: "solo",   state: .ready,   created: 30, ageSecs: 1, now: now),
    ], now: now, isAlive: { _ in true })
    check("render: dedup ·N", out.map { $0.label } == ["webapp·1", "webapp·2", "solo"])
}

// 6. truncate
check("truncate: short kept", truncate("short") == "short")
check("truncate: ellipsis", truncate("infrastructure", maxLength: 10) == "infrastru…")

// 7. pidIsAlive
check("pid: self alive", pidIsAlive(Int(ProcessInfo.processInfo.processIdentifier)))
check("pid: 0 dead", !pidIsAlive(0))
check("pid: negative dead", !pidIsAlive(-5))

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
