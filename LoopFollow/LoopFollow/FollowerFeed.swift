//
//  FollowerFeed.swift
//  LoopFollow
//
//  The wire format, decoded. This is the ONLY thing the follower knows about the
//  Loop device, and it is deliberately a hand-written mirror of what
//  `FollowerPublisher.buildPayload()` writes — not a shared model type.
//
//  ⚠️ WHY NOT SHARE A TYPE WITH LOOP. Sharing one would mean this app links a
//  module from the app that drives an insulin pump, which is exactly what the
//  read-only boundary forbids, and it would make "add a field to the model" a
//  change that silently widens the wire format. Two independent definitions mean
//  a new field has to be added ON PURPOSE at both ends, which is the point.
//
//  ⚠️ EVERY FIELD IS OPTIONAL AND DECODING NEVER THROWS ON AN UNKNOWN ONE. The
//  publisher is a different app on a different phone, on a version this one does
//  not control. A follower that refuses to render because a field it did not
//  expect appeared is a follower that goes blank at 3am after the patient
//  updates Loop.
//

import Foundation

/// One record from the rolling window.
///
/// `Codable` rather than `Decodable` because `FollowerHistoryStore` writes these
/// straight back out to keep more than the feed's 24-hour window.
struct FeedRecord: Codable, Identifiable {
    let t: String
    let at: String

    // glucose
    var mgdl: Double?
    var trendRate: Double?
    // meal
    var grams: Double?
    var absorption: Double?
    var eatenAt: String?
    var mealName: String?
    // dose
    var kind: String?
    var units: Double?
    var unitsPerHour: Double?
    var automatic: Bool?
    // pod
    var activatedAt: String?
    var hoursRun: Double?
    var stopReason: String?

    var id: String { "\(t)|\(at)|\(mgdl ?? units ?? grams ?? 0)" }

    var date: Date? { FeedTimestamp.date(from: at) }
}

/// The therapy settings snapshot. Read-only, and shown WITHOUT any control that
/// could change it — see the follower's settings screen.
struct FeedSettings: Decodable {
    struct ScheduleItem: Decodable {
        let startSeconds: Double
        var value: Double?
        var minMgdl: Double?
        var maxMgdl: Double?
    }
    var patientLabel: String?
    var appVersion: String?
    var glucoseUnit: String?
    var basalSchedule: [ScheduleItem]?
    var insulinSensitivitySchedule: [ScheduleItem]?
    var carbRatioSchedule: [ScheduleItem]?
    var correctionRangeSchedule: [ScheduleItem]?
    var suspendThresholdMgdl: Double?
    var maximumBolus: Double?
    var maximumBasalRate: Double?
}

/// The newest `status` line — one loop cycle's derived state, as the ALGORITHM
/// computed it on the patient's phone.
///
/// ⚠️ IOB, COB AND THE PREDICTION ARE READ, NEVER RECOMPUTED. Recomputing them
/// here would mean shipping the dosing algorithm into this app, which is the one
/// thing it exists not to do — and a follower's IOB quietly disagreeing with the
/// patient's own screen would be worse than showing no IOB at all.
///
/// Mirrors `StatusHistoryRecord` field for field. When that gains a field, this
/// does not, until someone decides it should.
struct FeedStatus: Decodable {
    var at: String?

    var glucoseMgdl: Double?
    var glucoseAt: String?
    var glucoseTrend: String?
    var glucoseTrendRate: Double?

    /// "green" / "yellow" / "red". A string on purpose: an unknown future value
    /// has to degrade to "we don't know" rather than fail the decode.
    var loopStatus: String?
    var lastLoopAt: String?

    var predictedGlucose: [PredictedPoint]?

    var activeInsulin: Double?
    var activeCarbs: Double?
    var iobTimeline: [TimelinePoint]?
    var cobTimeline: [TimelinePoint]?

    var basalRate: Double?
    var isBasalTemporary: Bool?
    var isDeliverySuspended: Bool?

    var overrideName: String?
    var overrideSymbol: String?
    var overrideEndsAt: String?

    var reservoirUnits: Double?
    var pumpBatteryPercent: Double?
    var podActivatedAt: String?
    var podExpiresAt: String?

    var sensorSessionStart: String?
    var sensorExpiresAt: String?

    struct PredictedPoint: Decodable, Identifiable {
        let at: String
        let mgdl: Double
        var id: String { at }
        var date: Date? { FeedTimestamp.date(from: at) }
    }

    struct TimelinePoint: Decodable, Identifiable {
        let at: String
        let value: Double
        var id: String { at }
        var date: Date? { FeedTimestamp.date(from: at) }
    }

    var date: Date? { at.flatMap(FeedTimestamp.date(from:)) }
    var lastLoop: Date? { lastLoopAt.flatMap(FeedTimestamp.date(from:)) }
    var glucoseDate: Date? { glucoseAt.flatMap(FeedTimestamp.date(from:)) }
    var podExpires: Date? { podExpiresAt.flatMap(FeedTimestamp.date(from:)) }
    var sensorExpires: Date? { sensorExpiresAt.flatMap(FeedTimestamp.date(from:)) }
}

/// One published payload.
struct FollowerFeed: Decodable {
    var v: Int?
    var publishedAt: String?
    var records: [FeedRecord]?
    var status: FeedStatus?
    var settings: FeedSettings?

    var published: Date? { publishedAt.flatMap(FeedTimestamp.date(from:)) }

    static func decode(_ data: Data) throws -> FollowerFeed {
        try JSONDecoder().decode(FollowerFeed.self, from: data)
    }

    // MARK: Derived views of the window

    var glucose: [FeedRecord] {
        (records ?? []).filter { $0.t == "glucose" && $0.mgdl != nil }
            .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    var latestGlucose: FeedRecord? { glucose.last }

    var meals: [FeedRecord] {
        (records ?? []).filter { $0.t == "meal" }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var doses: [FeedRecord] {
        (records ?? []).filter { $0.t == "dose" }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}

/// The publisher's timestamp format, and only that format.
enum FeedTimestamp {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? fractional.date(from: string)
    }
}
