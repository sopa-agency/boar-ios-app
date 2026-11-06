import Foundation
import Testing

@testable import BoarRouting

/// android TravelDistanceTest.kt (r4to's src/routing/travelDistance.test.ts), case for case. The table is the one the
/// Boar Distance lab ships (App/Resources/Data, copied from android labs/plugins/distance/res/raw).
struct TravelDistanceTests {
    static let td: TravelDistance = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try! TravelDistance(json: Data(contentsOf: root.appending(path: "App/Resources/Data/lab_distance_world_cities_v1.json")))
    }()

    private var td: TravelDistance { Self.td }

    @Test func answersDistanceRoundTripAndWalkingTimeAlwaysAsAnEstimate() throws {
        let r = try #require(td.answer("How far is it to walk from Paris to Rome and back?"))
        #expect(r.mode == "walk")
        #expect(r.roundTrip)
        #expect(r.straightKm > 1090 && r.straightKm < 1120)
        #expect(r.text.contains("estimate"))
        #expect(r.text.contains("there and back"))
        #expect(r.text.contains("days each way"))
    }

    @Test func coversTheUsualShapesAnyCityPairInTheTable() {
        for q in [
            "how far is it from Lisbon to Madrid?",
            "How far is Kyoto from Tokyo?",
            "What's the distance between Madrid and Barcelona?",
            "distance from Oslo to Bergen",
            "how many km from Bangkok to Chiang Mai by car?",
            "How long would it take to walk from Berlin to Prague?",
            "how many days to bike from Vienna to Budapest and back",
            "How far is it to drive from Los Angeles to San Francisco?",
        ] {
            let r = td.answer(q)
            #expect(r != nil, "\(q)")
            #expect(r?.text.contains("estimate") == true, "\(q)")
        }
    }

    @Test func aTimeQuestionLeadsWithTheTime() throws {
        let text = try #require(td.answer("How long would it take to walk from Berlin to Prague?")).text
        #expect(text.range(of: #"^About \d+ days each way"#, options: .regularExpression) != nil, "\(text)")
    }

    @Test func drivingAndCyclingOnlyStateTheFactorNeverAMappedRoadDistance() throws {
        let d = try #require(td.answer("How far is it to drive from Los Angeles to San Francisco?"))
        #expect(d.text.contains("usually about 25% longer"))
        #expect(d.text.contains("not a mapped route"))
    }

    @Test func fallsBackWhenAPlaceIsNotACityInTheTableOrNotATravelQuestion() {
        for q in [
            "How far is the Moon from the Earth?",
            "how far is it from my hotel to the beach?",
            "distance from Narnia to Mordor",
            "How far can a person walk in a day?",
            "How far is it to walk from Paris to Paris?",
            "Why is Rome far from Paris culturally?",
        ] {
            #expect(td.answer(q) == nil, "\(q)")
        }
    }

    @Test func resolvesTheMostPopulousCityOfANameWithOrWithoutACountry() {
        #expect(td.lookupCity("Paris")?.country == "FR")
        #expect(td.lookupCity("Paris, France")?.country == "FR")
        #expect(TravelDistance.greatCircleKm(0, 0, 0, 1).rounded() == 111)
    }

    @Test func toFixedKeepsItsDecimals() {
        #expect(TravelDistance.toFixed(4, 1) == "4.0")
        #expect(TravelDistance.toFixed(4.25, 1) == "4.3")
        #expect(TravelDistance.toFixed(0.05, 1) == "0.1")
        #expect(TravelDistance.toFixed(1.005, 2) == "1.00")
        #expect(TravelDistance.toFixed(12.34, 1) == "12.3")
    }
}
