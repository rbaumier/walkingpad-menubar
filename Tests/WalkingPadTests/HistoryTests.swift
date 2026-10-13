import Foundation
import Testing
@testable import WalkingPad

private let start = Date(timeIntervalSince1970: 1_760_000_000)

private func status(steps: Int, elapsedSeconds: Int) -> PadStatus {
    PadStatus(belt: .running, elapsedSeconds: elapsedSeconds, steps: steps)
}

private func log(_ readings: [(steps: Int, elapsedSeconds: Int, atSeconds: Double)]) -> ActivityLog {
    var log = ActivityLog()
    for reading in readings {
        log.record(status(steps: reading.steps, elapsedSeconds: reading.elapsedSeconds), at: start + reading.atSeconds)
    }
    return log
}

@Test func firstReadingCountsTheWholeSession() {
    #expect(log([(5_226, 2_866, 0)]).totals(on: start).steps == 5_226)
}

@Test func laterReadingsOnlyAddTheirGain() {
    #expect(log([(100, 60, 0), (150, 90, 30), (150, 90, 60)]).totals(on: start).steps == 150)
}

@Test func counterResetStartsANewSession() {
    #expect(log([(5_226, 2_866, 0), (0, 0, 10), (40, 20, 30)]).totals(on: start).steps == 5_266)
}

@Test func resetSpreadOverSeveralFramesIsCountedOnce() {
    let totals = log([(5_226, 2_866, 0), (5_226, 0, 1), (0, 0, 2), (10, 5, 7)]).totals(on: start)
    #expect(totals.steps == 5_236)
}

@Test func newSessionStartedWhileDisconnectedIsCountedWhole() {
    // Morning: 3 000 steps in 40 min. Mac asleep 3 h; the afternoon session shows 3 500 steps in 30 min.
    let totals = log([(3_000, 2_400, 0), (3_500, 1_800, 10_800)]).totals(on: start)
    #expect(totals.steps == 6_500)
    #expect(totals.activeSeconds == 4_200)
}

@Test func reconnectingToTheSameSessionAddsOnlyTheGain() {
    #expect(log([(2_000, 600, 0), (3_000, 1_200, 3_600)]).totals(on: start).steps == 3_000)
}

@Test func stepsAreCreditedToTheDayTheyHappen() {
    let tomorrow = start + 86_400
    let log = log([(1_000, 600, 0), (1_500, 900, 86_400)])
    #expect(log.totals(on: start).steps == 1_000)
    #expect(log.totals(on: tomorrow).steps == 500)
}

@Test func fileWrittenByThePreviousVersionKeepsCountingTheLiveSession() throws {
    // Copied from a real activity.json, from the build that still tracked distance.
    let saved = """
    {"lastReading":{"elapsedSeconds":1116,"seenAt":813573830.309606,"distanceKm":1.7,"steps":2030},\
    "days":{"2026-10-13":{"activeSeconds":6883,"distanceKm":10.479999999999935,"steps":12562}}}
    """
    var restored = try JSONDecoder().decode(ActivityLog.self, from: Data(saved.utf8))
    let later = Date(timeIntervalSinceReferenceDate: 813_573_830.309606 + 10)
    restored.record(status(steps: 2_050, elapsedSeconds: 1_126), at: later)
    #expect(restored.totals(on: later).steps == 12_582)
    #expect(restored.totals(on: later).activeSeconds == 6_893)
}

@Test func lastReadingSurvivesARestart() throws {
    let saved = log([(2_000, 600, 0)])
    var restored = try JSONDecoder().decode(ActivityLog.self, from: JSONEncoder().encode(saved))
    restored.record(status(steps: 2_100, elapsedSeconds: 660), at: start + 60)
    #expect(restored.totals(on: start).steps == 2_100)
}
