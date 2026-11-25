import BoarRouting
import Foundation
import Testing

@testable import BoarAnswer

/// Android's PluginAnswersTest (engine/labs, rc3 7286cf91 and bd041e73): the questions Lunar, Nomad and Vitals answer.
struct PluginAnswersTests {
    @Test func moonQuestionsAboutNowAreTakenHistoryAndScienceAreNot() {
        for q in ["what phase is the moon tonight?", "when is the next full moon", "is the moon waxing or waning now?", "qual a fase da lua hoje?", "quando é a próxima lua cheia?"] {
            #expect(PluginAnswers.isMoonQuestion(q), "\(q)")
        }
        for q in ["who was the first man on the moon", "Apollo 11 moon landing", "how far is the moon", "why does the moon have phases in physics terms gravity"] {
            #expect(!PluginAnswers.isMoonQuestion(q), "\(q)")
        }
    }

    @Test func theMoonAnswerGivesThePhaseTheLitShareAndTheNextFullAndNewMoon() {
        let utc = TimeZone(identifier: "UTC")!
        let now: Int64 = 1_762_819_200_000 // 2025-11-11
        let en = PluginAnswers.moonAnswer("what phase is the moon tonight?", nowMs: now, zone: utc)
        #expect(en.contains("% lit") && en.contains("Next full moon:") && en.contains("Next new moon:"), "\(en)")
        let pt = PluginAnswers.moonAnswer("qual a fase da lua hoje?", nowMs: now, zone: utc)
        #expect(pt.contains("% iluminada") && pt.contains("Próxima lua cheia:"), "\(pt)")
        // SimpleDateFormat's "MMMM d, HH:mm" and "d 'de' MMMM, HH:mm".
        #expect(Self.matches(en, #"Next full moon: [A-Z][a-z]+ \d{1,2}, \d\d:\d\d\."#), "\(en)")
        #expect(Self.matches(pt, #"Próxima lua cheia: \d{1,2} de [a-zç]+, \d\d:\d\d\."#), "\(pt)")
    }

    @Test func directionQuestionsAreTakenGeographyIsNot() {
        for q in ["which way is north?", "where is north", "which direction am I facing", "onde fica o norte?", "para que lado estou virado?", "para onde estou virado?"] {
            #expect(PluginAnswers.isDirectionQuestion(q), "\(q)")
        }
        for q in ["what is north of France", "the north pole", "history of West Germany"] { #expect(!PluginAnswers.isDirectionQuestion(q), "\(q)") }
    }

    @Test func theDirectionAnswerSaysWhereNorthIsAndToHoldThePhoneFlatWhenTilted() {
        let flat = PluginAnswers.directionAnswer("which way is north?", heading: 90, tiltDeg: 5)
        #expect(flat.contains("points east (90°)") && flat.contains("North is 90° to your left") && !flat.contains("Hold the phone flat"), "\(flat)")
        let tilted = PluginAnswers.directionAnswer("which way is north?", heading: 10, tiltDeg: 30)
        #expect(tilted.contains("Hold the phone flat") && tilted.contains("North is 10° to your left"), "\(tilted)")
        #expect(PluginAnswers.directionAnswer("onde fica o norte?", heading: 270, tiltDeg: 0).contains("O norte fica a 90° à direita"))
        #expect(PluginAnswers.directionAnswer("which way is north?", heading: nil, tiltDeg: nil).contains("no compass"))
    }

    @Test func phoneQuestionsAreTakenPhonesInGeneralAreNot() {
        for q in ["how hot is my phone?", "what's my phone's battery level", "how much memory does this phone have free", "qual a temperatura do meu celular?", "quanta bateria tem o celular?"] {
            #expect(PluginAnswers.isPhoneQuestion(q), "\(q)")
        }
        for q in ["who invented the phone", "how does a phone battery work in general chemistry"] { #expect(!PluginAnswers.isPhoneQuestion(q), "\(q)") }
    }

    @Test func thePhoneAnswerReadsWhatItHas() {
        let a = PluginAnswers.phoneAnswer("how hot is my phone?", .init(batteryPct: 81, charging: true, batteryTempC: 39.4, ramFreeMb: 4300, ramTotalMb: 11400, cores: 8))
        #expect(a.contains("Battery at 81%, charging") && a.contains("39.4 °C (warm)") && a.contains("4.2 GB of 11.1 GB memory free") && a.contains("8 processor cores"), "\(a)")
        let pt = PluginAnswers.phoneAnswer("qual a temperatura do meu celular?", .init(batteryPct: 50, charging: false, batteryTempC: 30.0, ramFreeMb: nil, ramTotalMb: nil, cores: nil))
        #expect(pt.contains("30,0 °C (fria)"), "\(pt)")
    }

    @Test func naturalPhrasingsAreTakenTooTheHistoryGuardStays() {
        for q in ["where's the north?", "where’s the north?", "whats north", "which way's north?", "where's north"] {
            #expect(PluginAnswers.isDirectionQuestion(q), "\(q)")
        }
        #expect(!PluginAnswers.isDirectionQuestion("what's north of France?"))
        for q in ["moon tonight", "whats the moon like", "what's the moon doing", "moon phase", "como está a lua?"] {
            #expect(PluginAnswers.isMoonQuestion(q), "\(q)")
        }
        for q in ["moon landing tonight documentary", "apollo moon phase mission", "moon distance today"] {
            #expect(!PluginAnswers.isMoonQuestion(q), "\(q)")
        }
        for q in ["my battery", "how hot is my phone", "battery level?", "minha bateria"] {
            #expect(PluginAnswers.isPhoneQuestion(q), "\(q)")
        }
    }

    @Test func aPlaceNamedAfterACardinalIsNotAHeading() {
        for q in ["Where is North Carolina?", "where's South Dakota", "What's North Korea's capital", "what's West Virginia known for",
                  "where is East Timor", "whats South Africa", "find North Dakota", "onde fica o Sul do Brasil", "onde fica o Norte Shopping", "where is the north pole"] {
            #expect(!PluginAnswers.isDirectionQuestion(q), "\(q)")
        }
        for q in ["which way is north from here?", "where is north right now", "find north", "onde fica o norte daqui?", "where's the north."] {
            #expect(PluginAnswers.isDirectionQuestion(q), "\(q)")
        }
    }

    @Test func aShowAnEclipseOrAHolidayIsNotTheMoonNow() {
        for q in ["what time does Moon Knight air today", "is there a lunar eclipse tonight", "Sailor Moon episodes today",
                  "when is the lunar new year this month", "lua de mel hoje"] {
            #expect(!PluginAnswers.isMoonQuestion(q), "\(q)")
        }
        for q in ["Moon phase today", "lunar phase today", "what's the moon like tonight?"] { #expect(PluginAnswers.isMoonQuestion(q), "\(q)") }
    }

    @Test func adviceAboutAPhoneGoesToTheModel() {
        for q in ["how do I charge this phone faster", "what battery should I buy for my phone", "how does the device driver manage memory",
                  "how can I make my battery last longer", "como faço meu celular esquentar menos?"] {
            #expect(!PluginAnswers.isPhoneQuestion(q), "\(q)")
        }
        for q in ["is my phone charging?", "how much battery does my phone have", "is this phone too hot?"] { #expect(PluginAnswers.isPhoneQuestion(q), "\(q)") }
    }

    @Test func theTurnIsToTheDirectionAskedAndADatedMoonGoesToTheModel() {
        #expect(PluginAnswers.directionAnswer("which way is east?", heading: 0, tiltDeg: 0).contains("East is 90° to your right"))
        #expect(PluginAnswers.directionAnswer("which way is west?", heading: 0, tiltDeg: 0).contains("West is 90° to your left"))
        #expect(PluginAnswers.directionAnswer("onde fica o sul?", heading: 90, tiltDeg: 0).contains("O sul fica a 90° à direita"))
        #expect(PluginAnswers.directionAnswer("which direction am I facing", heading: 90, tiltDeg: 0).contains("North is 90° to your left"))
        for q in ["what was the moon phase on July 20 1969", "what phase was the moon last night", "qual era a fase da lua ontem"] {
            #expect(!PluginAnswers.isMoonQuestion(q), "\(q)")
        }
    }

    // MARK: iOS

    @Test func theDeviceIsNamedAndAnIPhoneCountsAsThePhone() {
        let iphone = PluginAnswers.Device(en: "iPhone", pt: "iPhone")
        #expect(PluginAnswers.directionAnswer("which way is north?", heading: nil, tiltDeg: nil, device: iphone).hasPrefix("This iPhone has no compass"))
        #expect(PluginAnswers.directionAnswer("onde fica o norte?", heading: 0, tiltDeg: 40, device: iphone).contains("Segure o iPhone deitado"))
        for q in ["how hot is my iPhone?", "what's my iPhone's battery", "qual a temperatura do meu iPhone?"] { #expect(PluginAnswers.isPhoneQuestion(q), "\(q)") }
        #expect(!PluginAnswers.isPhoneQuestion("who designed the iPhone"))
        let a = PluginAnswers.phoneAnswer("how hot is my iPhone?", .init(batteryPct: 60, charging: false, batteryTempC: nil, ramFreeMb: 2048, ramTotalMb: 6144, cores: 6, heatLevel: 1), device: iphone)
        #expect(a == "Battery at 60%; heat level warm; 2.0 GB of 6.0 GB memory free; 6 processor cores. Read on this iPhone just now; Vitals shows more.", "\(a)")
        let none = PluginAnswers.phoneAnswer("qual a temperatura do meu iPhone?", .init(batteryPct: nil, charging: nil, batteryTempC: nil, ramFreeMb: nil, ramTotalMb: nil, cores: nil), device: iphone)
        #expect(none == "O Vitals não conseguiu ler o iPhone agora.")
    }

    @Test func vitalsHeatBands() {
        #expect(VitalsHeat.of(nil) == .unknown)
        #expect(VitalsHeat.of(37.9) == .cool)
        #expect(VitalsHeat.of(38) == .warm)
        #expect(VitalsHeat.of(42) == .hot)
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool { s.range(of: pattern, options: .regularExpression) != nil }
}
