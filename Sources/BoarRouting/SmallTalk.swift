import Foundation

/// Small talk answered without the model (port of src/routing/smallTalk.ts): a greeting, thanks, "who are you", the
/// time. These never get better from the library, and on a phone a cold model load plus generation is seconds for
/// "hi". Deterministic: same message, same reply. Anything else (a joke, a real question after "hi,") returns nil.
public enum SmallTalk {
    /// kind: "greeting" | "about" | "time" | "date"
    public struct Reply: Sendable, Equatable {
        public var text: String
        public var kind: String
        public init(text: String, kind: String) {
            self.text = text
            self.kind = kind
        }
    }

    private static let punct = JsRegex(#"[!.?~,;]+"#)
    private static let spaces = JsRegex("\(JsString.ws)+")
    private static let combining = JsRegex(#"[̀-ͯ]"#)

    private static func norm(_ s: String) -> String {
        JsString.trim(spaces.replace(in: punct.replace(in: combining.replace(in: JsString.nfd(JsString.trim(s).lowercased()), with: ""), with: " "), with: " "))
    }

    private enum Kind { case hello, morning, afternoon, evening, night, howAreYou, thanks, bye, ok }

    private static let phrases: [(Kind, JsRegex)] = {
        let raw: [(Kind, String)] = [
            (.morning, #"^(good morning|morning|bom dia)$"#),
            (.afternoon, #"^(good afternoon|boa tarde)$"#),
            (.evening, #"^(good evening|boa noite)$"#),
            (.night, #"^(good night|night)$"#),
            (.howAreYou, #"^(how are you|how(?:'s| is) it going|how are things|what'?s up|sup|tudo (bem|bom|certo|joia)|como vai|como (voce )?esta|e ai|eai|beleza|blz)$"#),
            (.thanks, #"^(thanks?( you)?( so much| a lot)?|thx|ty|obrigad[oa]( mesmo)?|valeu|vlw|brigad[oa])$"#),
            (.bye, #"^(bye|goodbye|see ya|see you|tchau|ate mais|ate logo|falou)$"#),
            (.ok, #"^(ok(ay)?|cool|nice|great|perfect|got it|beleza|show|massa|legal|blz|certo|entendi)$"#),
            (.hello, #"^(hi|hello|hey|hey there|yo|hiya|oi|ola|ola tudo bem|opa|e ai boar|oi boar|hi boar|hello boar|hey boar)$"#),
        ]
        return raw.map { ($0.0, JsRegex($0.1)) }
    }()

    private static let segmentSplit = JsRegex(#"[,;]|\band\b"#, flags: "i")

    /// The kinds of every segment, or nil when one segment isn't small talk ("hi, what is a monsoon").
    private static func kinds(_ message: String) -> [Kind]? {
        // Split before norm(), which turns the commas into spaces.
        let segments = segmentSplit.split(message).map(norm).filter { !$0.isEmpty }
        if segments.isEmpty { return nil }
        var out: [Kind] = []
        for seg in segments {
            guard let k = phrases.first(where: { $0.1.containsMatch(in: seg) })?.0 else { return nil }
            out.append(k)
        }
        return out
    }

    private static let aboutRe = JsRegex(
        #"^(what'?s? (is )?your name|who are you|what are you|what can you do|how can you help( me)?|how do you work|are you (an? )?(ai|bot|robot|human|real|person|online|offline)|qual (e )?(o )?seu nome|quem e voce|quem (e )?vc|o que (e )?voce|o que voce (faz|pode fazer)|como voce funciona|voce e (uma? )?(ia|robo|humano|pessoa))( please| por favor)?$"#
    )
    private static let timeRe = JsRegex(#"^(what time is it|what'?s? (is )?the time|que horas sao|que hora e)( now| agora)?$"#)
    private static let dateRe = JsRegex(#"^(what day is (it( today)?|today)|what'?s? (is )?today'?s date|what is the date( today)?|que dia e hoje|qual (e )?a data( de)? hoje)$"#)

    private static let ptWords = JsRegex(
        #"\b(oi|ola|opa|bom|boa|tudo|como|obrigad[oa]|brigad[oa]|valeu|vlw|tchau|ate|falou|beleza|blz|show|massa|legal|certo|entendi|eai|qual|quem|voce|vc|que|hoje|horas|seu)\b"#
    )

    private static let reply: [Kind: (en: String, pt: String)] = [
        .hello: ("Hi! What would you like to know?", "Oi! O que você quer saber?"),
        .morning: ("Good morning! What would you like to know?", "Bom dia! O que você quer saber?"),
        .afternoon: ("Good afternoon! What would you like to know?", "Boa tarde! O que você quer saber?"),
        .evening: ("Good evening! What would you like to know?", "Boa noite! O que você quer saber?"),
        .night: ("Good night!", "Boa noite!"),
        .howAreYou: ("All good, and ready offline. What would you like to know?", "Tudo certo, e pronto offline. O que você quer saber?"),
        .thanks: ("You're welcome!", "De nada!"),
        .bye: ("Bye! I'll be here, offline.", "Tchau! Estou aqui, offline."),
        .ok: ("Great. Ask me anything else.", "Beleza. Pode perguntar mais."),
    ]

    private static let aboutEn =
        "I'm BOAR, a research assistant that runs entirely on this phone. I answer from the library on it (Wikipedia and the packs you installed) and show the sources behind each answer. Nothing you ask leaves the phone."
    private static let aboutPt =
        "Sou o BOAR, um assistente de pesquisa que roda inteiro neste celular. Respondo a partir da biblioteca dele (a Wikipédia e os pacotes que você instalou) e mostro as fontes de cada resposta. Nada do que você pergunta sai do celular."

    // The reply of the most meaningful part: "hi, how are you?" answers how-are-you, "ok thanks" answers thanks.
    private static let order: [Kind] = [.howAreYou, .thanks, .bye, .night, .morning, .afternoon, .evening, .hello, .ok]

    private static let weekdaysEn = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let weekdaysPt = ["segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo"]
    private static let monthsEn = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    private static let monthsPt = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"]

    private static func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    /// A reply for pure small talk, or nil when the message needs the normal answer path. [now] in [timeZone] is the
    /// phone's clock (JS formats a Date in the local zone), printed as Intl's en-US / pt-BR formats do.
    public static func smallTalkReply(_ message: String, pt: Bool, now: Date = Date(), timeZone: TimeZone = .current) -> Reply? {
        let n = norm(message)
        if n.isEmpty || n.utf16.count > 80 { return nil }
        // "oi" or "valeu" is too short for a language detector: the phrase itself says Portuguese.
        let isPt = pt || ptWords.containsMatch(in: n)
        if aboutRe.containsMatch(in: n) { return Reply(text: isPt ? aboutPt : aboutEn, kind: "about") }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let t = cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: now)
        let hour = t.hour!, minute = t.minute!
        if timeRe.containsMatch(in: n) {
            if isPt { return Reply(text: "São \(pad2(hour)):\(pad2(minute)), pelo relógio deste celular.", kind: "time") }
            let h12 = hour % 12 == 0 ? 12 : hour % 12
            return Reply(text: "It's \(pad2(h12)):\(pad2(minute)) \(hour < 12 ? "AM" : "PM") by this phone's clock.", kind: "time")
        }
        if dateRe.containsMatch(in: n) {
            let wd = (t.weekday! + 5) % 7 // Calendar: 1 = Sunday; here 0 = Monday
            let mo = t.month! - 1
            if isPt {
                return Reply(text: "Hoje é \(weekdaysPt[wd]), \(t.day!) de \(monthsPt[mo]) de \(t.year!), pelo relógio deste celular.", kind: "date")
            }
            return Reply(text: "Today is \(weekdaysEn[wd]), \(monthsEn[mo]) \(t.day!), \(t.year!), by this phone's clock.", kind: "date")
        }
        guard let k = kinds(message) else { return nil }
        let pick = order.first { k.contains($0) }!
        let r = reply[pick]!
        return Reply(text: isPt ? r.pt : r.en, kind: "greeting")
    }
}
