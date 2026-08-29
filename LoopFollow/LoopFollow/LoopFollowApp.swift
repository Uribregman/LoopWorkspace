//
//  LoopFollowApp.swift
//  LoopFollow
//
//  A read-only window onto someone else's Loop.
//
//  ⛔ THE RULE THIS APP EXISTS TO KEEP: data flows Loop → follower and NOTHING
//  comes back. No write to the shared zone, no acknowledgement, no "request
//  access", no remote command, no bolus, no override, no carb entry. The
//  follower being able to send anything to the patient's phone would make it an
//  attack surface on an insulin pump.
//
//  ⛔ AND IT LINKS NOTHING FROM THE PUMP SIDE. This target does not depend on
//  LoopKit, LoopCore, any PumpManager or CGMManager, or the Loop app target. It
//  cannot dose, cannot connect to a pump, and cannot be made to by accident —
//  the dependency simply is not there to misuse. Adding one is not a refactor,
//  it is a change of what this app is.
//

import CloudKit
import SwiftUI

@main
struct LoopFollowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = FollowerFeedStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var history = FollowerHistoryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(history)
                .onAppear { store.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    // A follower is opened to answer "how are they right now?".
                    // Coming back to it must fetch, not show what was true when
                    // it was last closed.
                    if phase == .active { store.refresh() }
                }
        }
    }
}

/// The four screens.
///
/// ⚠️ "Now" IS FIRST AND IS THE DEFAULT, and the others are deliberately behind
/// it. This app is opened to answer one question — how are they, right now — and
/// anything that makes that answer take a second tap is the wrong shape for the
/// moment it gets used in.
struct RootView: View {
    @EnvironmentObject private var store: FollowerFeedStore
    @EnvironmentObject private var history: FollowerHistoryStore
    @AppStorage("com.uriBregman.loopkit.basal.LoopFollow.sample") private var showingSample = false

    var body: some View {
        TabView {
            FollowerStatusView()
                .tabItem { Label(NSLocalizedString("Now", comment: "Tab"), systemImage: "waveform.path.ecg") }
            FollowerHistoryView()
                .tabItem { Label(NSLocalizedString("History", comment: "Tab"), systemImage: "list.bullet") }
            FollowerStatsView()
                .tabItem { Label(NSLocalizedString("Summary", comment: "Tab"), systemImage: "chart.bar") }
            NavigationStack {
                // ⚠️ Sample mode has to reach EVERY tab. A settings screen saying
                // "nothing has arrived" beside three tabs full of sample numbers
                // is how someone concludes the sample numbers are real.
                FollowerSettingsView(settings: showingSample
                                     ? FollowerFixture.feed.settings
                                     : store.feed?.settings)
            }
            .tabItem { Label(NSLocalizedString("Settings", comment: "Tab"), systemImage: "slider.horizontal.3") }
        }
    }
}

/// Exists for exactly one reason: CloudKit hands share acceptance to the app
/// delegate and nowhere else.
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await FollowerFeedStore.shared.accept(metadata)
        }
    }
}
