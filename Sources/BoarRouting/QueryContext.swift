import Foundation

/// Ported from QueryContext.kt (itself src/routing/context.ts as of r4to's PR #85, BOAR R&D, MIT): the question
/// predicates for health, seed phrases, Portuguese and Spanish. The regexes are the TypeScript ones verbatim, through
/// JsRegex.
public enum QueryContext {
    private static let languageNames =
        #"thai|japanese|korean|chinese|mandarin|cantonese|arabic|russian|greek|hebrew|hindi|khmer|lao|vietnamese|indonesian|malay|turkish|spanish|french|german|italian|portuguese|tailand[êe]s|japon[êe]s|coreano|chin[êe]s|mandarim|[áa]rabe|russo|grego|hebraico|vietnamita|indon[ée]sio|turco|espanhol|franc[êe]s|alem[ãa]o|italiano|portugu[êe]s"#
    private static let health = JsRegex(#"\b(first aid|nose ?bleeds?|bleed(ing)?|burns?|scald(ed|s)?|bites?|stings?|snake|venom|poison(ing|ed)?|overdose|cpr|resuscitat\w*|chok(e|ing)|heimlich|fractur\w*|broken (bone|arm|leg)|sprain\w*|concussion|seizures?|stroke|heart attack|cardiac|allerg\w*|anaphyla\w*|epipen|asthma|hypotherm\w*|heat ?stroke|frostbite|drown\w*|unconscious|faint\w*|wounds?|fever|dehydrat\w*|symptoms?|dosage|medicine|medication|injur\w*|emergency|shiver\w*|evacuat\w*|contaminated|safe to drink|purify\w*|drinking water|evacua\w*|[áa]gua (pot[áa]vel|contaminada|fervente)|primeiros socorros|sangra\w*|queimadura\w*|picada\w*|mordida\w*|cobra|veneno|envenena\w*|engasg\w*|fratura\w*|desmai\w*|convuls\w*|infarto|avc|alergi\w*|febre|ferida\w*|ferimento\w*|afogamento|rcp|reanima\w*|emerg[eê]ncia|sintomas?|rem[eé]dio)\b"#, flags: "i")
    private static let healthPt = JsRegex(#"(^|[^\p{L}])([áa]gua (pot[áa]vel|contaminada|fervente|quente)|queimadura|picad[ao]|tremend\w*|tremores?|calafrios?|hipotermia|sangramento|engasg\w*|afogamento|desmai\w*|convuls\p{L}*|emerg[êe]ncia)(?![\p{L}])"#, flags: "iu")
    private static let disaster = JsRegex(#"(^|[^\p{L}])(earthquakes?|tsunamis?|floods?|flooding|hurricanes?|tornado(es)?|cyclones?|typhoons?|wildfires?|bush ?fires?|house fires?|kitchen fires?|on fire|caught fire|fires? (breaks?|broke) out|fire alarm|smoke inhalation|landslides?|avalanches?|volcan\p{L}*|eruption|terremotos?|sismos?|tsunamis?|enchentes?|inunda\p{L}*|alagamentos?|furac[ãa]o|tornados?|inc[êe]ndios?|deslizamentos?|avalanches?)(?![\p{L}])"#, flags: "iu")
    private static let actionIntent = JsRegex(#"\b(what (should|do|can|must) (i|we|you|one) do|what to do|how (do|should|can) (i|we|you) (stay|keep|survive|protect|prepare|get|treat|stop|help|make|purify|care)|how to (treat|stop|help|survive|make|purify)|first aid|stay safe|survive|protect (myself|yourself|ourselves)|prepare for|during|after (it|the)|before (it|the)|right now|evacuat\w*)\b|o que (eu )?(fa[çc]o|fazer|devo fazer)|como (agir|me proteger|sobreviver|se proteger|deixo|tornar|fa[çc]o|estancar|parar|tratar|cuidar|socorrer|aliviar)|durante|depois (de|do|da|que)|antes (de|do|da)|segur[ao] para"#, flags: "i")
    private static let injuryDescribed = JsRegex(#"(^|[^\p{L}])(spill\p{L}*|splash\p{L}*|scald\p{L}*|burn\p{L}*|boiling|blister\p{L}*|bit|bitten|stung|sting\p{L}*|bleed\p{L}*|faint\p{L}*|passed out|chok\p{L}*|cut (my|his|her|their|him|herself|himself|myself)|fell (off|down|from)|broke (my|his|her|their)|twist\p{L}*|sprain\p{L}*|swallow\p{L}*|electrocut\p{L}*|derram\p{L}*|escald\p{L}*|queim\p{L}*|fervend\p{L}*|fervent\p{L}*|bolha\p{L}*|mord\p{L}*|picou|picad\p{L}*|sangr\p{L}*|desmai\p{L}*|engasg\p{L}*|cortou|caiu d\p{L}*|bateu a cabe[çc]a|torceu|quebrou|engoliu|choque el[ée]trico|collaps\p{L}*|desabou|desmaiou|se desmay\p{L}*)(?![\p{L}])"#, flags: "iu")
    private static let venomous = JsRegex(#"(^|[^\p{L}])(escorpi\p{L}*|alacr[aá]n\p{L}*|scorpions?|aranhas?|ara[ñn]as?|spiders?|vespas?|abelhas?|avispas?|wasps?|bees?|marimbondos?|lacraia\p{L}*|centopeia\p{L}*|cobras?|serpientes?|víboras?|snakes?|jellyfish|[áa]gua-viva|medusas?)(?![\p{L}])"#, flags: "iu")
    private static let stungOrRisk = JsRegex(#"(^|[^\p{L}])(pic\p{L}*|mord\p{L}*|ferro\p{L}*|stung|stings?|bit|bitten|bites?|grave|perigos\p{L}*|peligros\p{L}*|dangerous|deadly|mata|matar|crian[çc]\p{L}*|beb[êeé]s?|filh[oa]s?|hij[oa]s?|niñ[oa]s?|child\p{L}*|baby|babies|kids?)(?![\p{L}])"#, flags: "iu")
    private static let swallowed = JsRegex(#"(^|[^\p{L}])(engol\p{L}*|se trag\p{L}*|trag[oó]|swallow\p{L}*)(?![\p{L}])"#, flags: "iu")
    private static let unresponsive = JsRegex(#"(^|[^\p{L}])(sem responder|n[ãa]o responde\p{L}*|inconscient\p{L}*|desacordad\p{L}*|no responde|unresponsive|not responding|n[ãa]o est[áa] respirando|no respira|not breathing)(?![\p{L}])"#, flags: "iu")
    private static let healthEs = JsRegex(#"(^|[^\p{L}])(picad[oa]s?|picó|mordid[oa]s?|mordió|quemad\p{L}*|quemó|atragant\p{L}*|envenen\p{L}*|intoxica\p{L}*|convulsi\p{L}*|desmay\p{L}*|sangrando|sangrad\p{L}*|sangre|fiebre|emergencia|primeros auxilios)(?![\p{L}])"#, flags: "iu")
    private static let shouldIntent = JsRegex(#"(^|[^\p{L}])(should (i|we|you|he|she|they)(?! (worry|bring|pack|visit|go(?! to (the )?(hospital|doctor|er|a&e|clinic|emergency))|travel|book|plan|cancel|still|be worried|be concerned|avoid (going|traveling|travelling)))|devo|devemos|debo|debemos|qu[ée] hago|qu[ée] hacemos)(?![\p{L}])"#, flags: "iu")
    private static let headInjury = JsRegex(#"(^|[^\p{L}])(head injur\p{L}*|hit (his|her|my|their) head|bumped (his|her|my|their) head|fell on (his|her|my|their) head|concussion|bateu a cabe[çc]a|batida na cabe[çc]a|pancada na cabe[çc]a|caiu de cabe[çc]a|traumatismo cran\p{L}*|concuss[ãa]o|se golpe[óo] la cabeza|golpe en la cabeza|traumatismo craneal|conmoci[óo]n cerebral)(?![\p{L}])"#, flags: "iu")
    private static let chestPainMetaphor = JsRegex(#"saudade|cora[çc][ãa]o partido|heartbreak|broken heart|de amor|desamor|por (ela|ele|ti|vos)"#, flags: "iu")
    private static let chestPain = JsRegex(#"(^|[^\p{L}])(chest (pain|pains|tightness|pressure|hurts?)|pain in (my|his|her|their) chest|pressure (in|on) (my|his|her|their) chest|tight(ness)? in (my|his|her|their) chest|dor (forte )?no peito|aperto no peito|press[ãa]o no peito|dolor (fuerte )?(en el|de) pecho|opresi[óo]n en el pecho)(?![\p{L}])"#, flags: "iu")
    private static let frostbite = JsRegex(#"(^|[^\p{L}])(frostbit\p{L}*|frostnip)(?![\p{L}])"#, flags: "iu")
    private static let phraseHealthContent = JsRegex(#"(?<![\p{L}])(al[ée]rg\p{L}*|allerg\p{L}*|anaphyla\p{L}*|epipen|insulin\p{L}*|diabet\p{L}*|epilep\p{L}*|asthma|asma|medicine|medication|pills?|rem[ée]dios?|medicamentos?|rem[ée]dio|disease|illness|sick|doen[çc]a|doente|symptoms?|sintomas?|pain|hurts?|dor(es)?|d[óo]i|blood|sangue|sangr\p{L}*|bleed\p{L}*|doctor|m[ée]dic[oa]|hospital|ambulance|ambul[âa]ncia|pregnant|gr[áa]vida|heart|cora[çc][ãa]o|emergency|emerg[êe]ncia)(?![\p{L}])"#, flags: "iu")
    private static let phraseAsk = JsRegex(#"\b(how (do|would|can|should) (i|you|we) say|how to say|how do (you|i) greet|what('s| is| are) [^?]{1,40} in (\#(languageNames))|translate)\b|(?<![\p{L}])(como (se )?diz|como (eu )?(falo|digo|cumprimento)|como se fala|como se escreve|como [ée] [^?]{1,40} em (\#(languageNames)))(?![\p{L}])"#, flags: "iu")
    private static let aBit = JsRegex(#"\ba (little )?bit\b"#, flags: "gi")
    private static let seedPhrase = JsRegex(#"(?<![\p{L}\p{N}])(seed[- ]?phrases?|recovery (phrases?|words|seeds?)|mnemonic (phrases?|words|seeds?)|wallet back ?ups?|back(ing|ed)? ?up (my|your|the|a|our) (\p{L}+ )?wallets?|frases?[- ](sementes?|de recupera[çc][ãa]o)|palavras[- ](de recupera[çc][ãa]o|sementes?)|frases?[- ](semillas?|de recuperaci[óo]n)|palabras[- ](semillas?|de recuperaci[óo]n)|copias? de seguridad (de la|de mi|de tu|del) (\p{L}+ )?(cartera|billetera|monedero)s?|backup (da|de|das|de uma|da minha|da sua) (\p{L}+ )?carteiras?)(?![\p{L}\p{N}])"#, flags: "iu")
    private static let seedWords = JsRegex(#"(?<![\p{L}\p{N}])(mnemonic|private keys?|chaves? privadas?|claves? privadas?|(12|24|twelve|twenty[- ]four)[- ]words?|(12|24|doze|vinte e quatro) palavras)(?![\p{L}\p{N}])"#, flags: "iu")
    private static let cryptoContext = JsRegex(#"(?<![\p{L}\p{N}])(wallets?|carteiras?|billeteras?|carteras?|monederos?|crypto\p{L}*|cripto\p{L}*|bitcoins?|btc|ethereum|eth|coins?|moedas?|blockchain|metamask|ledger|trezor|seed|semente|bip ?39)(?![\p{L}\p{N}])"#, flags: "iu")
    private static let ptQuestion = JsRegex(#"\b(como|o que|quando|onde|qual|quais|por que|porque|devo|fazer|posso|existe|quem|quanto)\b"#, flags: "i")
    private static let ptOnly = JsRegex(#"(?<![\p{L}])(é|são|não|em|uma|umas|dos|das|nos|nas|pelo|pela|com|sem|isso|isto|está|estão|também|você|vocês|meu|minha|seus|suas|dar|fazer|que|para|da|lá|alguns|algumas)(?![\p{L}])"#, flags: "giu")
    private static let ptAccent = JsRegex(#"(^|[^\p{L}])[a-zà-ÿ]*[ãõçâêôáéíóú]"#, flags: "u")
    private static let inverted = JsRegex(#"[¿¡]"#, flags: "")
    private static let esOnly = JsRegex(#"(?<![\p{L}])(qué|cómo|cuándo|dónde|hago|hijo|hija|niño|niña|niños|bebé|mi|una|tragó|picó|mordió|ayuda|ayudarlo|ayudarla|pila|alacrán|peligroso|es|muy|tiene|puedo|debo|hacer)(?![\p{L}])"#, flags: "giu")

    /// Health, first aid and emergencies.
    public static func isHealthQuestion(_ query: String) -> Bool {
        (venomous.containsMatch(in: query) && stungOrRisk.containsMatch(in: query))
            || swallowed.containsMatch(in: query)
            || unresponsive.containsMatch(in: query)
            || healthEs.containsMatch(in: query)
            || health.containsMatch(in: query)
            || healthPt.containsMatch(in: query)
            || (disaster.containsMatch(in: query) && (actionIntent.containsMatch(in: query) || shouldIntent.containsMatch(in: query)))
            // "a bit" is not "bit" (bitten).
            || (injuryDescribed.containsMatch(in: aBit.replace(in: query, with: " ")) && (actionIntent.containsMatch(in: query) || shouldIntent.containsMatch(in: query)))
            || frostbite.containsMatch(in: query)
            || (chestPain.containsMatch(in: query) && !chestPainMetaphor.containsMatch(in: query))
            || headInjury.containsMatch(in: query)
            // A phrase to translate that carries health content stays on the health path.
            || (phraseAsk.containsMatch(in: query) && phraseHealthContent.containsMatch(in: query))
    }

    /// Seed phrases and wallet backups (the prompt test plan's trigger list, Oct 18): a wrong detail loses the coins.
    /// "Mnemonic", "private key" and "12/24 words" count only next to a wallet or a coin (an SSH private key is not one).
    public static func isSeedPhraseQuestion(_ query: String) -> Bool {
        seedPhrase.containsMatch(in: query) || (seedWords.containsMatch(in: query) && cryptoContext.containsMatch(in: query))
    }

    /// Its interrogatives or, failing those, two words English doesn't use (or one plus an accent in a lowercase word).
    public static func isPortugueseQuestion(_ query: String) -> Bool {
        if ptQuestion.containsMatch(in: query) { return true }
        let strong = ptOnly.findAll(in: query).count
        return strong >= 2 || (strong >= 1 && ptAccent.containsMatch(in: query))
    }

    /// Inverted marks, or three distinct words Portuguese and English don't use.
    public static func isSpanishQuestion(_ query: String) -> Bool {
        if inverted.containsMatch(in: query) { return true }
        return Set(esOnly.findAll(in: query).map { $0.value.lowercased() }).count >= 3
    }
}
