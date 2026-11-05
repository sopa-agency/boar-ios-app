import Foundation
import Testing

@testable import BoarRouting

/// android LanguageGateTest.kt, case for case. Boar Polyglot's gate: what must pass to the model as today (English,
/// Portuguese, Spanish, short phrases, thanks, names, quotes, code, translation requests, follow-ups) and what gets the
/// instant "BOAR doesn't speak X yet" reply (full sentences in other languages: by script, or by the device's detector
/// for Latin text).
struct LanguageGateTests {
    typealias Decision = LanguageGate.Decision

    /// A sure detector result for `code`, as a detector gives it for a clear sentence.
    private func sure(_ code: String) -> LanguageGate.Guesses { [(code, 0.97), ("en", 0.02)] }

    private let pass: [String] = [
        // thanks, greetings, yes/no, in any language
        "ok", "okay", "OK!", "thanks", "Thanks!", "thank you", "obrigado", "obrigada", "merci", "merci beaucoup", "danke schön",
        "Danke", "gracias", "muchas gracias", "grazie mille", "спасибо", "спасибо большое", "谢谢", "ありがとう",
        "ありがとうございます", "감사합니다", "شكرا", "תודה רבה", "धन्यवाद", "ขอบคุณครับ", "ευχαριστώ πολύ", "yes", "no", "hi",
        "olá", "oi", "hola", "bonjour", "ciao", "привет", "你好", "こんにちは", "안녕하세요", "oui", "ja", "nein", "Teşekkürler",
        "terima kasih", "dziękuję", "Bonjour, merci beaucoup mon ami",
        // nothing to measure: emoji, numbers, links, code, punctuation
        "😀😀😀", "👍", "🙏🙏 🙏 🙏", "12345", "3.14159 + 2.71828 = 5.85987", "https://example.com/some/long/path?x=1",
        "contact me at someone@example.org", "`SELECT * FROM users WHERE id = 1;`",
        "```\nfn main() { println!(\"hola mundo\"); }\n```", "const x = { a: 1, b: 2 };", "???", "...", "",
        // names and places
        "Zürich?", "São Paulo", "Москва?", "東京", "Dostoevsky", "Kraków Wrocław Gdańsk Poznań",
        // English and Portuguese with foreign names and quotes
        "What is the capital of Switzerland, Zürich or Bern?", "How far is São Paulo from Rio de Janeiro?",
        "What does 'je ne sais quoi' mean?", "What does «Schadenfreude ist die schönste Freude» mean in English?",
        "Who wrote „Die Leiden des jungen Werthers“?", "Where is Ногинск located?", "Is 東京タワー taller than the Eiffel Tower?",
        "O que significa \"Ich bin ein Berliner\"?", "Quem escreveu \"Война и мир\"?", "Como se diz 'obrigado' em japonês?",
        "Qual é a capital da Alemanha?", "Onde fica Kraków?", "Por que o céu é azul?",
        "Translate 'danke schön' to English", "translate this to French: where is the train station",
        "Traduza para o português: Je voudrais un café s'il vous plaît", "traduz isso: Wo ist der Bahnhof bitte",
        "How do you say я люблю тебя in English?", "What's the difference between こんにちは and こんばんは?",
        "Can you explain what 你好吗 means?", "Is it true that Здравствуйте is hard to pronounce?",
        "I want to learn Polish. Jak się masz is my first phrase, what does it mean?",
        // plain English and Portuguese
        "What should I pack for a three day hike in the mountains?", "How do I purify water without a filter?",
        "Como faço para purificar água sem filtro?", "Quais são os sintomas de desidratação?",
        "Você pode me ajudar a planejar uma viagem?",
        // Spanish, allowed for now (with inverted marks or three Spanish-only words, whatever the detector says)
        "¿Dónde está la estación de tren más cercana?", "¿Cuánto tiempo hay que hervir el agua?",
        "Mi hijo tiene fiebre, qué puedo hacer", "Es muy peligroso hacer fuego aquí",
        // three-word foreign phrases
        "c'est la vie", "wie geht's dir", "come stai oggi", "hoe gaat het", "jak się masz", "что это такое", "这是什么",
    ]

    @Test func passesWithASureDetector() {
        // Even a detector sure it's French doesn't block these: each is short, quoted, a thanks, a name or has English/Portuguese in it.
        let failures = pass.filter { LanguageGate.decide($0, sure("fr")) != .allowed }
        #expect(failures.isEmpty, "blocked: \(failures)")
    }

    @Test func passesWithoutADetector() {
        let failures = pass.filter { LanguageGate.decide($0, nil) != .allowed }
        #expect(failures.isEmpty, "blocked: \(failures)")
    }

    /// No function word to go on: the detector names an allowed language.
    private let allowedByDetector: [(String, String)] = [
        ("es", "Necesito ayuda para planear un viaje a la montaña"),
        ("es", "Quiero saber cuánto tiempo tarda en hervir el agua"),
        ("es", "Cuál es la mejor manera de hervir agua en el campo"),
        ("en", "Explain photosynthesis in simple terms"),
        ("en", "Tell me something interesting about volcanoes today"),
        ("en", "Give me five tips for staying warm overnight"),
        ("pt", "Preciso saber quanto tempo dura uma bateria"),
        ("pt", "Me explica fotossíntese em palavras simples"),
    ]

    @Test func allowedLanguagesPassWhenDetected() {
        for (code, q) in allowedByDetector { #expect(LanguageGate.decide(q, sure(code)) == .allowed, "\(q)") }
        #expect(LanguageGate.allowed.contains("es"))
        #expect(pass.count + allowedByDetector.count >= 80)
    }

    struct NoClassifier: Error {}

    @Test func unsureDetectorPasses() {
        let q = "Je voudrais savoir quel temps il fera demain"
        #expect(LanguageGate.decide(q, [("fr", 0.85), ("it", 0.05)]) == .allowed)
        #expect(LanguageGate.decide(q, [("fr", 0.91), ("ca", 0.70)]) == .allowed)
        #expect(LanguageGate.decide(q, []) == .allowed)
        #expect(LanguageGate.decide(q, [("und", 0.99)]) == .allowed)
        #expect(LanguageGate.decide(q, followUp: false) { _ in throw NoClassifier() } == .allowed)
    }

    @Test func followUpsPass() {
        let shortOnes = ["Und auf Deutsch bitte, danke sehr", "Et en français s'il vous plaît", "А на русском языке можно?", "用中文回答可以吗"]
        for q in shortOnes { #expect(LanguageGate.decide(q, sure("de"), followUp: true) == .allowed, "\(q)") }
        // A full question isn't a follow-up however the chat went.
        let long = "Почему небо голубое а трава зелёная летом"
        #expect(LanguageGate.decide(long, nil, followUp: true) == .unsupported("ru"))
    }

    /// Latin script: blocked only on a sure detector result.
    private let latin: [(String, String)] = [
        ("fr", "Quelle est la meilleure façon de purifier l'eau en randonnée ?"),
        ("fr", "Je voudrais savoir combien de temps il faut pour faire bouillir de l'eau"),
        ("fr", "Est-ce que je peux boire l'eau de la rivière sans la filtrer ?"),
        ("de", "Wie lange dauert es, bis das Wasser kocht?"),
        ("de", "Ich möchte wissen, wie man ohne Kompass nach Norden findet"),
        ("de", "Was soll ich für eine dreitägige Wanderung einpacken?"),
        ("it", "Quale sarebbe il modo migliore per purificare l'acqua durante un'escursione?"),
        ("it", "Quanto tempo ci vuole per far bollire l'acqua in montagna?"),
        ("it", "Vorrei sapere come accendere un fuoco senza fiammiferi"),
        ("nl", "Hoe lang duurt het voordat het water kookt?"),
        ("nl", "Wat is de beste manier om water te zuiveren tijdens een wandeling?"),
        ("pl", "Jak długo trzeba gotować wodę, żeby była bezpieczna?"),
        ("pl", "Jak dojechać do dworca kolejowego najszybciej?"),
        ("tr", "Suyu kaynatmak ne kadar sürer ve güvenli mi?"),
        ("tr", "Kamp yaparken ateş nasıl yakılır bana anlatır mısın?"),
        ("id", "Berapa lama waktu yang dibutuhkan untuk merebus air?"),
        ("id", "Bagaimana cara menyaring air sungai agar aman diminum?"),
        ("sv", "Hur länge ska man koka vattnet innan man dricker det?"),
        ("vi", "Làm thế nào để lọc nước sông cho an toàn khi uống?"),
        ("fi", "Kuinka kauan vettä pitää keittää ennen juomista?"),
    ]

    /// Other scripts: blocked by their letters, no detector needed.
    private let scripts: [(String, String)] = [
        ("ru", "Как долго нужно кипятить воду, чтобы она была безопасной?"),
        ("ru", "Что взять с собой в поход на три дня в горы?"),
        ("ru", "Почему небо голубое а трава зелёная летом"),
        ("uk", "Як довго потрібно кип'ятити воду, щоб вона була безпечною?"),
        ("uk", "Що взяти з собою в похід на три дні?"),
        ("zh", "烧水需要多长时间才能安全饮用？"),
        ("zh", "在山里徒步三天应该带些什么东西"),
        ("ja", "水を安全に飲むためにはどのくらい沸騰させればいいですか？"),
        ("ja", "三日間の山歩きに何を持っていけばいいですか"),
        ("ko", "물을 안전하게 마시려면 얼마나 끓여야 하나요?"),
        ("ko", "삼일 동안 산행할 때 무엇을 챙겨야 하나요?"),
        ("ar", "كم من الوقت يجب أن أغلي الماء حتى يصبح آمنا للشرب؟"),
        ("ar", "ماذا يجب أن أحمل معي في رحلة تخييم لمدة ثلاثة أيام"),
        ("he", "כמה זמן צריך להרתיח מים כדי שיהיו בטוחים לשתייה?"),
        ("he", "מה כדאי לקחת לטיול של שלושה ימים בהרים"),
        ("hi", "पानी को सुरक्षित पीने के लिए कितनी देर उबालना चाहिए?"),
        ("hi", "तीन दिन की पहाड़ी यात्रा के लिए क्या ले जाना चाहिए"),
        ("th", "ต้องต้มน้ำนานเท่าไรถึงจะปลอดภัยสำหรับดื่ม"),
        ("th", "ไปเดินป่าสามวันควรเตรียมอะไรไปบ้าง"),
        ("el", "Πόση ώρα πρέπει να βράσω το νερό για να είναι ασφαλές;"),
        ("el", "Τι πρέπει να πάρω μαζί μου για πεζοπορία τριών ημερών"),
        ("ka", "რამდენ ხანს უნდა ვადუღო წყალი რომ უსაფრთხო იყოს"),
        ("hy", "Որքան ժամանակ պետք է եռացնել ջուրը որ այն անվտանգ լինի"),
        ("bn", "পানি নিরাপদে পান করার জন্য কতক্ষণ ফোটাতে হবে"),
    ]

    @Test func blocksLatinScriptWithASureDetector() {
        for (code, q) in latin { #expect(LanguageGate.decide(q, sure(code)) == .unsupported(code), "\(q)") }
    }

    @Test func blocksOtherScriptsWithoutADetector() {
        for (code, q) in scripts { #expect(LanguageGate.decide(q, nil) == .unsupported(code), "\(q)") }
        #expect(latin.count + scripts.count >= 40)
    }

    @Test func cyrillicPrefersTheDetector() {
        let q = "Колко време трябва да се вари водата за да е безопасна"
        #expect(LanguageGate.decide(q, nil) == .unsupported("ru"))
        #expect(LanguageGate.decide(q, [("bg", 0.93), ("ru", 0.05)]) == .unsupported("bg"))
        // A detector naming a language of another script is ignored.
        #expect(LanguageGate.decide(q, [("en", 0.99)]) == .unsupported("ru"))
    }

    @Test func latinPassesWithoutADetector() {
        for (_, q) in latin { #expect(LanguageGate.decide(q, nil) == .allowed, "\(q)") }
    }

    @Test func detectorCodesAreNormalized() {
        #expect(LanguageGate.decide("כמה זמן צריך להרתיח מים כדי שיהיו בטוחים", [("iw", 0.99)]) == .unsupported("he"))
        #expect(LanguageGate.decide("Berapa lama waktu yang dibutuhkan untuk merebus air?", [("in-ID", 0.98)]) == .unsupported("id"))
    }

    @Test func detectorOnlyCalledWhenNeeded() {
        var calls = 0
        _ = LanguageGate.decide("What should I pack for a hike?", followUp: false) { _ in calls += 1; return nil }
        _ = LanguageGate.decide("merci", followUp: false) { _ in calls += 1; return nil }
        _ = LanguageGate.decide("Как долго нужно кипятить воду?", followUp: false) { _ in calls += 1; return nil }
        #expect(calls == 1) // only the Cyrillic one asks (ru/uk/bg)
    }

    /// SplitMix64: a fixed sequence for the fuzz (Kotlin uses java.util.Random(20261018)).
    struct Rng {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int((z ^ (z >> 31)) % UInt64(bound))
        }
    }

    @Test func fuzzNeverThrowsAndIsFast() {
        var rnd = Rng(state: 20_261_018)
        // Kotlin's pool also has lone surrogates (\uD83D, \uDBFF); a Swift String can't hold one.
        let pools: [[UInt16]] = [
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ  .,;:!?'\"«»„“”‘’`{}()[]@/#0123456789\n\t-_",
            "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЖЗ ",
            "的一是不了人我在有他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可她里后小么心多天而能好都然没日于起还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三已老从动两长",
            "あいうえおかきくけこアイウエオカキクケコ가나다라마바사아자차카타파하 ",
            "ابتثجحخدذرسشصضطظعغفقكلمنهوي אבגדהוזחטיכלמנסעפצקרשת ",
            "αβγδεζηθικλμνξοπρστυφχψω अआइईउऊएऐओऔकखगघङ กขคงจฉชซฌญ ",
            "😀🙏👍🔥\u{FE0F}\u{301}\u{300}𐀀",
        ].map { Array($0.utf16) }
        func random(_ len: Int) -> String {
            var sb: [UInt16] = []
            let pool = pools[rnd.next(pools.count)]
            for _ in 0..<len {
                if rnd.next(10) == 0 {
                    let p = pools[rnd.next(pools.count)]
                    sb.append(p[rnd.next(p.count)])
                } else {
                    sb.append(pool[rnd.next(pool.count)])
                }
            }
            return String(decoding: sb, as: UTF16.self)
        }
        let detectors: [LanguageGate.Guesses?] = [nil, [], sure("fr"), [("", 1)], [("zh-Hant-TW", 0.99)], [("xx", .nan)]]
        for i in 0..<2_000 { _ = LanguageGate.decide(random(rnd.next(300)), detectors[i % detectors.count], followUp: i % 7 == 0) }
        // Warm up, then time 2,000-character inputs.
        let long = (0..<50).map { _ in random(2_000) }
        for s in long { _ = LanguageGate.decide(s, sure("fr")) }
        let clock = ContinuousClock()
        var worst = Duration.zero
        for s in long {
            let d = clock.measure { _ = LanguageGate.decide(s, sure("fr")) }
            worst = max(worst, d)
        }
        #expect(worst < .milliseconds(5), "worst \(worst)")
        // Adversarial: unmatched quotes and backticks everywhere.
        for s in [String(repeating: "«", count: 2_000), String(repeating: "'a", count: 1_000), String(repeating: "`", count: 2_001),
                  String(repeating: "\"x ", count: 700), String(repeating: "{;", count: 1_000), String(repeating: "Ab ", count: 700)] {
            let d = clock.measure { _ = LanguageGate.decide(s, sure("fr")) }
            #expect(d < .milliseconds(20), "slow on \(s.prefix(6))")
        }
    }
}
