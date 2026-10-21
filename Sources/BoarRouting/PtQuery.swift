import Foundation

/// English search words for a question (port of src/routing/ptQuery.ts). A Portuguese question gets English words so
/// it can find the knowledge packs, which are in English ("Como faço para parar um sangramento no nariz?" retrieved
/// nothing from the Preparedness pack). A fixed dictionary of health, first-aid and emergency terms: no model call, so
/// it is instant and can't invent a query. Nil when no term is known (the question is searched as written).
public enum PtQuery {
    // Longest phrases first: "sangramento no nariz" before "sangramento".
    private static let ptEn: [(JsRegex, String)] = {
        let raw: [(String, String)] = [
            (#"sangramento (no|do|pelo) nariz|sangramento nasal|sangue (no|do|pelo) nariz|nariz[^.?!]{0,20}sangr\w*|sangr\w*[^.?!]{0,20}nariz|epistaxe"#, "nosebleed nose bleed"),
            (#"primeiros socorros"#, "first aid"),
            (#"picada de (cobra|serpente)|mordida de (cobra|serpente)|picad[ao] por (uma )?(cobra|serpente)|mordid[ao] por (uma )?(cobra|serpente)|(cobra|serpente)[^.]{0,30}(picou|mordeu)|(picou|mordeu)[^.]{0,30}(cobra|serpente)"#, "snakebite snake bite"),
            (#"picada de (abelha|vespa)|ferroada"#, "bee sting"),
            (#"picada de escorpi[ãa]o"#, "scorpion sting"),
            (#"parada card[íi]aca"#, "cardiac arrest"),
            (#"ataque card[íi]aco|infarto"#, "heart attack"),
            (#"\bavc\b|derrame"#, "stroke"),
            (#"\brcp\b|reanima[çc][ãa]o( cardiopulmonar)?|massagem card[íi]aca"#, "cpr"),
            // A scald is a burn: "derramou água fervente no braço" must find Burn, not the physics of boiling.
            (#"(derram|caiu|queim|escald|jog)\w*[^.]{0,40}(água|[áa]gua|[óo]leo|caf[ée]|ch[áa]|sopa|leite) (fervente|fervendo|quente|escaldante)|(água|[áa]gua|[óo]leo) (fervente|fervendo|quente|escaldante)[^.]{0,40}(derram|caiu|queim|escald)\w*|escaldadura|escaldou|se queimou|queimou (o|a|a m[ãa]o|o bra[çc]o)"#, "burn scald"),
            (#"[áa]gua (fervente|fervendo)|[áa]gua quente"#, "boiling water"),
            // Shivering, confused, slurred speech in the cold: hypothermia.
            (#"(tremend\w*|tremores?|calafrios?)[^.]{0,80}\bfrio\b|\bfrio\b[^.]{0,80}(tremend\w*|tremores?|calafrios?)"#, "hypothermia"),
            (#"[áa]gua pot[áa]vel|[áa]gua (segura|limpa) para beber|tornar a [áa]gua (segura|pot[áa]vel)"#, "safe drinking water"),
            (#"[áa]gua contaminada"#, "contaminated water"),
            (#"insola[çc][ãa]o|golpe de calor"#, "heatstroke heat stroke"),
            (#"rea[çc][ãa]o al[ée]rgica|choque anafil[áa]tico|anafilaxia"#, "anaphylaxis allergic reaction"),
            (#"sangramento|hemorragia|sangrando"#, "bleeding"),
            (#"queimadura|queimou|queimad[oa]"#, "burn"),
            (#"cobra|serpente"#, "snake"),
            (#"engasg\w*|asfixia"#, "choking"),
            (#"afogamento|afogad[oa]"#, "drowning"),
            (#"hipotermia"#, "hypothermia"),
            (#"desidrata[çc][ãa]o"#, "dehydration"),
            (#"desmai\w*"#, "fainting"),
            (#"convuls[ãa]o|convuls\w*"#, "seizure"),
            (#"fratura|osso quebrado|quebrou o (bra[çc]o|perna|osso)"#, "fracture broken bone"),
            (#"tor[çc][ãa]o|entorse"#, "sprain"),
            (#"envenenamento|envenenad[oa]|veneno"#, "poisoning"),
            (#"ferida|ferimento|machucad[oa]|corte profundo"#, "wound"),
            (#"febre"#, "fever"),
            (#"alergia"#, "allergy"),
            // Before "terremoto": the plates (Sextant RF-1, "…perto das bordas das placas?").
            (#"(bordas?|limites?|fronteiras?) (das|entre as) placas|placas? tect[ôo]nicas?|tect[ôo]nica de placas"#, "plate tectonics plate boundary"),
            (#"terremoto|sismo|tremor de terra"#, "earthquake"),
            (#"enchente|inunda[çc][ãa]o|alagamento"#, "flood"),
            (#"furac[ãa]o|tuf[ãa]o|ciclone"#, "hurricane"),
            (#"inc[êe]ndio|fogo"#, "fire"),
            (#"evacua[çc][ãa]o|evacuar"#, "evacuation"),
            (#"nariz"#, "nose"),
            (#"crian[çc]a|beb[êe]s?(?![a-zà-ÿ])"#, "child"),
            (#"parar|estancar|interromper"#, "stop"),
            (#"tratar|tratamento|cuidar"#, "treat"),
            (#"prevenir|evitar"#, "prevent"),
        ]
        return raw.map { (JsRegex($0.0, flags: "i"), $0.1) }
    }()

    /// English search words for the Portuguese terms in [query] (each matched phrase consumed), or nil.
    public static func englishSearchTerms(_ query: String) -> String? {
        var out: [String] = []
        var rest = query
        for (re, en) in ptEn where re.containsMatch(in: rest) {
            rest = re.replace(in: rest, with: " ")
            if !out.contains(en) { out.append(en) }
        }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    // English first-aid questions phrased as a story ("I just got bitten by a snake while hiking") share few words with
    // the articles (Snakebite, Burn, Hypothermia): search with their names. No "first aid" added: it pulls in generic
    // first-aid articles ("Mental health first aid").
    private static let enCanonical: [(JsRegex, String)] = {
        let raw: [(String, String)] = [
            (#"\b(bitten|bit) by (a |an )?(snake|viper|rattlesnake|cobra)|\bsnake ?bites?\b"#, "snakebite snake bite"),
            (#"\b(spill\w*|splash\w*|scald\w*|pour\w*)\b[^.]{0,40}\b(boiling|hot) (water|oil|coffee|tea)|\b(boiling|hot) (water|oil)[^.]{0,40}\b(spill\w*|scald\w*|burn\w*)|\bscalds?\b"#, "burn scald"),
            (#"\bshiver\w*[^.]{0,80}\bcold\b|\bcold\b[^.]{0,80}\bshiver\w*"#, "hypothermia"),
            (#"\bnose ?bleeds?\b|\bbleed\w*[^.?!]{0,20}\bnose\b|\bnose\b[^.?!]{0,20}\bbleed\w*"#, "nosebleed nose bleed"),
            // Any other bleeding ("My arm is bleeding a lot"): the articles' word, not the story's.
            (#"\bbleed(s|ing)?\b"#, "bleeding"),
            (#"\bchok(e|ing)\b"#, "choking"),
            // Earthquakes and floods: the question's own words find the "During an earthquake" sections better.
        ]
        return raw.map { (JsRegex($0.0, flags: "i"), $0.1) }
    }()

    /// Canonical English search words for an English first-aid question, or nil.
    public static func canonicalHealthTerms(_ query: String) -> String? {
        var out = enCanonical.filter { $0.0.containsMatch(in: query) }.map(\.1)
        // A nosebleed is not generic bleeding (it would pull in "Emergency bleeding control").
        if out.contains("nosebleed nose bleed") { out.removeAll { $0 == "bleeding" } }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }
}
