//
//  FollowerHistoryStore.swift
//  LoopFollow
//
//  Everything this app has ever received, kept on disk.
//
//  ── WHY THIS HAS TO EXIST ───────────────────────────────────────────────────
//  The feed is a ROLLING 24-HOUR WINDOW, overwritten in place on every publish.
//  Without somewhere to put it, this app can never show more than a day, and a
//  "statistics" screen built on one day is not statistics, it is today.
//
//  The publisher was written expecting this: its own comment says a rolling
//  window is fine because "the follower already keeps its own durable log and
//  de-duplicates what it receives". This is that.
//
//  ⚠️ WHAT IT CANNOT DO, AND SAYS SO ON SCREEN. It only holds what it actually
//  received. Anything published while this app was not fetching — phone off,
//  app not opened for two days, iCloud unreachable — is simply gone, because
//  the record it would have come from was overwritten. So the history here is
//  NOT the patient's history; it is the part of it this app happened to see.
//  Every screen built on it has to say that, or it is quietly lying about a
//  medical record. See `coverageNote`.
//
//  ⚠️ De-duplication is by VALUE, not by identifier. The payload deliberately
//  strips `syncIdentifier` — it is a pump radio credential — so there is nothing
//  stable to key on but the record's own contents. Two genuinely identical
//  readings at the same instant are the same reading.
//

import Foundation
import os.log

@MainActor
final class FollowerHistoryStore: ObservableObject {

    static let shared = FollowerHistoryStore()

    /// How far back to keep. Beyond this the oldest records are dropped on the
    /// next merge — this is a follower's convenience, not an archive, and an
    /// unbounded file on someone's phone is a bug waiting to be filed.
    static let retention: TimeInterval = 90 * 24 * 3600

    @Published private(set) var records: [FeedRecord] = []
    /// The first record this app ever received, which is where any honest
    /// statement about coverage has to start.
    @Published private(set) var collectingSince: Date?

    private let log = OSLog(subsystem: "com.uriBregman.loopkit.basal.LoopFollow",
                            category: "FollowerHistoryStore")

    private var fileURL: URL? {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        return directory.appendingPathComponent("follower-history.json")
    }

    private init() { load() }

    // MARK: - Merging

    /// Fold a freshly fetched payload into what is already held.
    func merge(_ feed: FollowerFeed) {
        let incoming = feed.records ?? []
        guard !incoming.isEmpty else { return }

        var seen = Set(records.map(Self.key))
        var merged = records
        var added = 0
        for record in incoming where !seen.contains(Self.key(record)) {
            seen.insert(Self.key(record))
            merged.append(record)
            added += 1
        }
        guard added > 0 else { return }

        let cutoff = Date().addingTimeInterval(-Self.retention)
        merged = merged
            .filter { ($0.date ?? .distantPast) >= cutoff }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }

        records = merged
        collectingSince = merged.first?.date
        save()
    }

    /// The de-duplication key. Contents only — see the banner.
    private static func key(_ record: FeedRecord) -> String {
        switch record.t {
        case "glucose":
            return "g|\(record.at)|\(record.mgdl ?? -1)"
        case "meal":
            return "m|\(record.eatenAt ?? record.at)|\(record.grams ?? -1)"
        case "dose":
            return "d|\(record.kind ?? "?")|\(record.at)|\(record.units ?? -1)|\(record.unitsPerHour ?? -1)"
        default:
            return "\(record.t)|\(record.at)"
        }
    }

    // MARK: - Persistence

    private struct Stored: Codable {
        let records: [FeedRecord]
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            // A file this app cannot read is a file from an older shape of this
            // app. Dropping it loses convenience data only — the patient's real
            // record lives on their phone — and is far better than refusing to
            // start.
            os_log("Discarding unreadable history file", log: log, type: .error)
            return
        }
        records = stored.records.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
        collectingSince = records.first?.date
    }

    private func save() {
        guard let fileURL else { return }
        let snapshot = Stored(records: records)
        Task.detached(priority: .utility) {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Losing the cache is survivable; crashing a follower app at 3am
                // is not.
            }
        }
    }

    // MARK: - Coverage

    /// Days that hold at least one glucose reading. The denominator for anything
    /// this app says "per day".
    var daysWithData: Int {
        let calendar = Calendar.current
        return Set(records.compactMap { record -> Date? in
            guard record.t == "glucose", let date = record.date else { return nil }
            return calendar.startOfDay(for: date)
        }).count
    }

    /// ⚠️ SHOWN WHEREVER THESE NUMBERS ARE. Not a footnote to be trimmed later.
    var coverageNote: String {
        guard let collectingSince else {
            return NSLocalizedString("Nothing collected yet.", comment: "Coverage, empty")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return String(format: NSLocalizedString(
            "Based on %1$d days of data this app collected since %2$@. It only receives updates while both phones are running and online, so anything published while this app was closed is not here — these are not their full records.",
            comment: "Coverage caveat"), daysWithData, formatter.string(from: collectingSince))
    }
}
