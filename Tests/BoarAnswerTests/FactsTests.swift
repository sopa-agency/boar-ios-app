import Foundation
import Testing

@testable import BoarAnswer

/// android FactsTest.kt (r4to's src/rag/facts.test.ts), case for case. The table is the one the Boar Facts lab ships
/// (App/Resources/Data, copied from android labs/plugins/facts/res/raw).
struct FactsTests {
    static let facts: Facts = {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try! Facts(json: Data(contentsOf: root.appending(path: "App/Resources/Data/lab_facts_facts_v1.json")))
    }()

    private var facts: Facts { Self.facts }

    private func text(_ q: String) -> String? { facts.answer(q)?.text }

    private func matches(_ pattern: String, _ q: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard let t = text(q) else {
            Issue.record("no answer: \(q)", sourceLocation: sourceLocation)
            return
        }
        let re = try! NSRegularExpression(pattern: pattern)
        #expect(re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) != nil, "\(q) -> \(t)", sourceLocation: sourceLocation)
    }

    private func none(_ q: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(facts.answer(q) == nil, "\(q) -> \(text(q) ?? "")", sourceLocation: sourceLocation)
    }

    // ---- the step-1 target items (bench v0.1, dev) ----

    @Test func lanCmp001TwoCountryPopulationComparisonGivesAComputedYesNoVerdict() { // lan-cmp-001, two-country population comparison gives a computed yes-no verdict
        let a = facts.answer("Does Brazil have more people than Russia?")
        #expect(a?.template == "population")
        matches(#"^Yes\. Brazil has more people than Russia: Brazil 21\d\.\d million \(20\d\d\) vs Russia 14\d\.\d million"#, "Does Brazil have more people than Russia?")
        matches(#"^No\. Brazil has more people than Russia"#, "Does Russia have more people than Brazil?")
        matches(#"^Yes\."#, "Does Russia have fewer people than Brazil?")
    }

    @Test func lanRsn002ABuildingSHeightAgainstALakeSDepth() { // lan-rsn-002, a building's height against a lake's depth
        matches(
            #"^No\. Burj Khalifa is 828 m tall; Lake Baikal is 1,642 m deep at its deepest point, so its top would be about 814 m below the surface"#,
            "If you stood the Burj Khalifa on the deepest point of Lake Baikal, would its top stick out of the water?",
        )
    }

    @Test func lanRef001AndLanRef005AwardWinnerByYearHostCity() { // lan-ref-001 and lan-ref-005, award winner by year, host city
        matches(#"2017: Kazuo Ishiguro\."#, "Who received the Nobel Prize in Literature in 2017?")
        none("Who received the Nobel Prize in Literature?") // no year -> no fire
        matches(#"held in Rio de Janeiro"#, "Which city hosted the 2016 Summer Olympics?")
    }

    @Test func lanRef004LanExp006LanRsn007AreaElevationWithTypeAndCountryDates() { // lan-ref-004, lan-exp-006, lan-rsn-007, area, elevation with type and country, dates
        matches(#"^Iceland \(.*\): area 103,004 km²"#, "How big is Iceland in square kilometres?")
        matches(#"Tanzania; type: dormant volcano.*elevation 5,895 m"#, "What is Kilimanjaro, how high is it, and is it a volcano?")
        matches(#"13 August 1961.*9 November 1989"#, "In which year was the Berlin Wall built, and in which year did it come down?")
    }

    @Test func trv002PlugsAndVoltageAreOneTemplate() { // trv-002, plugs and voltage are one template
        matches(#"Type C .*Type N .*127 V / 220 V"#, "What plug type and voltage does Brazil use?")
    }

    @Test func everyAnswerCarriesTheSourceLine() { // every answer carries the source line
        matches(#"The capital of Kenya is Nairobi\.\n\nSource: Wikidata \(CC0\), offline table as of 2026-10-06\."#, "What is the capital of Kenya?")
    }

    // ---- the trigger stays narrow ----

    @Test func noFireOnMultiSlotOverviewsOrExplanationWording() { // no fire on multi-slot overviews or explanation wording
        none("What are the key facts about Montenegro: capital, currency, coastline and how it became independent?")
        none("Give me the essentials on Kenya: its location, capital, official languages and year of independence.")
        none("Give me a quick overview of Singapore: where it is, how it became independent, and what languages people speak there.")
        none("Describe Greenland: who governs it, its capital, roughly how many people live there, and how much of it is covered by ice.")
        none("Tell me about Japan")
        #expect(Facts.templates("What is the capital and currency of Peru?") == ["capital", "currency"])
        none("What is the capital and currency of Peru?")
    }

    @Test func noFireOnUnsupportedSlotsSetQueriesOrAnEntityWithoutTheValue() { // no fire on unsupported slots, set queries or an entity without the value
        none("Which is more densely populated, Japan or Germany, and by how much?")
        none("Which countries are bigger than India by area?")
        none("How long is the Great Wall of China, and can you really see it from the Moon?")
        none("What is the capital of Lake Baikal?")
        none("What is the population of Atlantis?")
    }

    @Test func noFireOnHealthDangerOrNonQuestions() { // no fire on health, danger or non-questions
        none("I'm at 4,000 m in the Andes with a headache and nausea. What should I do?")
        none("Is it safe to go to La Paz with the altitude?")
        none("I love the capital of France")
    }

    @Test func entitiesLongestNameFirstInnerWordsNeverResolveTwiceLoneWordsMustBeCapitalized() { // entities, longest name first, inner words never resolve twice, lone words must be capitalized
        #expect(facts.factEntities("When was the Berlin Wall built?").map(\.n) == ["Berlin Wall"])
        #expect(facts.factEntities("what is the population of turkey?").map(\.n) == [String]()) // r3: risk-list word
        #expect(!facts.factEntities("Which is longer, the Nile or the Amazon River?").isEmpty)
    }

    @Test func comparisonNeedsTwoEntitiesWithTheValueAWhichQuestionGetsTheVerdictWithoutYesNo() { // comparison needs two entities with the value, a which question gets the verdict without yes-no
        matches(#"^Brazil has more people than Russia"#, "Which has more people, Brazil or Russia?")
        matches(#"^No\. Brazil is larger by area than Iceland"#, "Is Iceland bigger than Brazil?") // r3: "bigger than" -> area
    }

    @Test func lookupIsFastWarm() { // lookup is fast (warm)
        _ = facts.answer("How big is Iceland in square kilometres?")
        let clock = ContinuousClock()
        let took = clock.measure { for _ in 0..<200 { _ = facts.answer("Does Brazil have more people than Russia?") } }
        // Android's bound is 5 ms; a debug build of the Swift port gets four times that.
        #expect(took / 200 < .milliseconds(20), "\(took / 200) per answer")
    }

    // ---- r2: data and trigger gates ----

    @Test func r2Gate1NoFoundingYearForCountriesTheBerlinWallKeepsItsDates() { // r2 gate 1, no founding year for countries, the Berlin Wall keeps its dates
        none("When was Italy founded?")
        none("When was the United States founded?")
        matches(#"13 August 1961"#, "In which year was the Berlin Wall built, and in which year did it come down?")
    }

    @Test func r2Gate2PopulationOnlyWhenDated2020OrLater() { // r2 gate 2, population only when dated 2020 or later
        none("What is the population of the Netherlands?") // latest statement 2013
        matches(#"\((dated )?20(2\d)\)"#, "What is the population of Iceland?")
    }

    @Test func r2Gate3NoFormerOrUnbuiltEntitiesNoOutOfRangeValuesNoAnswerForANameWithTwoEntities() { // r2 gate 3, no former or unbuilt entities, no out-of-range values, no answer for a name with two entities
        none("How long is the Bian River?")
        none("How tall is X-Seed 4000?")
        none("How big is Lake Agassiz?")
        none("What is the population of Bandung?") // city and regency share the label
        none("What is the capital of Georgia?") // the US state is not in the table
    }

    @Test func r2Gate4NicknameAliasesRemovedEveryWordOfANameTypedCapitalised() { // r2 gate 4, nickname aliases removed, every word of a name typed capitalised
        none("How tall is the White House?")
        none("How big is Michigan?")
        none("How high is the Cape?")
        none("How long is the Green River?")
        none("How many people live in Garden City?")
        none("How tall is Trump Tower?")
        // r4 rule 1 (kept in r5 rule D): a lowercase multi-word name that names exactly one entity resolves.
        #expect(facts.factEntities("how deep is lake baikal?").map(\.n) == ["Lake Baikal"])
        #expect(facts.factEntities("How deep is Lake Baikal?").map(\.n) == ["Lake Baikal"])
    }

    // ---- r3: trigger recall fixes ----

    @Test func r3Fix1OneWordCountryOrCapitalNamesMayBeTypedLowercaseRiskWordsAndMultiWordNamesMayNot() { // r3 fix 1, one-word country or capital names may be typed lowercase, risk words and multi-word names may not
        matches(#"^Canada \(.*\): population 40 million"#, "what is the population of canada")
        matches(#"Official language of Egypt: Arabic"#, "what is the official language of egypt")
        matches(#"^Peru is in South America"#, "what continent is peru on")
        #expect(facts.factEntities("how big is paris").map(\.n) == ["Paris"])
        for w in ["georgia", "turkey", "chad", "jordan", "china", "america"] { none("what is the population of \(w)") }
        none("how tall is jordan")
        #expect(facts.answer("how long is the amazon river")?.entities == ["Q3783"]) // r4/r5 rule D: one exact label
        none("how tall is kilimanjaro") // a mountain, not a country or capital
        none("what is the population of south sudan") // not Sudan
        matches(#"^Mexico City \("#, "what is the population of mexico city") // r4/r5 rule D; not Mexico
        none("what is the population of new mexico")
    }

    @Test func r3Fix2AliasesChinaUKUSTheAmazon() { // r3 fix 2, aliases China, UK, US, the Amazon
        #expect(facts.factEntities("What is the population of China?").map(\.q) == ["Q148"])
        for q in ["What currency does the UK use?", "what currency does the uk use", "What is the capital of the U.K.?", "How big is Britain?"] {
            #expect(facts.answer(q)?.entities == ["Q145"], "\(q)")
        }
        for q in ["What currency does the US use?", "How big is the U.S.?", "What is the population of the USA?", "How big is America?"] {
            #expect(facts.answer(q)?.entities == ["Q30"], "\(q)")
        }
        none("what is the population of the us") // lowercase "us" is a pronoun
        matches(#"^Nile is longer than Amazon River"#, "Which is longer, the Nile or the Amazon?")
        none("How big is Amazon?") // the company: only "the Amazon" is the river
    }

    @Test func r3Fix3SizeOfHowBigBiggerLargerSmallerThanWhichIsBiggerAskForArea() { // r3 fix 3, size of, how big, bigger, larger, smaller than, which is bigger ask for area
        matches(#"^Brazil \(.*\): area 8,515,767 km²"#, "what's the size of brazil")
        matches(#"^Canada is larger by area than United States: Canada 9,984,670 km² .* vs United States 9,826,675 km²"#, "Which is bigger, Canada or the United States?")
        matches(#"^Yes\. Brazil is larger by area than Iceland"#, "Is Iceland smaller than Brazil?")
        #expect(Facts.templates("Which is larger, Peru or Chile?") == ["area"])
        #expect(Facts.templates("Is Brazil's population larger than Russia's?") == ["population"]) // a named property wins
    }

    @Test func r3Fix4ANameGluedToAnUnknownCapitalisedWordOrACompoundPropertyWordDoesNotFire() { // r3 fix 4, a name glued to an unknown capitalised word, or a compound property word, does not fire
        none("How tall is Paris Hilton?")
        none("When was the Paris Agreement signed?")
        none("How tall is the London Eye?")
        none("How tall is Michael Jordan?")
        none("How big is South America?")
        // r6: Lake Chad is a table lake; the glued name answers for the lake, never the country Chad.
        #expect(facts.answer("How big is Lake Chad?")?.entities == ["Q125309"])
        none("What is the area code for London?")
        #expect(Facts.templates("What is your area of expertise?") == [String]())
        matches(#"^France \(.*\): population"#, "What Is The Population Of France?") // title case still fires
        matches(#"^Danube \(.*\): length 2,850 km"#, "How long is the Danube River?") // feature word of the same kind
    }

    @Test func r3Fix5APopulationDatedBefore2023PrintsDatedYEAR2023AndLaterPrintsYEAR() { // r3 fix 5, a population dated before 2023 prints (dated YEAR), 2023 and later prints (YEAR)
        matches(#"population 211\.4 million \(dated 2021\)\."#, "How many people live in Nigeria?")
        matches(#"population 40 million \(2023\)\."#, "What is the population of Canada?")
    }

    // ---- r5: two-sided neighbour guard, question openers, whole-label override ----

    @Test func r5RuleAALowercaseContentWordOnEitherSideOfANameNoFire() { // r5 rule A, a lowercase content word on either side of a name, no fire
        for q in [
            "how tall is paris hilton", "how tall is a mont blanc pen", "how big is a cuba libre", "how big is a london broil",
            "how tall is mount everest base camp", "how tall is the paris las vegas eiffel tower", "how high is the mexico city metro fare",
            "how long is the rio grande valley", "how tall is the berlin wall memorial", "what language is the japan times written in",
            "how many people live in jersey city", "what is the population of new england",
        ] { none(q) }
    }

    @Test func r5RuleAQuestionPropertyHedgeUnitAndComparisonWordsAndAnotherResolvedNameAreAllowedNeighbours() { // r5 rule A, question, property, hedge, unit and comparison words, and another resolved name, are allowed neighbours
        #expect(facts.answer("how tall is mount everest")?.entities == ["Q513"])
        matches(#"^Mount Everest \("#, "how tall is mount everest in feet")
        matches(#"^Kuala Lumpur Tower \(.*\): height 421 m"#, "how tall is the kuala lumpur tower") // the whole label
        matches(#"^Canada \(.*\): population 40 million"#, "roughly how many people live in canada today?")
        matches(#"^The capital of Ethiopia is Addis Ababa"#, "What's the capital city of Ethiopia?") // "capital city"
        matches(#"^Yes\. Chad is larger by area than Jordan"#, "Is Chad bigger than Jordan by area?")
        matches(#"^Danube \("#, "how long is the danube river") // r3 feature-word exception, any casing
    }

    @Test func r5RuleAACapitalisedContentWordIsCheckedTooOnBothSidesAndAcrossPunctuation() { // r5 rule A, a capitalised content word is checked too, on both sides and across punctuation
        none("How tall is Paris Hilton?")
        none("Which language is spoken in Swiss schools?")
        none("What is the population of Paris, the city of light?") // "city" is not part of the label
        none("How big is Greater London?")
    }

    @Test func r5RuleBWhatsHowsWheresAndSizeCapitalPopulationOfAreQuestionsWithoutAQuestionMark() { // r5 rule B, whats, hows, wheres and size, capital, population of are questions without a question mark
        matches(#"^The capital of Philippines is Manila"#, "whats the capital of the philippines")
        matches(#"Wellington"#, "capital of new zealand")
        matches(#"^Japan \(.*\): population"#, "population of japan")
        none("the capital of japan") // no opener, no "?"
    }

    @Test func r5RuleCAWholeMultiWordLabelResolvesEvenWithARiskListWordALoneRiskWordStillDoesNot() { // r5 rule C, a whole multi-word label resolves even with a risk-list word, a lone risk word still does not
        matches(#"^Lake Victoria \(.*\): area 68,100 km²"#, "how big is lake victoria")
        none("how big is victoria")
        none("what is the population of georgia")
    }

    @Test func r5RuleDR4KeptSafeLowercaseMultiWordNamesTypoTolerantThe() { // r5 rule D (r4 kept), safe lowercase multi-word names, typo-tolerant the
        matches(#"^Mont Blanc \(.*\): elevation 4,806 m"#, "how high is mont blanc")
        #expect(facts.answer("how high are the petronas towers") != nil)
        matches(#"is Amsterdam"#, "what is the capital of thw Netherlands?")
    }

    // ---- r6: five trigger fixes ----

    @Test func r6Fix1OpenerTyposWhtaWahtWatHwoWhats() { // r6 fix 1, opener typos whta, waht, wat, hwo, whats'
        matches(#"^The capital of Chile is Santiago"#, "waht is the capital of Chile")
        none("waht is the capital of chile") // lowercase "chile" stays on the r3 risk list
        matches(#"^Canada \(.*\): population"#, "whta is the population of Canada?")
        matches(#"^France \(.*\): area 643,801 km²"#, "wat is the area of france")
        matches(#"^Burj Khalifa \(.*\): height 828 m"#, "hwo tall is the burj khalifa")
        matches(#"^The capital of Peru is Lima"#, "whats' the capital of peru")
        none("Wat Arun is a temple") // only the opening word of a question frame
    }

    @Test func r6Fix2OfficialLanguageSOfXAndContinentOfXWithoutWhatOrAQuestionMark() { // r6 fix 2, official language(s) of X and continent of X without what or a question mark
        matches(#"^Official languages of Brazil: .*Portuguese"#, "official language of brazil")
        matches(#"French, German, Italian and Romansh"#, "official languages of switzerland")
        matches(#"^Kenya is in Africa\."#, "continent of kenya")
        none("language of brazil") // not one of the listed openers
    }

    @Test func r6Fix3WhatOrWhichContinentIsAPlaceInOrOnGivesItsOneCountrySContinent() { // r6 fix 3, what or which continent is a place in or on gives its one country's continent
        matches(#"^Addis Ababa is in Ethiopia, which is in Africa\."#, "which continent is Addis Ababa in?")
        matches(#"^Nairobi is in Kenya, which is in Africa\."#, "what continent is nairobi on")
        none("What continent is Paris on?") // France spans several continents (overseas regions)
    }

    @Test func r6Fix4WhatCountryOrCountriesSurroundXAsksForBorders() { // r6 fix 4, what country or countries surround X asks for borders
        matches(#"^Iran borders Afghanistan, .*Turkmenistan"#, "what countries surround iran?")
        matches(#"^Lesotho borders South Africa\."#, "What country surrounds Lesotho")
    }

    @Test func r6Fix5WhichIsTallerOrHigherTwoMountainsOrTwoStructuresAnyCasing() { // r6 fix 5, which is taller or higher, two mountains or two structures, any casing
        matches(#"^Aconcagua is taller than Mount Kilimanjaro: Aconcagua 6,962 m"#, "which is higher, aconcagua or kilimanjaro")
        matches(#"^No\. K2 is taller than Aconcagua"#, "is aconcagua higher than k2?")
        matches(#"^No\. CN Tower is taller than Eiffel Tower"#, "is the eiffel tower taller than the cn tower?")
        matches(#"^Empire State Building is taller than Chrysler Building"#, "which is taller, the empire state building or the chrysler building?")
        none("which is higher, aconcagua or the burj khalifa") // a mountain and a building
        none("which is taller, everest base camp or k2") // a side that is not one whole name
        none("Which is taller, K2 or Everest?") // "Everest" alone is not a label or alias
    }

    // ---- r9: travel fields (driving side, calling code, mains frequency), 2026-10-19 ----

    @Test func r9AnswersPlugAndVoltageQuestionsInTravelWordingWithTheMainsFrequency() { // r9 answers plug and voltage questions in travel wording, with the mains frequency
        matches(#"^Japan: plug types Type A \(NEMA 1-15\) and Type B \(NEMA 5-15\), mains voltage 100 V, 50 Hz / 60 Hz\. Where two values are listed"#, "What plug do I need in Japan?")
        matches(#"^India: .*mains voltage 230 V, 50 Hz\.\n"#, "voltage in India")
        matches(#"Type I \(AS/NZS 3112\), mains voltage 230 V, 50 Hz"#, "Do I need a plug adapter for Australia?")
        matches(#"mains voltage 120 V, 60 Hz\."#, "What voltage is used in the United States?")
        matches(#"mains voltage 230 V, 50 Hz\.\n"#, "What is the voltage in Indonesia?") // obsolete 127 V dropped
        #expect(text("What plug type is used in Afghanistan?").map { !$0.contains("British") } == true) // umbrella item dropped
    }

    @Test func r9AnswersTheDrivingSideWithYesOrNoWhenTheQuestionNamesOneSide() { // r9 answers the driving side, with Yes or No when the question names one side
        matches(#"^Yes\. In Japan, traffic drives on the left\."#, "Do they drive on the left in Japan?")
        matches(#"^No\. In Ireland, traffic drives on the left\."#, "Do they drive on the right in Ireland?")
        matches(#"^In Sweden, traffic drives on the right\."#, "Which side of the road do they drive on in Sweden?")
        matches(#"^In Samoa, traffic drives on the left\."#, "Do they drive on the left or the right in Samoa?")
        matches(#"drives on the right"#, "driving side in Argentina")
    }

    @Test func r9AnswersTheInternationalCallingCode() { // r9 answers the international calling code
        matches(#"^The international calling code for Brazil is \+55\."#, "What is the country code for Brazil?")
        matches(#"is \+91\."#, "country code for India")
        matches(#"\+1 876 \(country code \+1, then area code 876\)"#, "What's the calling code for Jamaica?")
        matches(#"Denmark \+45, Faroe Islands \+298 and Greenland \+299"#, "What is the dialling code for Denmark?")
        matches(#"is \+90\."#, "What is the country code for Turkey?") // ended +36 dropped
        none("What is the country code for Vatican City?") // +379 unused: the model answers
    }

    @Test func r9StaysOutOfOtherDrivingAndCodeQuestions() { // r9 stays out of other driving and code questions
        none("Can I drive in Japan with a US license?")
        none("Do I need an international driving permit for Italy?")
        none("Is it safe to drive in Mexico?")
        none("How do I drive to Paris?")
        none("Which side of the road should I walk on in Japan?")
        none("What is the ISO country code for France?")
        none("What is the internet country code for Germany?")
        none("What is the area code for London?")
        none("What is the country code for Tokyo?") // a city has no calling code in the table
        none("What time zone is Japan in?")
        #expect(facts.answer("What is the capital of Japan?")?.template == "capital")
        #expect(facts.answer("What is the emergency number in Thailand?")?.template == "emergency")
    }

    // ---- r8: emergency numbers, 2026-10-19 ----

    @Test func r8AnswersACountrySEmergencyNumbersWithTheirService() { // r8 answers a country's emergency numbers with their service
        matches(#"^Emergency numbers in Thailand: police 191, fire department 199 and emergency medical services 1669\."#, "What is the emergency number in Thailand?")
        matches(#"police 110"#, "What is the police number in Japan?")
        none("Is there an emergency exit in the Burj Khalifa?")
    }

}
