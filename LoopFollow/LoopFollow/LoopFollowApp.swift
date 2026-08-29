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

    var body: some Scene {
        WindowGroup {
            FollowerStatusView()
                .environmentObject(store)
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
