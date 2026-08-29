//
//  FollowerHistoryView.swift
//  LoopFollow
//
//  What they ate and what insulin they took, day by day.
//
//  ⚠️ MEALS AND BOLUSES ARE SEPARATED, and automatic doses are separated from
//  the person's own. "They bolused 4 units" and "the algorithm gave 0.05 units"
//  are different facts, and a single merged list quietly turns 40 automatic
//  micro-doses a day into visual noise that buries the four that were decisions.
//

import SwiftUI

struct FollowerHistoryView: View {
    @EnvironmentObject private var store: FollowerFeedStore
    @EnvironmentObject private var history: FollowerHistoryStore

    enum Kind: String, CaseIterable, Identifiable {
        case meals, insulin
        var id: String { rawValue }
        var title: String {
            switch self {
            case .meals:   return NSLocalizedString("Meals", comment: "History tab")
            case .insulin: return NSLocalizedString("Insulin", comment: "History tab")
            }
        }
    }

    @AppStorage("com.uriBregman.loopkit.basal.LoopFollow.sample") private var showingSample = false
    @State private var kind: Kind = .meals
    /// Automatic doses are off by default — see the banner.
    @State private var includingAutomatic = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if kind == .insulin {
                        Toggle(NSLocalizedString("Include automatic doses", comment: "Toggle"),
                               isOn: $includingAutomatic)
                            .font(.subheadline)
                    }
                }

                if days.isEmpty {
                    Section {
                        Text("Nothing received yet.", comment: "Empty history")
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(days, id: \.0) { day, items in
                    Section(Self.dayFormatter.string(from: day)) {
                        ForEach(items) { item in
                            row(item)
                        }
                        if kind == .meals {
                            let total = items.compactMap(\.grams).reduce(0, +)
                            if total > 0 { summary(String(format: NSLocalizedString("%.0f g total", comment: "Day total"), total)) }
                        } else {
                            let total = items.compactMap(\.units).reduce(0, +)
                            if total > 0 { summary(String(format: NSLocalizedString("%.2f U total", comment: "Day total"), total)) }
                        }
                    }
                }

                Section {
                    Text(showingSample
                         ? NSLocalizedString("Sample data — not a real person.", comment: "Fixture note")
                         : history.coverageNote)
                        .font(.caption)
                        .foregroundStyle(showingSample ? .orange : .secondary)
                }
            }
            .navigationTitle(Text("History", comment: "History screen title"))
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.fetch() }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(_ record: FeedRecord) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(record)).font(.subheadline)
                if let detail = detail(record) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(record.date.map(Self.timeFormatter.string(from:)) ?? "—")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func summary(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func title(_ record: FeedRecord) -> String {
        if record.t == "meal" {
            let grams = record.grams.map { String(format: "%.0f g", $0) } ?? "—"
            return record.mealName.map { "\($0) · \(grams)" } ?? grams
        }
        switch record.kind {
        case "bolus":
            let units = record.units.map { String(format: "%.2f U", $0) } ?? "—"
            return record.automatic == true
                ? String(format: NSLocalizedString("Automatic %@", comment: "Dose"), units)
                : String(format: NSLocalizedString("Bolus %@", comment: "Dose"), units)
        case "tempBasal":
            return record.unitsPerHour.map { String(format: NSLocalizedString("Temp basal %.2f U/hr", comment: "Dose"), $0) }
                ?? NSLocalizedString("Temp basal", comment: "Dose")
        case "suspend":  return NSLocalizedString("Delivery suspended", comment: "Dose")
        case "resume":   return NSLocalizedString("Delivery resumed", comment: "Dose")
        default:         return record.kind ?? NSLocalizedString("Dose", comment: "Dose")
        }
    }

    private func detail(_ record: FeedRecord) -> String? {
        guard record.t == "meal" else { return nil }
        var parts: [String] = []
        // The EATING time, when it differs from when it was logged. That gap is
        // the single most useful thing on a meal record — it explains post-meal
        // highs on its own — and it is invisible unless both are shown.
        if let eaten = record.eatenAt.flatMap(FeedTimestamp.date(from:)),
           let logged = record.date,
           abs(logged.timeIntervalSince(eaten)) > 300 {
            parts.append(String(format: NSLocalizedString("eaten %@", comment: "Eating time"),
                                Self.timeFormatter.string(from: eaten)))
        }
        if let absorption = record.absorption {
            parts.append(String(format: NSLocalizedString("%.0f h absorption", comment: "Absorption"),
                                absorption / 3600))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Grouping

    /// The durable store, or the fixture while sample mode is on.
    private var source: [FeedRecord] {
        showingSample ? (FollowerFixture.feed.records ?? []) : history.records
    }

    private var filtered: [FeedRecord] {
        switch kind {
        case .meals:
            return source.filter { $0.t == "meal" }
        case .insulin:
            return source.filter { record in
                guard record.t == "dose" else { return false }
                if includingAutomatic { return true }
                return record.automatic != true
            }
        }
    }

    /// Newest day first, newest item first within a day.
    private var days: [(Date, [FeedRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filtered) { record in
            calendar.startOfDay(for: record.date ?? .distantPast)
        }
        return grouped
            .map { ($0.key, $0.value.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) }
            .sorted { $0.0 > $1.0 }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
