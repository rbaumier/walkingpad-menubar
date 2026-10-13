import Foundation
import Testing
@testable import WalkingPad

// Frames captured from a real WalkingPad A1 Pro (firmware M30_V187.2.2).
private let capturedStatus = "f8 a2 01 37 01 00 0b 32 00 01 b5 00 14 6a 00 00 02 00 4e fd"

private func frame(_ hex: String) -> Data {
    Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
}

@Test func askStatusMatchesCapturedFrame() {
    #expect(PadCommand.askStatus.frame == frame("f7 a2 00 00 a2 fd"))
}

@Test func setSpeedEncodesTenthsOfKmh() {
    #expect(PadCommand.setSpeed(kmh: 5.5).frame == frame("f7 a2 01 37 da fd"))
}

@Test func parsesCapturedStatus() throws {
    let status = try #require(PadStatus(frame: frame(capturedStatus)))
    #expect(status.belt == .running)
    #expect(status.elapsedSeconds == 2_866)
    #expect(status.steps == 5_226)
}

@Test func rejectsStatusWithBadChecksum() {
    #expect(PadStatus(frame: frame(capturedStatus.replacingOccurrences(of: "4e fd", with: "4f fd"))) == nil)
}

@Test func ignoresHistoryReply() {
    #expect(PadStatus(frame: frame("f8 a7 00 17 92 00 0c 5e 00 05 7c 00 00 d5 00 09 e5 00 fe fd")) == nil)
}
