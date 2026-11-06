import Foundation
import Testing

@testable import BoarRouting

/// android ArithmeticTest.kt (r4to's src/routing/arithmetic.test.ts), case for case.
struct ArithmeticTests {
    private func close(_ want: Double, _ got: Double?, _ digits: Int, _ label: String) {
        guard let got else {
            Issue.record("no answer: \(label)")
            return
        }
        #expect(abs(want - got) <= 0.5 * pow(10, -Double(digits)), "\(label)")
    }

    @Test func vitSci003PromptThenAnswerPairedByPhaseWords() {
        let r = Arithmetic.answer(
            "My phone generates 10 tokens per second and processes the prompt at 30 tokens per second. With 1,300 tokens of sources and a 400-token answer, how long until the answer is finished?"
        )
        #expect(r?.kind == "rate-time")
        close(83.33, r?.value, 2, "value")
        #expect(r?.text == "About 83.3 seconds (1 min 23 s) in total: 1,300 tokens ÷ 30 tokens per second ≈ 43.3 seconds, plus 400 tokens ÷ 10 tokens per second = 40 seconds. Computed from the numbers in your question.")
    }

    @Test func rateTimesQuantityToTime() {
        let cases: [(String, Double)] = [
            ("copying 12,000 MB to an external drive at 40 MB per second, how long will it take?", 300),
            ("I need to read 300 pages and I do about 30 pages an hour. how long is that in total?", 36000),
            ("filling a 200-litre tank at 8 litres per minute, how long until it's full", 1500),
            ("If I cycle 36 km at 12 km/h, how long is the ride?", 10800),
            ("prompt is 1500 tokens, prefill speed 50 tok/s, answer is 400 tokens generated at 8 tok/s. how many seconds from send to finished answer?", 80),
            ("downloading a 600 MB update at 20 MB/s and then installing 1,200 MB of files at 40 MB/s. total time in seconds?", 60),
            ("scanner does 20 pages per minute and I have 60 pages, then the printer prints those 60 pages at 12 pages per minute. how long for the whole job", 480),
            ("How long does it take to type 2,400 words at 60 wpm?", 2400),
            ("A 2,000 token prompt is read at 100 tokens per second; then a 300 token answer is written at 10 tokens per second. How long in total?", 50),
            ("how long to drive 240 miles at 60 mph", 14400),
        ]
        for (q, s) in cases { close(s, Arithmetic.answer(q)?.value, 3, q) }
    }

    @Test func ceilDivision() {
        let cases: [(String, Double)] = [
            ("I have 23 L of water and 5 L jerrycans. how many jerrycans do I need?", 5),
            ("1,000 photos, 150 per album, how many albums do i need", 7),
            ("I want to stake 10,000 ETH and each validator holds a max of 32 ETH. how many validators?", 313),
            ("47 people, vans seat 12. how many vans must we book?", 4),
            ("100 eggs and cartons hold 12 each, how many cartons do I need to buy", 9),
            ("250 kg of sand, bags take 20 kg max. how many bags?", 13),
            ("need to move 85 chairs, the truck carries 8 per trip. how many trips", 11),
            ("We have 96 ETH to stake with a 32 ETH cap per validator, how many validators do we need?", 3),
            ("17 litres of juice into 2 litre bottles, how many bottles", 9),
            ("2,000 attendees and each bus holds 150, how many buses to hire", 14),
            ("We need 130 GB of backups, and the USB sticks hold 32 GB each, how many sticks?", 5),
        ]
        for (q, n) in cases { #expect(Arithmetic.answer(q)?.value == n, "\(q)") }
    }

    @Test func statesTheRemainder() {
        #expect(Arithmetic.answer("I have 23 L of water and 5 L jerrycans. how many jerrycans do I need?")?.text
            == "5 jerrycans: 23 ÷ 5 = 4.6, rounded up. 4 full ones hold 20 L; the remaining 3 L needs one more.")
    }

    @Test func neverOnHealthDangerOrQuestionsThatOnlyMentionNumbers() {
        for q in [
            "my heart rate is 130 beats per minute while resting, is that bad?",
            "IV drip at 125 ml per hour for my dad, is that normal?",
            "dose of ibuprofen 400 mg every 6 hours, how many can i take per day max?",
            "my wife is in labor with contractions every 5 minutes lasting 60 seconds, should we go to the hospital",
            "we're trapped in the basement, water rising 10 cm per minute and the ceiling is 200 cm up, how long do we have?",
            "the speed limit is 50 km/h, what's the typical fine for going 70?",
            "why does 4 tokens per second feel slow for an llm, what makes tokens per second higher",
            "I want to stake 10,000 ETH. How many validators did I need before EIP-7251, and what is the minimum after it?",
            "How many people died in the 2004 tsunami?",
            "is 12 pages per minute a good speed for a home laser printer?",
        ] {
            #expect(Arithmetic.answer(q) == nil, "\(q)")
        }
    }
}
