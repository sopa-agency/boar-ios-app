import BoarRouting
import Foundation

/// The questions Lunar, Nomad and Vitals answer themselves, from the device's own data (android engine/labs
/// `PluginAnswers.kt`, rc3 7286cf91 and bd041e73; adam, Nov 12: "plugins that answer"), and the answers' text in English
/// and Portuguese. Only a question that clearly asks for that data is taken: "the moon landing" or "north of France" go to
/// the model as before.
///
/// iOS differences (docs/labs-ios.md): the answers name the device (`device`, "iPhone"/"Mac") where Android says "phone";
/// "my iPhone", "this iPad" count as the device, as "my phone" does; and Vitals, which can't read the battery temperature
/// on iOS, says the system's heat level instead (`PhoneNow.heatLevel`).
public enum PluginAnswers {
    /// The device as the answers name it: Android's "phone" / "celular" by default.
    public struct Device: Sendable, Equatable {
        public let en: String
        public let pt: String
        public init(en: String, pt: String) { self.en = en; self.pt = pt }
        public static let phone = Device(en: "phone", pt: "celular")
    }

    // MARK: Lunar

    // No bare "lunar" ("lunar eclipse", "lunar new year"), and no title: "Moon Knight", "Sailor Moon", "lua de mel" (validator P-2).
    private static let moon = Rx(#"\b(moon|moons|lua|lunar phase|fase lunar)\b"#, ignoreCase: true)
    private static let moonNot = Rx(#"\b(eclipse|eclipses|new year|ano novo|knight|sailor|lua de mel|honeymoon|festival)\b"#, ignoreCase: true)
    /// A date or the past ("the moon on July 20 1969", "last night's moon"): the answer is for now only (CodeRabbit).
    private static let moonDated = Rx(#"\b(1[5-9][0-9][0-9]|2[0-9][0-9][0-9])\b|\byesterday\b|\blast (night|week|month|year)\b|\bontem\b|\b(semana|m[eê]s|ano) passad[oa]\b"#, ignoreCase: true)
    /// "Moon Knight", "Lua Nova" as a name: a capitalised word after the moon word (case-sensitive on purpose).
    private static let moonName = Rx(#"\b(Moon|Lua)\s+\p{Lu}"#)
    private static let moonNow = Rx(
        #"\b(phase|phases|tonight|today|now|this (week|month)|next (full|new)|full moon|new moon|waxing|waning|crescent|gibbous|lit|"#
            + #"fase|fases|hoje|esta noite|agora|esta semana|este m[eê]s|pr[oó]xima|cheia|nova|minguante|crescente)\b"#,
        ignoreCase: true)
    private static let moonHistory = Rx(#"\b(landing|landed|apollo|armstrong|mission|astronaut|pouso|miss[aã]o|astronauta|orbit|[oó]rbita|distance|dist[aâ]ncia|gravity|gravidade)\b"#, ignoreCase: true)
    /// "what's the moon", "whats the moon like", "moon phase": asking for the moon now without a time word.
    private static let moonAsk = Rx(#"\bwhat'?s the moon\b|\bwhat is the moon (like|doing)\b|\bmoon (phase|tonight|today|now)\b|\bcomo est[aá] a lua\b|\bfase da lua\b|\blunar phase\b|\bfase lunar\b"#, ignoreCase: true)

    public static func isMoonQuestion(_ q: String) -> Bool {
        let n = norm(q)
        return moon.containsMatch(in: n) && (moonNow.containsMatch(in: n) || moonAsk.containsMatch(in: n)) && !moonHistory.containsMatch(in: n)
            && !moonNot.containsMatch(in: n) && !moonName.containsMatch(in: n) && !moonDated.containsMatch(in: n)
    }

    /// Curly apostrophes as straight ones: "where’s" is "where's".
    private static func norm(_ q: String) -> String {
        q.replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
    }

    private static let phaseEN = ["new": "a new moon", "waxingCrescent": "a waxing crescent", "firstQuarter": "at first quarter",
                                  "waxingGibbous": "a waxing gibbous", "full": "full", "waningGibbous": "a waning gibbous",
                                  "lastQuarter": "at last quarter", "waningCrescent": "a waning crescent"]
    private static let phasePT = ["new": "nova", "waxingCrescent": "crescente", "firstQuarter": "no quarto crescente",
                                  "waxingGibbous": "crescente gibosa", "full": "cheia", "waningGibbous": "minguante gibosa",
                                  "lastQuarter": "no quarto minguante", "waningCrescent": "minguante"]

    public static func moonAnswer(_ q: String, nowMs: Int64, zone: TimeZone = .current, device: Device = .phone) -> String {
        let s = MoonPhase.at(nowMs)
        let key = MoonPhase.nameKey(s)
        let pct = Int((s.illumination * 100 + 0.5).rounded(.down))
        let pt = QueryContext.isPortugueseQuestion(q)
        let f = DateFormatter()
        f.locale = Locale(identifier: pt ? "pt_BR" : "en_US")
        f.timeZone = zone
        f.dateFormat = pt ? "d 'de' MMMM, HH:mm" : "MMMM d, HH:mm"
        func day(_ ms: Int64) -> String { f.string(from: Date(timeIntervalSince1970: Double(ms) / 1000)) }
        return pt
            ? "A lua está \(phasePT[key] ?? key) agora, com \(pct)% iluminada. Próxima lua cheia: \(day(s.nextFullMs)). Próxima lua nova: \(day(s.nextNewMs)). Calculado no \(device.pt), sem internet."
            : "The moon is \(phaseEN[key] ?? key) now, \(pct)% lit. Next full moon: \(day(s.nextFullMs)). Next new moon: \(day(s.nextNewMs)). Worked out on this \(device.en), offline."
    }

    // MARK: Nomad

    /// After the cardinal the question ends, or says "from here", "now"...: "North Carolina", "North Korea's capital",
    /// "o Sul do Brasil" and "o Norte Shopping" are places, not headings (validator P-1).
    private static let headingEnd = #"(?=\s*(?:$|[?.!,;]|(?:from here|right now|now|exactly|please|pls|here|today|on (?:my|this) (?:phone|map)|i'?m lost|i am lost|daqui|agora|exatamente|por favor|aqui|hoje)\b|\s*[-–—]))"#

    private static let direction = Rx(
        #"\b(which way is|which way'?s|where is|where'?s|what'?s|whats|what direction (is|am i)|which direction (is|am i)|point me|find) (to )?(the )?(north|south|east|west)"#
            + headingEnd + "|"
            + #"\bwhich (way|direction) am i (facing|heading|pointing)\b|\bmy heading\b|\bcompass (heading|reading|direction)\b|"#
            + #"\b(onde fica|onde [eé]|para onde fica|para que lado fica|qual dire[cç][aã]o [eé]) o (norte|sul|leste|oeste)"# + headingEnd + "|"
            + #"\bpara (onde|que lado|que dire[cç][aã]o) estou (virado|apontando|olhando)\b"#,
        ignoreCase: true)

    /// "What's north of France" is geography, not a heading.
    private static let notDirection = Rx(#"\b(north|south|east|west) of\b|\b(norte|sul|leste|oeste) (de|do|da|dos|das)\b"#, ignoreCase: true)

    public static func isDirectionQuestion(_ q: String) -> Bool {
        direction.containsMatch(in: norm(q)) && !notDirection.containsMatch(in: norm(q))
    }

    /// Past this tilt the compass reads wrong: "hold the phone flat".
    public static let flatDeg = 18.0

    /// `heading`: degrees from magnetic north the device's top points at; nil without a compass.
    public static func directionAnswer(_ q: String, heading: Double?, tiltDeg: Double?, device: Device = .phone) -> String {
        let pt = QueryContext.isPortugueseQuestion(q)
        guard let heading else {
            return pt ? "Este \(device.pt) não tem bússola (sensor magnético), então o Nomad não consegue dizer a direção."
                : "This \(device.en) has no compass (magnetic sensor), so Nomad can't tell the direction."
        }
        // Kotlin roundToInt: half up.
        let deg = Int((heading + 0.5).rounded(.down)) % 360
        let names = pt ? dirsPT : dirsEN
        let name = names[CompassMath.cardinal(deg)] ?? ""
        // "Which way is east": the turn to east, not to north (CodeRabbit). North otherwise.
        let asked = askedCardinal(q)
        let target = ["n": 0, "e": 90, "s": 180, "w": 270][asked] ?? 0
        let north = ((target - deg) % 360 + 360) % 360
        let askedName = capitalized(names[asked] ?? "")
        // Facing it already: "straight ahead", not "0° to your right" (validator M-5).
        let turn = north == 0 ? (pt ? "bem à sua frente" : "straight ahead")
            : north <= 180 ? (pt ? "\(north)° à direita" : "\(north)° to your right")
            : (pt ? "\(360 - north)° à esquerda" : "\(360 - north)° to your left")
        let flat = tiltDeg.map { $0 > flatDeg } ?? false
        let base = pt ? "O topo do \(device.pt) aponta para \(name) (\(deg)°). \(askedName) fica \(north == 0 ? "" : "a ")\(turn)."
            : "The top of your \(device.en) points \(name) (\(deg)°). \(askedName) is \(turn)."
        let hold = !flat ? "" : pt ? " Segure o \(device.pt) deitado, na horizontal: inclinado, a bússola erra." : " Hold the \(device.en) flat: tilted, the compass reads wrong."
        let note = pt ? " Norte magnético; afaste de ímãs e metais." : " Magnetic north; keep it away from magnets and metal."
        return base + hold + note
    }

    private static let askedRx = Rx(#"\b(north|south|east|west|norte|sul|leste|oeste)\b"#, ignoreCase: true)

    /// The cardinal the question asks for: "n", "e", "s" or "w"; north when it names none ("which way am I facing").
    private static func askedCardinal(_ q: String) -> String {
        switch askedRx.firstMatch(in: q)?.group(0, in: q)?.lowercased() {
        case "south", "sul": "s"
        case "east", "leste": "e"
        case "west", "oeste": "w"
        default: "n"
        }
    }

    /// Kotlin `replaceFirstChar { it.uppercase() }`.
    private static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    private static let dirsEN = ["n": "north", "ne": "northeast", "e": "east", "se": "southeast", "s": "south", "sw": "southwest", "w": "west", "nw": "northwest"]
    private static let dirsPT = ["n": "o norte", "ne": "o nordeste", "e": "o leste", "se": "o sudeste", "s": "o sul", "sw": "o sudoeste", "w": "o oeste", "nw": "o noroeste"]

    // MARK: Vitals

    // iOS adds "iphone" and "ipad" to Android's device words.
    private static let phone = Rx(#"\b(my|this) (phone|device|cellphone|mobile|iphone|ipad)\b|\bthe (phone|cellphone|iphone|ipad)\b|\b(meu|este|deste|do|o) (celular|telefone|aparelho|iphone|ipad)\b|\b(phone|iphone|ipad)'?s\b"#, ignoreCase: true)
    private static let phoneWhat = Rx(
        #"\b(battery|charging|temperature|hot|heat|overheat|overheating|warm|memory|ram|cpu|processor|cores|processes|"#
            + #"bateria|carga|carregando|temperatura|quente|esquentando|aquecendo|mem[oó]ria|processador|n[uú]cleos|processos)\b"#,
        ignoreCase: true)
    /// "my battery", "minha bateria": the phone's own, with no phone word needed.
    private static let myBattery = Rx(#"\bmy battery\b|\bminha bateria\b|\bbattery level\b|\bn[ií]vel da bateria\b"#, ignoreCase: true)
    /// Advice, not a reading: "how do I charge this phone faster", "what battery should I buy for my phone" go to the model
    /// (validator P-3: Vitals is on by default, so a wrong first answer reaches everyone).
    private static let advice = Rx(
        #"\bhow (do|can|should|to|does|would)\b|\bhow to\b|\bshould i\b|\bbuy\b|\bfaster\b|\blonger\b|\btips?\b|\bwhy\b|\bbest\b|\bimprove\b|\bsave\b|"#
            + #"\bcomo (fa[cç]o|posso|devo|fazer|economizar)\b|\bcomprar\b|\bmais r[aá]pido\b|\bdicas?\b|\bpor ?que\b|\bmelhor\b|\bdurar mais\b"#,
        ignoreCase: true)

    public static func isPhoneQuestion(_ q: String) -> Bool {
        let n = norm(q)
        return ((phone.containsMatch(in: n) && phoneWhat.containsMatch(in: n)) || myBattery.containsMatch(in: n)) && !advice.containsMatch(in: n)
    }

    /// What Vitals read just now. `heatLevel` (iOS only): the system's thermal state, 0 nominal … 3 critical, said when
    /// there is no battery temperature (iOS never has one).
    public struct PhoneNow: Sendable, Equatable {
        public var batteryPct: Int?
        public var charging: Bool?
        public var batteryTempC: Double?
        public var ramFreeMb: Int64?
        public var ramTotalMb: Int64?
        public var cores: Int?
        public var heatLevel: Int?

        public init(batteryPct: Int?, charging: Bool?, batteryTempC: Double?, ramFreeMb: Int64?, ramTotalMb: Int64?, cores: Int?, heatLevel: Int? = nil) {
            self.batteryPct = batteryPct
            self.charging = charging
            self.batteryTempC = batteryTempC
            self.ramFreeMb = ramFreeMb
            self.ramTotalMb = ramTotalMb
            self.cores = cores
            self.heatLevel = heatLevel
        }
    }

    public static func phoneAnswer(_ q: String, _ p: PhoneNow, device: Device = .phone) -> String {
        let pt = QueryContext.isPortugueseQuestion(q)
        var parts: [String] = []
        if let b = p.batteryPct {
            parts.append(pt ? "bateria em \(b)%" + (p.charging == true ? ", carregando" : "") : "battery at \(b)%" + (p.charging == true ? ", charging" : ""))
        }
        if let t = p.batteryTempC {
            let heat = VitalsHeat.of(t).rawValue
            parts.append(pt ? "temperatura da bateria \(one(t, pt: true)) °C (\(heatPT[heat] ?? heat))" : "battery temperature \(one(t, pt: false)) °C (\(heat))")
        } else if let level = p.heatLevel {
            let i = min(max(level, 0), 3)
            parts.append(pt ? "nível de calor \(["normal", "morno", "quente", "muito quente"][i])" : "heat level \(["cool", "warm", "hot", "too hot"][i])")
        }
        if let free = p.ramFreeMb, let total = p.ramTotalMb {
            parts.append(pt ? "\(one(Double(free) / 1024, pt: true)) GB de memória livres de \(one(Double(total) / 1024, pt: true)) GB"
                : "\(one(Double(free) / 1024, pt: false)) GB of \(one(Double(total) / 1024, pt: false)) GB memory free")
        }
        if let c = p.cores { parts.append(pt ? "\(c) núcleos de processador" : "\(c) processor cores") }
        if parts.isEmpty { return pt ? "O Vitals não conseguiu ler o \(device.pt) agora." : "Vitals couldn't read the \(device.en) just now." }
        let body = capitalized(parts.joined(separator: "; "))
        return pt ? "\(body). Lido agora no \(device.pt); o Vitals mostra mais." : "\(body). Read on this \(device.en) just now; Vitals shows more."
    }

    /// `"%.1f".format(locale, x)`: one decimal, a comma in Portuguese.
    private static func one(_ x: Double, pt: Bool) -> String {
        String(format: "%.1f", locale: Locale(identifier: pt ? "pt_BR" : "en_US"), x)
    }

    private static let heatPT = ["cool": "fria", "warm": "morna", "hot": "quente", "unknown": "desconhecida"]
}

/// Boar Vitals' heat from the battery's own temperature (android engine/labs `Vitals.heat`): below 38 °C cool, below
/// 42 °C warm, above that hot.
public enum VitalsHeat: String, Sendable {
    case unknown, cool, warm, hot

    public static func of(_ tempC: Double?) -> VitalsHeat {
        guard let t = tempC else { return .unknown }
        return t < 38 ? .cool : t < 42 ? .warm : .hot
    }
}
