import AppKit
import Observation
import os

struct DayTotals: Codable {
    var steps = 0
    var activeSeconds = 0
}

/// Last counters read from the pad, kept so the next reading only adds what changed since.
struct PadReading: Codable {
    let steps: Int
    let elapsedSeconds: Int
    let seenAt: Date
}

/// Per-day activity, credited to the day each reading arrives (midnight-safe, restart-safe once persisted).
struct ActivityLog: Codable {
    private(set) var days: [String: DayTotals] = [:]
    private var lastReading: PadReading?

    mutating func record(_ status: PadStatus, at date: Date) {
        defer {
            lastReading = PadReading(steps: status.steps, elapsedSeconds: status.elapsedSeconds, seenAt: date)
        }
        // Elapsed time went down after we lost sight of the pad: it ran a new session meanwhile, count it whole.
        // ponytail: an unseen session longer than the previous one on every counter is still read as a continuation;
        // telling them apart needs the pad's history reply.
        let isUnseenNewSession = lastReading.map {
            status.elapsedSeconds < $0.elapsedSeconds && date.timeIntervalSince($0.seenAt) > 60
        } ?? true
        // Otherwise each counter is diffed on its own: one that went down was reset by the pad,
        // and the pad may reset its counters in separate frames.
        func gain(_ current: Int, since previous: Int?) -> Int {
            guard let previous, !isUnseenNewSession, current >= previous else { return current }
            return current - previous
        }
        let key = Self.key(for: date)
        days[key, default: DayTotals()].steps += gain(status.steps, since: lastReading?.steps)
        days[key, default: DayTotals()].activeSeconds += gain(status.elapsedSeconds, since: lastReading?.elapsedSeconds)
    }

    func totals(on day: Date) -> DayTotals {
        days[Self.key(for: day)] ?? DayTotals()
    }

    private static func key(for date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }
}

@Observable @MainActor final class History {
    private(set) var log: ActivityLog
    /// Moved at midnight too, so `today` rolls over while the pad sends nothing.
    private var day = Date.now
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var isSaveBlocked = false
    @ObservationIgnored private var savedAt = Date.distantPast

    init(fileURL: URL = .applicationSupportDirectory.appending(path: "WalkingPad/activity.json")) {
        self.fileURL = fileURL
        do {
            log = try JSONDecoder().decode(ActivityLog.self, from: Data(contentsOf: fileURL))
        } catch CocoaError.fileReadNoSuchFile {
            log = ActivityLog()
        } catch {
            log = ActivityLog()
            isSaveBlocked = true
            logger.error("History at \(fileURL.path) unreadable (\(error)). Not saving this run so the file stays intact; fix or delete it, then relaunch.")
        }
        let center = NotificationCenter.default
        _ = center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.day = .now }
        }
        _ = center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    func record(_ status: PadStatus) {
        day = .now
        log.record(status, at: day)
        // Throttled write; quitting saves too.
        guard Date.now.timeIntervalSince(savedAt) > 30 else { return }
        save()
    }

    var today: DayTotals {
        log.totals(on: day)
    }

    private func save() {
        guard !isSaveBlocked else { return }
        savedAt = .now
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(log).write(to: fileURL, options: .atomic)
        } catch {
            logger.error("History not saved to \(self.fileURL.path): \(error). Activity stays in memory; next save retries in 30 s.")
        }
    }
}

private let logger = Logger(subsystem: "com.rbaumier.walkingpad", category: "history")
