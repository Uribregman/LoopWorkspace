//
//  FollowerStatsView.swift
//  LoopFollow
//
//  Summary numbers, computed HERE from what this app has collected.
//
//  ── WHY THESE ARE NOT THE NUMBERS ON THE PATIENT'S SCREEN ───────────────────
//  ⚠️ AND WHY THAT IS SAID ON THE SCREEN RATHER THAN BURIED HERE. The Loop app
//  computes its statistics from a complete history log. This app has only what
//  it managed to fetch before each 24-hour window was overwritten — so if the
//  follower's phone was off for a day, that day does not exist here. The two
//  will disagree, sometimes substantially, and a follower quoting a time in
//  range that contradicts the patient's own screen without explaining why is
//  worse than showing nothing.
//
//  ⚠️ DELIBERATELY THE SIMPLE MEASURES ONLY. Time in range, average, GMI, CV,
//  and per-day totals — all of which are honest on partial data. NOT the
//  consensus hypo/hyper EVENT counts, which need the 15-minute rule and
//  therefore need continuous readings; on gappy data they would silently
//  undercount, and an undercounted low is exactly the wrong number to be wrong
//  about. The reading-level shares below are labelled as such.
//

import SwiftUI

struct FollowerStatsView: View {
    @EnvironmentObject private var store: FollowerFeedStore
    @EnvironmentObject private var history: FollowerHistoryStore
    @AppStorage("com.uriBregman.loopkit.basal.LoopFollow.sample") private var showingSample = false

    /// The durable store, or the fixture while sample mode is on.
    private var source: [FeedRecord] {
        showingSample ? (FollowerFixture.feed.records ?? []) : history.records
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if summary.readings < 12 {
                        tile {
                            Text("Not enough collected yet", comment: "Stats empty title")
                                .font(.headline)
                            Text("This app builds these up from the updates it receives. Leave it paired and open it now and again.",
                                 comment: "Stats empty explanation")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        rangeTile
                        keyNumbersTile
                        dailyTile
                    }
                    tile {
                        Text(showingSample
                             ? NSLocalizedString("Sample data — not a real person.", comment: "Fixture note")
                             : history.coverageNote)
                            .font(.caption)
                            .foregroundStyle(showingSample ? .orange : .secondary)
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(Text("Summary", comment: "Stats screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.fetch() }
        }
    }

    // MARK: - Tiles

    private var rangeTile: some View {
        tile {
            Text("Time In Range", comment: "Tile title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(percent(summary.inRange))
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    band(summary.veryLow, .purple, geometry.size.width)
                    band(summary.low, .red, geometry.size.width)
                    band(summary.inRange, .green, geometry.size.width)
                    band(summary.high, .yellow, geometry.size.width)
                    band(summary.veryHigh, .orange, geometry.size.width)
                }
            }
            .frame(height: 18)
            .clipShape(Capsule())

            row(NSLocalizedString("Very low (under 54)", comment: "Band"), percent(summary.veryLow))
            row(NSLocalizedString("Low (54–69)", comment: "Band"), percent(summary.low))
            row(NSLocalizedString("In range (70–180)", comment: "Band"), percent(summary.inRange))
            row(NSLocalizedString("High (181–250)", comment: "Band"), percent(summary.high))
            row(NSLocalizedString("Very high (over 250)", comment: "Band"), percent(summary.veryHigh))

            // ⚠️ Says READINGS, not time and not events. On data with gaps in it
            // those are not the same thing, and only one of them is true here.
            Text(String(format: NSLocalizedString("Share of the %d readings this app has received.", comment: "Reading share caveat"),
                        summary.readings))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var keyNumbersTile: some View {
        tile {
            Text("Key Numbers", comment: "Tile title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            row(NSLocalizedString("Average glucose", comment: "Stat"), String(format: "%.0f mg/dL", summary.mean))
            row(NSLocalizedString("Estimated A1c (GMI)", comment: "Stat"), String(format: "%.1f%%", summary.gmi))
            row(NSLocalizedString("Variability (CV)", comment: "Stat"), String(format: "%.0f%%", summary.cv))
            row(NSLocalizedString("Readings under 70", comment: "Stat"), "\(summary.countUnder70)")
            row(NSLocalizedString("Readings over 250", comment: "Stat"), "\(summary.countOver250)")
        }
    }

    private var dailyTile: some View {
        tile {
            Text("Per Day", comment: "Tile title")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            row(NSLocalizedString("Insulin (their own boluses)", comment: "Stat"),
                summary.days > 0 ? String(format: "%.1f U", summary.manualUnits / Double(summary.days)) : "—")
            row(NSLocalizedString("Insulin (automatic)", comment: "Stat"),
                summary.days > 0 ? String(format: "%.1f U", summary.automaticUnits / Double(summary.days)) : "—")
            row(NSLocalizedString("Carbs", comment: "Stat"),
                summary.days > 0 ? String(format: "%.0f g", summary.grams / Double(summary.days)) : "—")
            row(NSLocalizedString("Meals logged", comment: "Stat"),
                summary.days > 0 ? String(format: "%.1f", Double(summary.mealCount) / Double(summary.days)) : "—")
            // ⚠️ The denominator, stated. "18 U a day" over three days and over
            // thirty are different claims.
            Text(String(format: NSLocalizedString("Averaged over the %d days with data.", comment: "Per-day denominator"),
                        summary.days))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - The computation

    private struct Summary {
        var readings = 0
        var mean: Double = 0
        var gmi: Double = 0
        var cv: Double = 0
        var veryLow: Double = 0
        var low: Double = 0
        var inRange: Double = 0
        var high: Double = 0
        var veryHigh: Double = 0
        var countUnder70 = 0
        var countOver250 = 0
        var manualUnits: Double = 0
        var automaticUnits: Double = 0
        var grams: Double = 0
        var mealCount = 0
        var days = 0
    }

    private var summary: Summary {
        var result = Summary()
        let values = source.compactMap { $0.t == "glucose" ? $0.mgdl : nil }
        result.readings = values.count
        result.days = showingSample ? 1 : history.daysWithData

        if !values.isEmpty {
            result.mean = values.reduce(0, +) / Double(values.count)
            // Standard GMI, the published regression on mean glucose.
            result.gmi = 3.31 + 0.02392 * result.mean
            let variance = values.reduce(0) { $0 + pow($1 - result.mean, 2) } / Double(values.count)
            let deviation = sqrt(variance)
            result.cv = result.mean > 0 ? deviation / result.mean * 100 : 0

            let total = Double(values.count)
            result.veryLow = Double(values.filter { $0 < 54 }.count) / total
            result.low = Double(values.filter { $0 >= 54 && $0 < 70 }.count) / total
            result.inRange = Double(values.filter { $0 >= 70 && $0 <= 180 }.count) / total
            result.high = Double(values.filter { $0 > 180 && $0 <= 250 }.count) / total
            result.veryHigh = Double(values.filter { $0 > 250 }.count) / total
            result.countUnder70 = values.filter { $0 < 70 }.count
            result.countOver250 = values.filter { $0 > 250 }.count
        }

        for record in source {
            switch record.t {
            case "dose":
                guard record.kind == "bolus", let units = record.units else { continue }
                if record.automatic == true { result.automaticUnits += units }
                else { result.manualUnits += units }
            case "meal":
                result.grams += record.grams ?? 0
                result.mealCount += 1
            default:
                continue
            }
        }
        return result
    }

    // MARK: - Chrome

    private func band(_ fraction: Double, _ colour: Color, _ width: CGFloat) -> some View {
        Rectangle().fill(colour).frame(width: max(0, width * fraction))
    }

    private func percent(_ fraction: Double) -> String { String(format: "%.0f%%", fraction * 100) }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func tile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
