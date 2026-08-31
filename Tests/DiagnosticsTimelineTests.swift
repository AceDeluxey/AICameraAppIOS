@testable import AICameraApp
import XCTest

final class DiagnosticsTimelineTests: XCTestCase {
    func testRecordsEventsInOrder() async {
        let timeline = DiagnosticsTimeline()
        let detection = DiagnosticsEvent(
            kind: .detectionCompleted,
            timestamp: Date(timeIntervalSince1970: 1),
            durationMilliseconds: 20
        )
        let focus = DiagnosticsEvent(
            kind: .focusRequested,
            timestamp: Date(timeIntervalSince1970: 2),
            details: "0.4,0.5"
        )

        await timeline.record(detection)
        await timeline.record(focus)

        let events = await timeline.snapshot()
        XCTAssertEqual(events, [detection, focus])
    }

    func testDropsOldestEventsAtCapacity() async {
        let timeline = DiagnosticsTimeline(capacity: 2)
        await timeline.record(DiagnosticsEvent(kind: .cameraStarted))
        await timeline.record(DiagnosticsEvent(kind: .detectionCompleted))
        await timeline.record(DiagnosticsEvent(kind: .targetLost))

        let events = await timeline.snapshot()

        XCTAssertEqual(events.map(\.kind), [.detectionCompleted, .targetLost])
    }

    func testResetClearsTimeline() async {
        let timeline = DiagnosticsTimeline()
        await timeline.record(DiagnosticsEvent(kind: .focusCompleted))

        await timeline.reset()

        let events = await timeline.snapshot()
        XCTAssertTrue(events.isEmpty)
    }
}
