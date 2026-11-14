import XCTest
@testable import PlaybackCore

final class PlaylistTests: XCTestCase {
    func testEndAndLoop() {
        let ids = (0..<3).map { _ in UUID() }
        var list = Playlist()
        list.reset(ids, shuffle: false)
        XCTAssertEqual(list.current, ids[0])
        XCTAssertEqual(list.advance(loop: false, shuffle: false), ids[1])
        XCTAssertEqual(list.advance(loop: false, shuffle: false), ids[2])
        XCTAssertNil(list.advance(loop: false, shuffle: false))
        XCTAssertEqual(list.advance(loop: true, shuffle: false), ids[0])
    }
    func testShuffleVisitsEveryItemAndAvoidsBoundaryRepeat() {
        let ids = (0..<20).map { _ in UUID() }
        var list = Playlist()
        list.reset(ids, shuffle: true)
        for _ in 0..<100 {
            var visited = [list.current!]
            for _ in 1..<ids.count { visited.append(list.advance(loop: true, shuffle: true)!) }
            XCTAssertEqual(Set(visited), Set(ids))
            let last = list.current
            XCTAssertNotEqual(list.advance(loop: true, shuffle: true), last)
        }
    }
    func testKeepCurrentAndEmptyAndSingle() {
        let id = UUID()
        var list = Playlist()
        XCTAssertNil(list.advance(loop: true, shuffle: true))
        list.reset([id], shuffle: true, keeping: id)
        XCTAssertEqual(list.advance(loop: true, shuffle: true), id)
        XCTAssertEqual(list.previous(), id)
        let others = [UUID(), id, UUID()]
        list.reset(others, shuffle: true, keeping: id)
        XCTAssertEqual(list.current, id)
        XCTAssertEqual(Set(list.order), Set(others))
    }
}
