import Foundation

// KingSmith WalkingPad BLE protocol, reverse-engineered by github.com/ph4r05/ph4-walkingpad.
// Commands go to characteristic FE02, replies come as notifications on FE01.
// Every frame is `F7|F8 <payload> <payload sum mod 256> FD`.

enum PadMode: UInt8 {
    case manual = 1
    case standby = 2
}

enum PadCommand {
    case askStatus
    case setMode(PadMode)
    case setSpeed(kmh: Double)
    case startBelt

    static let beltSpeedKmh = 0.5...6.0

    var frame: Data {
        let payload: [UInt8] = switch self {
        case .askStatus: [0xA2, 0x00, 0x00]
        case .setMode(let mode): [0xA2, 0x02, mode.rawValue]
        case .setSpeed(let kmh): [0xA2, 0x01, UInt8(clamping: Int((kmh * 10).rounded()))]
        case .startBelt: [0xA2, 0x04, 0x01]
        }
        return Data([0xF7] + payload + [checksum(payload), 0xFD])
    }
}

enum BeltState {
    case stopped
    case startCountdown
    case running
}

/// Live counters of the pad's current session, reset by the pad when a new session starts.
struct PadStatus {
    let belt: BeltState
    let elapsedSeconds: Int
    let steps: Int
}

extension PadStatus {
    /// Parses a status reply (`F8 A2 …`, 20 bytes); nil for any other frame or a bad checksum.
    init?(frame: Data) {
        let bytes = [UInt8](frame)
        guard bytes.count == 20, bytes[0] == 0xF8, bytes[1] == 0xA2, bytes[19] == 0xFD,
              bytes[18] == checksum(bytes[1..<18]) else { return nil }
        func uint24(at index: Int) -> Int {
            Int(bytes[index]) << 16 | Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
        }
        // Belt state byte: 1 = running, 9 = start countdown (0 idle, 5 standby).
        belt = switch bytes[2] {
        case 1: .running
        case 9: .startCountdown
        default: .stopped
        }
        // Byte 3 is the speed in tenths of km/h, byte 4 the mode, bytes 8-10 the distance in 10 m; unused for now.
        elapsedSeconds = uint24(at: 5)
        steps = uint24(at: 11)
    }
}

extension PadStatus {
    var isBeltMoving: Bool { belt != .stopped }
}

private func checksum(_ payload: some Sequence<UInt8>) -> UInt8 {
    payload.reduce(0, &+)
}
