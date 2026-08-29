//
//  FollowerFixture.swift
//  LoopFollow
//
//  A checked-in sample payload, so the whole UI can be built and looked at
//  without CloudKit, without a second Apple ID, and without a second phone.
//
//  ⚠️ THIS IS WHY IT EXISTS AND WHY IT COMES FIRST. Pairing needs two accounts
//  on two devices; wiring the screens to a live feed before they are right means
//  every UI change costs a full pairing round trip. The fixture also pins the
//  wire format: if a field is renamed on the publisher, this stops matching and
//  the mismatch shows up here rather than at 3am on someone's mother's phone.
//
//  It is sample data and says so on screen — see the banner in
//  `FollowerStatusView`. A follower app showing invented numbers without saying
//  they are invented would be indefensible.
//

import Foundation

enum FollowerFixture {

    static var feed: FollowerFeed {
        (try? FollowerFeed.decode(Data(json.utf8))) ?? FollowerFeed()
    }

    private static var json: String {
        let now = Date()
        func stamp(_ minutesAgo: Double) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: now.addingTimeInterval(-minutesAgo * 60))
        }

        // A gentle post-meal rise, coming back down.
        let glucose = stride(from: 180.0, through: 0.0, by: -5.0).map { minutesAgo -> String in
            let t = (180.0 - minutesAgo) / 180.0
            let value = 110 + 70 * sin(t * .pi) - 8 * cos(t * 6)
            return """
            {"v":1,"t":"glucose","at":"\(stamp(minutesAgo))","mgdl":\(Int(value)),"trendRate":\(String(format: "%.1f", -0.6))}
            """
        }.joined(separator: ",")

        let iob = stride(from: 180.0, through: 0.0, by: -15.0).map { minutesAgo -> String in
            let t = (180.0 - minutesAgo) / 180.0
            return """
            {"at":"\(stamp(minutesAgo))","value":\(String(format: "%.2f", 4.2 * exp(-t * 1.2)))}
            """
        }.joined(separator: ",")

        let predicted = stride(from: 0.0, through: 240.0, by: 15.0).map { minutesAhead -> String in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let at = formatter.string(from: now.addingTimeInterval(minutesAhead * 60))
            let value = 148 - 45 * (minutesAhead / 240)
            return "{\"at\":\"\(at)\",\"mgdl\":\(Int(value))}"
        }.joined(separator: ",")

        return """
        {
          "v": 1,
          "publishedAt": "\(stamp(2))",
          "records": [\(glucose),
            {"v":1,"t":"meal","at":"\(stamp(95))","grams":48,"absorption":10800,"eatenAt":"\(stamp(100))","mealName":"Pasta"},
            {"v":1,"t":"dose","at":"\(stamp(98))","kind":"bolus","units":4.1,"automatic":false},
            {"v":1,"t":"dose","at":"\(stamp(35))","kind":"tempBasal","unitsPerHour":0.35,"automatic":true}
          ],
          "status": {
            "v": 1, "t": "status", "at": "\(stamp(2))",
            "glucoseMgdl": 148, "glucoseAt": "\(stamp(2))",
            "glucoseTrend": "down", "glucoseTrendRate": -0.6,
            "loopStatus": "green", "lastLoopAt": "\(stamp(2))",
            "predictedGlucose": [\(predicted)],
            "activeInsulin": 3.4, "activeCarbs": 22,
            "iobTimeline": [\(iob)],
            "basalRate": 0.35, "isBasalTemporary": true, "isDeliverySuspended": false,
            "reservoirUnits": 82, "pumpBatteryPercent": 74,
            "podActivatedAt": "\(stamp(2100))", "podExpiresAt": "\(stamp(-2700))",
            "sensorExpiresAt": "\(stamp(-5400))"
          },
          "settings": {
            "v": 1, "t": "settings", "at": "\(stamp(2))",
            "patientLabel": "Sample", "appVersion": "3.14.4", "glucoseUnit": "mg/dL",
            "basalSchedule": [{"startSeconds":0,"value":0.65},{"startSeconds":21600,"value":0.9}],
            "insulinSensitivitySchedule": [{"startSeconds":0,"value":50}],
            "carbRatioSchedule": [{"startSeconds":0,"value":11}],
            "correctionRangeSchedule": [{"startSeconds":0,"minMgdl":100,"maxMgdl":120}],
            "suspendThresholdMgdl": 70, "maximumBolus": 10, "maximumBasalRate": 4
          }
        }
        """
    }
}
