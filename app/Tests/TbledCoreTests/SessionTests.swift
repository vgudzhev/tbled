import XCTest
@testable import TbledCore

final class SessionTests: XCTestCase {

    private func makeJSON(id: String, name: String, state: String,
                          created: String, updated: String, pid: Int) -> Data {
        """
        {"session_id":"\(id)","name":"\(name)","cwd":"/x/\(name)","pid":\(pid),
         "state":"\(state)","created_at":"\(created)","updated_at":"\(updated)",
         "term":{"app":"iTerm.app","iterm_session_id":"w0","term_session_id":"y"}}
        """.data(using: .utf8)!
    }

    func testDecodeMatchesHookOutput() throws {
        let data = makeJSON(id: "a1", name: "webapp", state: "working",
                            created: "2026-07-08T13:00:00Z",
                            updated: "2026-07-08T13:05:00Z", pid: 123)
        let s = try Session.decode(from: data)
        XCTAssertEqual(s.sessionId, "a1")
        XCTAssertEqual(s.name, "webapp")
        XCTAssertEqual(s.state, .working)
        XCTAssertEqual(s.pid, 123)
        XCTAssertEqual(s.term?.app, "iTerm.app")
    }

    func testDecodeToleratesMissingTerm() throws {
        let data = """
        {"session_id":"a1","name":"x","cwd":"/x","pid":1,"state":"ready",
         "created_at":"2026-07-08T13:00:00Z","updated_at":"2026-07-08T13:00:00Z"}
        """.data(using: .utf8)!
        let s = try Session.decode(from: data)
        XCTAssertNil(s.term)
        XCTAssertEqual(s.state, .ready)
    }

    private func session(id: String, name: String, state: SessionState,
                         created: TimeInterval, ageSecs: TimeInterval,
                         now: Date, pid: Int = 999) -> Session {
        Session(sessionId: id, name: name, cwd: "/x", pid: pid, state: state,
                createdAt: Date(timeIntervalSince1970: created),
                updatedAt: now.addingTimeInterval(-ageSecs), term: nil)
    }

    func testRenderMapsStatesAndOrdersByCreated() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            session(id: "c", name: "infra",  state: .ready,   created: 30, ageSecs: 1, now: now),
            session(id: "a", name: "my-api", state: .working, created: 10, ageSecs: 1, now: now),
            session(id: "b", name: "webapp", state: .waiting, created: 20, ageSecs: 1, now: now),
        ]
        let out = render(sessions: sessions, now: now, isAlive: { _ in true })
        XCTAssertEqual(out.map { $0.label }, ["my-api", "webapp", "infra"])
        XCTAssertEqual(out.map { $0.display }, [.working, .waiting, .ready])
    }

    func testRenderMarksStaleAndDropsExpiredAndDead() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            session(id: "live",    name: "a", state: .ready, created: 1, ageSecs: 10,    now: now),
            session(id: "stale",   name: "b", state: .ready, created: 2, ageSecs: 1300,  now: now), // >20m
            session(id: "expired", name: "c", state: .ready, created: 3, ageSecs: 8000,  now: now), // >2h
            session(id: "dead",    name: "d", state: .working, created: 4, ageSecs: 1, now: now, pid: 1),
        ]
        let out = render(sessions: sessions, now: now,
                         isAlive: { $0 != 1 })  // pid 1 == "dead"
        XCTAssertEqual(out.map { $0.session.sessionId }, ["live", "stale"])
        XCTAssertEqual(out.map { $0.display }, [.ready, .stale])
    }

    func testDuplicateNamesDisambiguated() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sessions = [
            session(id: "x", name: "webapp", state: .ready, created: 10, ageSecs: 1, now: now),
            session(id: "y", name: "webapp", state: .working, created: 20, ageSecs: 1, now: now),
            session(id: "z", name: "solo",   state: .ready, created: 30, ageSecs: 1, now: now),
        ]
        let out = render(sessions: sessions, now: now, isAlive: { _ in true })
        XCTAssertEqual(out.map { $0.label }, ["webapp·1", "webapp·2", "solo"])
    }

    func testTruncate() {
        XCTAssertEqual(truncate("short"), "short")
        XCTAssertEqual(truncate("infrastructure", maxLength: 10), "infrastru…")
    }

    func testPidAliveForCurrentProcess() {
        XCTAssertTrue(pidIsAlive(Int(ProcessInfo.processInfo.processIdentifier)))
        XCTAssertFalse(pidIsAlive(0))
        XCTAssertFalse(pidIsAlive(-5))
    }
}
