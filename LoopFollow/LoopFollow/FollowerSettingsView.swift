//
//  FollowerSettingsView.swift
//  LoopFollow
//
//  The patient's therapy settings, as VALUES.
//
//  ⚠️ THERE IS NO CONTROL ON THIS SCREEN, AND THAT IS THE WHOLE DESIGN. Not a
//  disabled stepper, not a greyed-out field, not a picker that refuses to commit
//  — plain text. A disabled control still says "this is a thing you could
//  change", and the follower can change nothing about a pump on another person's
//  body. It is a viewer.
//

import SwiftUI

struct FollowerSettingsView: View {
    let settings: FeedSettings?

    var body: some View {
        List {
            if let settings {
                Section {
                    row(NSLocalizedString("Glucose unit", comment: "Setting"), settings.glucoseUnit)
                    row(NSLocalizedString("Loop version", comment: "Setting"), settings.appVersion)
                }
                schedule(NSLocalizedString("Basal rates", comment: "Setting"),
                         settings.basalSchedule, suffix: " U/hr")
                schedule(NSLocalizedString("Insulin sensitivity", comment: "Setting"),
                         settings.insulinSensitivitySchedule, suffix: " mg/dL/U")
                schedule(NSLocalizedString("Carb ratio", comment: "Setting"),
                         settings.carbRatioSchedule, suffix: " g/U")
                if let ranges = settings.correctionRangeSchedule, !ranges.isEmpty {
                    Section(NSLocalizedString("Correction range", comment: "Setting")) {
                        ForEach(Array(ranges.enumerated()), id: \.offset) { _, item in
                            // Both bounds or neither: half a correction range is
                            // not a range, and "100–—" reads as a value.
                            if let low = item.minMgdl, let high = item.maxMgdl {
                                row(time(item.startSeconds), "\(format(low))–\(format(high)) mg/dL")
                            } else {
                                row(time(item.startSeconds), nil)
                            }
                        }
                    }
                }
                Section {
                    row(NSLocalizedString("Suspend threshold", comment: "Setting"),
                        settings.suspendThresholdMgdl.map { "\(format($0)) mg/dL" })
                    row(NSLocalizedString("Maximum bolus", comment: "Setting"),
                        settings.maximumBolus.map { "\(format($0)) U" })
                    row(NSLocalizedString("Maximum basal rate", comment: "Setting"),
                        settings.maximumBasalRate.map { "\(format($0)) U/hr" })
                }
                Section {
                    Text("These are read from their phone. Nothing here can be edited from this app, and nothing this app does reaches their Loop.",
                         comment: "Read-only note")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No settings have arrived yet.", comment: "No settings")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("Their Settings", comment: "Settings viewer title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func schedule(_ title: String, _ items: [FeedSettings.ScheduleItem]?, suffix: String) -> some View {
        if let items, !items.isEmpty {
            Section(title) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(time(item.startSeconds), item.value.map { "\(format($0))\(suffix)" })
                }
            }
        }
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value ?? "—").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    /// Seconds after midnight, in the PATIENT's time zone as it was when they
    /// published. Rendered as a plain clock time rather than converted: their
    /// 6am basal change is a fact about their day, not about the reader's.
    private func time(_ startSeconds: Double) -> String {
        let total = Int(startSeconds)
        return String(format: "%02d:%02d", total / 3600, (total % 3600) / 60)
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }
}
