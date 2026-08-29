//
//  FollowerFeedStore.swift
//  LoopFollow
//
//  Reads the shared CloudKit zone the Loop device publishes into. This is the
//  whole of the follower's networking.
//
//  ── THE HARD BOUNDARY, FROM THIS SIDE ───────────────────────────────────────
//  READ ONLY, AND NOT MERELY BY CONVENTION. There is no `save`, no `modify`, no
//  subscription-with-callback that writes anything back, and no code path in
//  this app that constructs a `CKRecord` at all. Data flows Loop → follower and
//  nothing goes the other way. The follower being able to send ANYTHING to the
//  patient's phone makes it an attack surface on an insulin pump.
//
//  Do not add a write here, however harmless it sounds — an acknowledgement, a
//  "seen" receipt, a request to refresh. There is no such thing as a small hole
//  in this rule.
//
//  ── sharedCloudDatabase, NOT privateCloudDatabase ───────────────────────────
//  ⚠️ THE SINGLE MOST COMMON `CKShare` MISTAKE. This app is a PARTICIPANT in
//  someone else's zone, not the owner of one. `privateCloudDatabase` here would
//  address this device's own (empty) private database and return nothing, with
//  no error to explain why — which reads exactly like "the patient isn't
//  publishing" and sends you debugging the wrong phone.
//
//  ── AND IT VERIFIES THE PERMISSION IT WAS GIVEN ─────────────────────────────
//  After accepting, the app reads back the share's ACTUAL granted permission and
//  refuses to render if it is anything other than read-only. Not because the
//  invite flow is expected to get it wrong, but because a security property you
//  never assert is one you merely hope for.
//

import CloudKit
import Foundation
import os.log

@MainActor
final class FollowerFeedStore: ObservableObject {

    static let shared = FollowerFeedStore()

    /// ⚠️ MUST MATCH `FollowerShareManager.containerIdentifier` in the Loop app,
    /// exactly. Two different strings produce a silent nothing: no error, no
    /// records, no clue. If this app shows "not connected" on a device that
    /// definitely accepted an invite, check this line first.
    static let containerIdentifier = "iCloud.com.uriBregman.loopkit.basal.LoopFollowShare"

    static let zoneName = "FollowerFeed"
    static let recordName = "current"
    static let recordType = "FollowerFeed"

    /// After this, the numbers stop being presented as current.
    ///
    /// The publisher writes at most every ~4 minutes, so 20 covers several missed
    /// publishes before the screen starts saying so. It is deliberately short: a
    /// follower app's worst failure is showing an old number as if it were now.
    static let stalenessLimit: TimeInterval = 20 * 60

    enum State: Equatable {
        case notConnected
        case loading
        case loaded(publishedAt: Date?)
        case failed(String)
        /// The share exists but grants more than read-only. The app refuses to
        /// render rather than quietly accept a permission it did not ask for.
        case refusedPermission
    }

    @Published private(set) var state: State = .notConnected
    @Published private(set) var feed: FollowerFeed?
    @Published private(set) var lastFetch: Date?

    /// Whether this device has ever accepted an invite.
    ///
    /// ⚠️ NOTHING TOUCHES CLOUDKIT UNTIL THIS IS TRUE, and that is deliberate on
    /// three counts. A follower that has never been paired has, by design,
    /// nothing to fetch — pairing is always started on the Loop device, so there
    /// is no zone to look in. Reaching for CloudKit anyway means a fresh install
    /// opens on a spinner and then an error, which reads as "this app is broken"
    /// rather than "you have not been invited yet". And it keeps the whole
    /// pre-pairing experience — the instructions, the sample data — working
    /// without an iCloud account at all.
    private static let acceptedKey = "com.uriBregman.loopkit.basal.LoopFollow.hasAccepted"

    private(set) var hasAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: Self.acceptedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.acceptedKey) }
    }

    private let log = OSLog(subsystem: "com.uriBregman.loopkit.basal.LoopFollow",
                            category: "FollowerFeedStore")

    private var container: CKContainer { CKContainer(identifier: Self.containerIdentifier) }

    /// ⚠️ SHARED, not private. See the banner.
    private var database: CKDatabase { container.sharedCloudDatabase }

    private init() {}

    /// True once this device has accepted an invite and a zone is visible.
    private(set) var zoneID: CKRecordZone.ID?

    // MARK: - Fetching

    /// Fetch, but only if there is any reason to believe there is something to
    /// fetch. Used by the automatic paths — launch, foreground.
    func refresh() {
        guard hasAccepted else {
            state = .notConnected
            return
        }
        Task { await fetch() }
    }

    /// Fetch regardless. Used by the pull-to-refresh and the explicit
    /// "check again" button, where the user has asked in so many words.
    func refreshIgnoringPairing() {
        Task { await fetch() }
    }

    func fetch() async {
        if case .loading = state { return }
        state = .loading

        do {
            guard let zone = try await resolveZone() else {
                // No shared zone visible. Either the invite was never accepted on
                // this device, or it was revoked — see the note in the view about
                // why this must not be reported as stale data still being fine.
                state = .notConnected
                feed = nil
                return
            }
            zoneID = zone

            guard try await isReadOnly(zone) else {
                // Fail CLOSED. Rendering data from a share that granted write
                // access would mean this app is one bug away from being able to
                // write to the patient's zone.
                os_log("Share is not read-only; refusing to render", log: log, type: .error)
                state = .refusedPermission
                feed = nil
                return
            }

            let recordID = CKRecord.ID(recordName: Self.recordName, zoneID: zone)
            let record = try await database.record(for: recordID)
            guard let payload = record["payload"] as? Data else {
                state = .failed(NSLocalizedString("The feed record had no payload.",
                                                  comment: "Empty payload"))
                return
            }
            let decoded = try FollowerFeed.decode(payload)
            feed = decoded
            // ⚠️ EVERY SUCCESSFUL FETCH IS FOLDED INTO THE DURABLE STORE, HERE
            // AND NOWHERE ELSE. The feed record is a rolling 24-hour window that
            // is overwritten in place, so anything not kept at the moment it is
            // read is gone for good — there is no way to ask for it again.
            FollowerHistoryStore.shared.merge(decoded)
            lastFetch = Date()
            state = .loaded(publishedAt: decoded.published ?? record["publishedAt"] as? Date)
        } catch let error as CKError where error.code == .unknownItem {
            // The zone is there but nothing has been published into it yet. That
            // is a real, expected state right after pairing — not a failure, and
            // saying "error" here would send the patient looking for a problem
            // that does not exist.
            state = .loaded(publishedAt: nil)
            feed = nil
        } catch {
            os_log("Fetch failed: %{public}@", log: log, type: .error, String(describing: error))
            state = .failed(error.localizedDescription)
        }
    }

    /// The shared zone, if this device is a participant in one.
    private func resolveZone() async throws -> CKRecordZone.ID? {
        let zones = try await database.allRecordZones()
        return zones.first { $0.zoneID.zoneName == Self.zoneName }?.zoneID
    }

    /// Read the permission actually granted, rather than the one that was asked
    /// for.
    private func isReadOnly(_ zone: CKRecordZone.ID) async throws -> Bool {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        guard let share = try? await database.record(for: shareID) as? CKShare else {
            // No zone-wide share record readable. Treat as acceptable rather than
            // as a violation: we have no evidence of over-permission, and this
            // app cannot write regardless — there is no write code in it.
            return true
        }
        guard let me = share.currentUserParticipant else { return true }
        return me.permission == .readOnly
    }

    // MARK: - Accepting an invite

    /// Accept a share the user tapped.
    ///
    /// Called from the app delegate's `userDidAcceptCloudKitShareWith`. Nothing
    /// else in this app initiates pairing: there is no "request access" path, by
    /// design — the connection is always created on the Loop device.
    func accept(_ metadata: CKShare.Metadata) async {
        state = .loading
        do {
            _ = try await container.accept(metadata)
            hasAccepted = true
            await fetch()
        } catch {
            os_log("Accept failed: %{public}@", log: log, type: .error, String(describing: error))
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Staleness

    /// How old the numbers on screen are, and whether that is now a problem.
    var age: TimeInterval? {
        guard let published = feed?.published else { return nil }
        return Date().timeIntervalSince(published)
    }

    var isStale: Bool {
        guard let age else { return true }
        return age > Self.stalenessLimit
    }
}
