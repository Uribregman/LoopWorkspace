//
//  FollowerStatusView.swift
//  LoopFollow
//
//  The one screen: how is this person, right now.
//
//  ── EVERY NUMBER CARRIES ITS AGE ────────────────────────────────────────────
//  ⚠️ THE WORST THING A FOLLOWER APP CAN DO IS SHOW AN OLD NUMBER AS IF IT WERE
//  NOW. Someone opens this at 3am to decide whether to walk into a bedroom. A
//  glucose value with no timestamp, or one that keeps drawing confidently after
//  the feed has stopped arriving, is not a smaller version of the truth — it is
//  the specific failure that gets somebody hurt.
//
//  So: the reading is stamped, the screen goes grey and says so past the
//  staleness limit, and every failure state is a sentence about what is actually
//  wrong rather than a spinner that never resolves.
//
//  ── NOTHING HERE IS A CONTROL ───────────────────────────────────────────────
//  No bolus, no carbs, no override, no pump action, no "ask them to check". Not
//  disabled, not hidden behind a confirmation — ABSENT. See the banner in
//  `LoopFollowApp`.
//

import Charts
import SwiftUI

struct FollowerStatusView: View {
    @EnvironmentObject private var store: FollowerFeedStore
    /// Shows the checked-in sample instead of the live feed. Only reachable
    /// before pairing, and labelled on screen the whole time it is on.
    @State private var showingSample = false

    private var feed: FollowerFeed? { showingSample ? FollowerFixture.feed : store.feed }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if showingSample { sampleBanner }
                    switch store.state {
                    case .notConnected where !showingSample:
                        notConnectedTile
                    case .refusedPermission:
                        refusedTile
                    case .failed(let message) where feed == nil:
                        failureTile(message)
                    default:
                        if let feed, feed.latestGlucose != nil || feed.status != nil {
                            glucoseTile(feed)
                            chartTile(feed)
                            activeTile(feed)
                            deviceTile(feed)
                            recentTile(feed)
                        } else if !showingSample {
                            waitingTile
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { FollowerSettingsView(settings: feed?.settings) } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
            .refreshable { await store.fetch() }
        }
    }

    private var title: String {
        feed?.settings?.patientLabel ?? NSLocalizedString("Loop Follow", comment: "App name")
    }

    // MARK: - Glucose

    private func glucoseTile(_ feed: FollowerFeed) -> some View {
        let mgdl = feed.status?.glucoseMgdl ?? feed.latestGlucose?.mgdl
        let at = feed.status?.glucoseDate ?? feed.latestGlucose?.date
        let stale = store.isStale && !showingSample

        return tile {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(mgdl.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(size: 60, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    // ⚠️ GREY WHEN STALE. Not a small caption saying it is old —
                    // the number itself stops looking authoritative, because the
                    // number is the thing people read.
                    .foregroundStyle(stale ? .secondary : .primary)
                if let trend = feed.status?.glucoseTrend {
                    Image(systemName: Self.trendSymbol(trend))
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(stale ? .secondary : .primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("mg/dL", comment: "Unit").font(.subheadline).foregroundStyle(.secondary)
                    if let rate = feed.status?.glucoseTrendRate {
                        Text(String(format: "%@%.1f/min", rate >= 0 ? "+" : "", rate))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            // The age, always, in words rather than a timestamp to be decoded.
            HStack(spacing: 6) {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "clock")
                    .font(.caption)
                Text(ageText(at))
                    .font(.subheadline)
                Spacer()
                loopPill(feed.status?.loopStatus, stale: stale)
            }
            .foregroundStyle(stale ? Color.orange : Color.secondary)

            if stale {
                Text("These numbers have stopped arriving. Do not treat what is above as current — check with them directly.",
                     comment: "Stale warning")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func loopPill(_ status: String?, stale: Bool) -> some View {
        let colour: Color = stale ? .secondary : {
            switch status {
            case "green": return .green
            case "yellow": return .yellow
            case "red": return .red
            default: return .secondary
            }
        }()
        return HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(status.map { $0.capitalized } ?? NSLocalizedString("Unknown", comment: "Loop status unknown"))
                .font(.caption)
        }
    }

    // MARK: - Chart

    private func chartTile(_ feed: FollowerFeed) -> some View {
        let readings = feed.glucose.compactMap { record -> (Date, Double)? in
            guard let date = record.date, let mgdl = record.mgdl else { return nil }
            return (date, mgdl)
        }
        let predicted = (feed.status?.predictedGlucose ?? []).compactMap { point -> (Date, Double)? in
            guard let date = point.date else { return nil }
            return (date, point.mgdl)
        }

        return tile {
            Text("Glucose", comment: "Chart title").font(.subheadline.weight(.semibold))
            Chart {
                RectangleMark(yStart: .value("", 70), yEnd: .value("", 180))
                    .foregroundStyle(.green.opacity(0.10))
                ForEach(readings, id: \.0) { point in
                    PointMark(x: .value("Time", point.0), y: .value("mg/dL", point.1))
                        .symbolSize(18)
                        .foregroundStyle(.blue)
                }
                // ⚠️ DASHED, ALWAYS. The prediction is the algorithm's guess
                // about the future; drawn like the readings it would be mistaken
                // for something that happened.
                ForEach(predicted, id: \.0) { point in
                    LineMark(x: .value("Time", point.0), y: .value("mg/dL", point.1),
                             series: .value("", "predicted"))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .foregroundStyle(.blue.opacity(0.6))
                }
            }
            .chartYScale(domain: 40...300)
            .frame(height: 180)
            if !predicted.isEmpty {
                Text("The dashed line is what their Loop predicts, not a measurement.",
                     comment: "Prediction caveat")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Active insulin and carbs

    private func activeTile(_ feed: FollowerFeed) -> some View {
        tile {
            Text("Right Now", comment: "Tile title").font(.subheadline.weight(.semibold))
            row(NSLocalizedString("Active insulin", comment: "Stat"),
                feed.status?.activeInsulin.map { String(format: "%.2f U", $0) })
            row(NSLocalizedString("Active carbs", comment: "Stat"),
                feed.status?.activeCarbs.map { String(format: "%.0f g", $0) })
            if let rate = feed.status?.basalRate {
                row(NSLocalizedString("Basal", comment: "Stat"),
                    String(format: feed.status?.isBasalTemporary == true ? "%.2f U/hr (temp)" : "%.2f U/hr", rate))
            }
            if feed.status?.isDeliverySuspended == true {
                Label(NSLocalizedString("Insulin delivery is suspended.", comment: "Suspended"),
                      systemImage: "pause.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            if let override = feed.status?.overrideName {
                row(NSLocalizedString("Override", comment: "Stat"),
                    "\(feed.status?.overrideSymbol ?? "") \(override)")
            }
        }
    }

    // MARK: - Devices

    private func deviceTile(_ feed: FollowerFeed) -> some View {
        tile {
            Text("Pump & Sensor", comment: "Tile title").font(.subheadline.weight(.semibold))
            row(NSLocalizedString("Reservoir", comment: "Stat"),
                feed.status?.reservoirUnits.map { String(format: "%.0f U", $0) })
            row(NSLocalizedString("Pump battery", comment: "Stat"),
                feed.status?.pumpBatteryPercent.map { String(format: "%.0f%%", $0) })
            if let expires = feed.status?.podExpires {
                row(NSLocalizedString("Pod expires", comment: "Stat"), remaining(expires))
            }
            if let expires = feed.status?.sensorExpires {
                row(NSLocalizedString("Sensor expires", comment: "Stat"), remaining(expires))
            }
        }
    }

    // MARK: - Recent

    private func recentTile(_ feed: FollowerFeed) -> some View {
        tile {
            Text("Recent", comment: "Tile title").font(.subheadline.weight(.semibold))
            let items = (feed.meals.prefix(3) + feed.doses.prefix(4))
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            if items.isEmpty {
                Text("Nothing logged in the last day.", comment: "Empty recent")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                HStack {
                    Text(describe(item)).font(.subheadline)
                    Spacer()
                    Text(ageText(item.date)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func describe(_ record: FeedRecord) -> String {
        switch record.t {
        case "meal":
            let grams = record.grams.map { String(format: "%.0f g", $0) } ?? "—"
            return record.mealName.map { "\($0) · \(grams)" } ?? grams
        case "dose":
            switch record.kind {
            case "bolus":
                let units = record.units.map { String(format: "%.2f U", $0) } ?? "—"
                return record.automatic == true
                    ? String(format: NSLocalizedString("Automatic bolus %@", comment: "Dose"), units)
                    : String(format: NSLocalizedString("Bolus %@", comment: "Dose"), units)
            case "tempBasal":
                return record.unitsPerHour.map { String(format: NSLocalizedString("Temp basal %.2f U/hr", comment: "Dose"), $0) } ?? "Temp basal"
            default:
                return record.kind ?? "Dose"
            }
        default:
            return record.t
        }
    }

    // MARK: - States

    private var notConnectedTile: some View {
        tile {
            Text("Not connected yet", comment: "Not paired title").font(.headline)
            Text("An invite has to be sent from the Loop phone: Settings → Follow → Add Follower. Open the link it produces on this device.",
                 comment: "Pairing instructions")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // ⚠️ NO "REQUEST ACCESS" BUTTON, AND THERE NEVER WILL BE. The
            // connection is always created on the Loop device; a request path
            // would be a message travelling the wrong way.
            Text("This app cannot ask for access, by design — nothing it does ever reaches their phone.",
                 comment: "No back channel note")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Button {
                    store.refreshIgnoringPairing()
                } label: {
                    Text("Check again", comment: "Check for a connection")
                }
                .buttonStyle(.borderedProminent)
                Button {
                    showingSample = true
                } label: {
                    Text("Show sample data", comment: "Show the fixture")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var waitingTile: some View {
        tile {
            Text("Connected — waiting for the first update", comment: "Paired, no data").font(.headline)
            Text("Their Loop publishes every few minutes while it is running. Nothing has arrived in this zone yet.",
                 comment: "Waiting explanation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var refusedTile: some View {
        tile {
            Label(NSLocalizedString("Refusing to show this feed", comment: "Refused title"),
                  systemImage: "lock.slash")
                .font(.headline)
                .foregroundStyle(.red)
            Text("The share granted more than read-only access. This app will not display a feed it could, even in principle, write back to. Ask them to remove and re-send the invite.",
                 comment: "Refused explanation")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func failureTile(_ message: String) -> some View {
        tile {
            Label(NSLocalizedString("Could not reach the feed", comment: "Failure title"),
                  systemImage: "exclamationmark.triangle")
                .font(.headline)
            // The real message, not "something went wrong". Someone debugging
            // this at 3am needs the actual error.
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button { store.refresh() } label: { Text("Try again", comment: "Retry") }
                .buttonStyle(.bordered)
        }
    }

    private var sampleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
            Text("Sample data — not a real person.", comment: "Fixture banner")
            Spacer()
            Button { showingSample = false } label: { Text("Exit", comment: "Leave sample mode") }
        }
        .font(.caption.weight(.semibold))
        .padding(10)
        .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Chrome

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func ageText(_ date: Date?) -> String {
        guard let date else { return NSLocalizedString("time unknown", comment: "No timestamp") }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 0 { return NSLocalizedString("just now", comment: "Age") }
        if seconds < 90 { return NSLocalizedString("just now", comment: "Age") }
        if seconds < 3600 { return String(format: NSLocalizedString("%d min ago", comment: "Age"), seconds / 60) }
        return String(format: NSLocalizedString("%d h ago", comment: "Age"), seconds / 3600)
    }

    private func remaining(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return NSLocalizedString("expired", comment: "Expired") }
        let hours = Int(seconds / 3600)
        if hours < 24 { return String(format: NSLocalizedString("in %d h", comment: "Remaining"), hours) }
        return String(format: NSLocalizedString("in %1$d d %2$d h", comment: "Remaining"), hours / 24, hours % 24)
    }

    static func trendSymbol(_ trend: String) -> String {
        switch trend {
        case "upUpUp", "upDouble": return "arrow.up"
        case "up": return "arrow.up.right"
        case "upHalf", "flatUp": return "arrow.up.right"
        case "flat": return "arrow.right"
        case "downHalf", "flatDown": return "arrow.down.right"
        case "down": return "arrow.down.right"
        case "downDownDown", "downDouble": return "arrow.down"
        default: return "arrow.right"
        }
    }
}
