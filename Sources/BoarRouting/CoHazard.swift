import Foundation

/// Ported from src/routing/coHazard.ts in r4to's PR #85 (BOAR R&D, MIT), through android `routing/CoHazard.kt`.
///
/// CO hazard (Compass 2026-10-03, ship L3 safety finding): "Can I run my portable generator in the attached garage if I
/// keep the door open?" took the model path and got "Yes, … ensure it's well-ventilated". A planning question about a
/// fuel-burning device in an enclosed or attached space gets a fixed safety-fact answer, before any model. Symptom or
/// alarm questions are left out (they go to the model as health questions). Wording: reviewed 2026-10-03, kept verbatim.
/// Sources: CDC "What to Do to Protect Yourself During a Power Outage"; US CPSC "Generators and Engine-Driven Tools"; NHS
/// "Carbon monoxide poisoning". The regexes are the TypeScript ones verbatim, through JsRegex. Portuguese and Spanish
/// patterns and draft answers are Android's own (Labs, Oct 18).
///
/// Not ported (as on Android): isCoExposure and isCoExposureAcrossTurns, which only pick the health route's CO card.
public enum CoHazard {
    private static let b = #"(?<![\p{L}\p{N}_])"#
    private static let e = #"(?![\p{L}\p{N}_])"#
    private static func re(_ s: String) -> JsRegex { JsRegex(s, flags: "iu") }
    private static func reAll(_ s: String) -> JsRegex { JsRegex(s, flags: "giu") }

    /// A device that burns fuel. A plain "grill", "stove" or "heater" may be electric, so those need a fuel word.
    private static let device = re(
        [
            #"\#(b)(?<!(?:random|number|code|site|password|static|image|text|qr|name|idea|key|signal|function|pulse|lorem|tone|wave|pdf|report|hash|ai|music|art|map|meme|solar|battery|jackery|ecoflow|bluetti)[ -])(?:generators?|gennys?|gennies)\#(e)"#,
            #"\#(b)(?<!activated )charcoal\#(e)(?! (?:drawing|pencil|filter|tablet|pill|capsule|mask|soap|toothpaste|grey|gray|colou?r|sketch|powder|supplement))"#,
            #"\#(b)(?:bbqs?|barbecues?|hibachis?)\#(e)"#,
            #"\#(b)(?:a|the|our|my|your) barbie\#(e)"#,
            #"\#(b)(?:gas|propane|charcoal|pellet|wood|camping|camp|portable gas|disposable) (?:grills?|smokers?)\#(e)"#,
            #"\#(b)(?:camping|camp|backpacking|coleman|primus|portable gas|canister|gas canister) (?:stoves?|burners?)\#(e)"#,
            #"\#(b)(?:propane|gas|kerosene|paraffin|butane|coleman) lanterns?\#(e)"#,
            #"\#(b)(?:gas|gasoline|petrol)[- ]powered\#(e)"#,
            #"\#(b)(?:pressure|power) washers?\#(e)"#,
            #"\#(b)(?:propane|butane|gas|coleman|camp|camping) (?:griddles?|torch(?:es)?|cookers?|rings?|fire ?pits?|lanterns?)\#(e)"#,
            #"\#(b)(?:jetboils?|pocket rockets?|blackstone(?: griddles?)?|weed torch(?:es)?|propane torch(?:es)?)\#(e)"#,
            #"\#(b)(?:kerosene|paraffin|oil) (?:lamps?|lanterns?|stoves?)\#(e)"#,
            #"\#(b)(?:gas|gasoline|petrol) (?:leaf blowers?|blowers?|lawn ?mowers?|mowers?|chainsaws?|engines?|tools?|trimmers?|augers?)\#(e)"#,
        ].joined(separator: "|"),
    )
    /// Fuel heaters. Reviewer C2: an installed or vented appliance (water heater, furnace, boiler, direct-vent) is not this hazard.
    private static let heater = re(
        [
            #"\#(b)(?:propane|kerosene|paraffin|butane|gas|diesel|oil|fuel|fuel-burning|camping|buddy|patio|catalytic|outdoor)(?: [\p{L}-]+)? heaters?\#(e)"#,
            #"\#(b)(?:big|little) buddy\#(e)"#,
            #"\#(b)mr\.? heater\#(e)"#,
        ].joined(separator: "|"),
    )
    /// An installed appliance named in passing ("the furnace eats the battery") doesn't veto the message: its name is removed
    /// before the heater test; only vented/direct-vent/flued/installed still veto.
    private static let appliance = reAll(#"\#(b)(?:water heaters?|furnaces?|boilers?)\#(e)"#)
    private static let installed = re(#"\#(b)(?:direct[- ]vent\w*|vented|flued|installed)\#(e)"#)
    /// A propane or butane stove counts unless the only space named is a kitchen (a propane kitchen range is a normal appliance).
    private static let propaneStove = re(#"\#(b)(?:propane|butane) (?:stoves?|burners?)\#(e)"#)
    private static let kitchen = reAll(#"\#(b)(?:(?:rv|camper|caravan|van|boat|motorhome|trailer|apartment|home|house)'?s? )?(?:kitchens?|galleys?)\#(e)"#)
    /// Using a gas oven or range to heat the home (CDC).
    private static let ovenHeat = re(
        #"\#(b)(?:gas )?(?:oven|stove|range)\#(e).{0,40}\#(b)(?:to|for) (?:heat|warm)"# +
            #"|\#(b)(?:heat|heated|heating|warm|warmed|warming)\#(e).{0,50}\#(b)(?:gas )?(?:oven|stove)\#(e) (?:on|open|with the door)"# +
            #"|\#(b)(?:oven|stove)\#(e) on with the door (?:open|down)"#,
    )
    /// An engine left running where the exhaust stays (CDC, NHS): a car warming up in the garage.
    private static let engine = re(
        #"\#(b)(?:car|truck|vehicle|engine|motor|motorcycle|motorbike|lawn ?mower|mower|chainsaw|snow ?blower|leaf blower|atv|quad|van|suv)s?\#(e).{0,40}\#(b)(?:running|run|idle|idling|on|warm(?:ing)? up|start(?:ed|ing)?)\#(e)"# +
            #"|\#(b)(?:run|running|idle|idling|warm(?:ing)? up|leave|start)\#(e).{0,25}\#(b)(?:car|truck|vehicle|engine|motor|motorcycle|motorbike|lawn ?mower|mower|snow ?blower|suv)s?\#(e)"#,
    )
    /// Generator placement near an opening ("is 10 ft from the back door ok?"): the 20-foot rule.
    private static let placement = re(
        #"\#(b)(?:generators?|gennys?)\#(e).{0,80}\#(b)(?:how far|distance|gap|enough|far enough|minimum|close|ok|okay|safe|\d+ ?(?:ft|feet|foot|m|metres|meters))\#(e).{0,60}\#(b)(?:windows?|doors?|vents?|intakes?)\#(e)"# +
            #"|\#(b)(?:how far|distance|gap|minimum|\d+ ?(?:ft|feet|foot|m|metres|meters))\#(e).{0,60}\#(b)(?:windows?|doors?|vents?|intakes?)\#(e).{0,60}\#(b)(?:generators?|gennys?)\#(e)"# +
            #"|\#(b)(?:how far|distance|gap|minimum)\#(e).{0,40}\#(b)(?:generators?|gennys?)\#(e).{0,60}\#(b)(?:windows?|doors?|vents?|intakes?)\#(e)"# +
            #"|\#(b)(?:is|are) \d+ ?(?:ft|feet|foot|m|metres|meters)\#(e).{0,40}\#(b)(?:windows?|doors?|vents?)\#(e)"# +
            #"|\#(b)(?:generators?|gennys?)\#(e).{0,80}\#(b)(?:right next to|next to|right by|right under|under|beside|near|close to|up against)\#(e) (?:my |the |our |his |her |their |a |an )?(?:[\p{L}-]+ ){0,2}(?:windows?|doors?|vents?|hatch(?:es)?)\#(e)"#,
    )

    private static let feet = JsRegex(#"(\d+(?:\.\d+)?) ?(ft|feet|foot|m|metres|meters)(?![\p{L}])"#, flags: "giu")
    private static let metres = JsRegex("^m", flags: "i")

    /// Heating or warming a space with a fuel burner ("warm up the tent with a gas canister stove").
    private static let heatSpace = re(
        #"\#(b)(?:heat|warm)(?:ing)?(?: up)? (?:the |my |our |a )?(?:[\p{L}-]+ )?(?:tent|room|house|home|apartment|camper|van|cabin|shack|shelter|garage|basement|crawl ?space)\#(e).{0,40}\#(b)(?:stoves?|ovens?|grills?|bbqs?|heaters?|burners?|lanterns?)\#(e)"#,
    )
    /// Storing or winterising, nothing running.
    private static let storage = re(#"\#(b)(?:stor(?:e|ing|age)|winteri[sz]\w*|drain(?:ing)?|put (?:it )?away|for the (?:summer|winter|season|off-season))\#(e)"#)
    /// Fiction or history writing, not a plan.
    private static let fiction = re(#"\#(b)(?:novel|my character|screenplay|short story|fiction|historically|historical)\#(e)"#)
    private static let running = re(#"\#(b)(?:run|running|use|using|operate|operating|start|starting|turn(?:ed|ing)? on|fire up|light|lighting)\#(e)"#)
    /// An enclosed or attached space. Bare "inside" is not enough on its own ("inside the function"); a fuel device is required too.
    private static let space = re(
        [
            #"\#(b)indoors?\#(e)"#,
            // A car or truck cab too (Oct 18): "can I run a propane heater in the car?" got no warning.
            #"\#(b)(?:inside|in|into) (?:the |my |our |a |your |an |his |her |their )?(?:[\p{L}-]+ ){0,2}(?:house|home|bedroom|living room|apartment|flat|cabin|room|tent|camper|garage|basement|shed|van|rv|caravan|trailer|motorhome|boat|yurt|hut|shelter|dorm|condo|workshop|barn|porch|sunroom|conservatory|car|truck|suv|vehicle|minivan|pickup)\#(e)"#,
            #"\#(b)garages?\#(e)(?! (?:sale|band|door opener))"#,
            #"\#(b)carports?\#(e)"#,
            #"\#(b)on (?:the |my |our |a )?(?:enclosed |screened |screened-in |covered |closed-in )?(?:porch|sunroom|veranda)\#(e)"#,
            #"\#(b)tents?\#(e)"#,
            #"\#(b)(?:campers?|rvs?|motorhomes?|caravans?|camper ?vans?|travel trailers?)\#(e)"#,
            #"\#(b)(?:basements?|cellars?|crawl ?spaces?|sheds?)\#(e)"#,
            #"\#(b)(?:enclosed|screened[- ]in|closed|covered) (?:porch|patio|balcony|space|area|room|deck)\#(e)"#,
            #"\#(b)(?:ice|fishing|pop-up|popup) (?:fishing )?(?:shack|house|hut|shanty|tent|shelter)s?\#(e)"#,
            #"\#(b)shacks?\#(e)"#,
            // v2 (dev2): a fuel device is already required, so a bare "inside" or a room name is enough here.
            #"\#(b)(?:inside|in here|in there)\#(e)"#,
            #"\#(b)(?:bathrooms?|kitchens?|stalls?|barns?|coops?|stables?|shant(?:y|ies)|cabins?|workshops?|below deck|bunkhouse)\#(e)"#,
            #"\#(b)while (?:we|i|you|they|the kids|everyone) (?:sleep|are asleep|'re asleep)\#(e)|\#(b)(?:overnight|all night)\#(e)"#,
        ].joined(separator: "|"),
    )
    /// Someone may already be poisoned or an alarm is sounding: not this planning answer.
    private static let acute = re(
        #"\#(b)(?:headaches?|head (?:hurts|is (?:pounding|killing me|splitting))|pounding head|dizz\w*|nause\w*|vomit\w*|throwing up|threw up|throw(?:s|n)? up|passed out|faint\w*|unconscious|confus\w*|drowsy|sleepy|chest pain|can'?t breathe|short of breath|barely waking|(?:won'?t|can'?t|hard to|not) wak(?:e|ing)(?: up)?|slurr\w*|feel(?:s|ing)? (?:sick|ill|weird|woozy|weak))\#(e)"# +
            #"|\#(b)(?:alarm|detector)s?\#(e).{0,60}\#(b)(?:going off|went off|beeping|sounding|chirp\w*|is on|says|reads|reading|shows)\#(e)|\#(b)\d+ ?ppm\#(e)"#,
    )
    /// "Can I / Is it ok to <run|use…>": a request to do it. Only then does the answer start with "No." (reviewer C1).
    private static let askPermission = re(
        #"(?:^|[.?!]\s+)(?:can|could|may|should|shall) (?:i|we)\#(e) (?:still |just |safely )?(?:run|use|put|keep|leave|bring|start|operate|light|cook|warm|heat|idle|set up|plug)\#(e)"# +
            #"|\#(b)is it (?:ok|okay|safe|fine|alright|all right) (?:for (?:me|us) )?to\#(e)"#,
    )
    /// Risk questions ("can you die", "is it dangerous"), outdoor or either/or alternatives, installed appliances: a bare "No." would mislead.
    private static let noLeadIf = re(
        #"\#(b)(?:dangerous|danger|bad|die|dies|death|kill\w*|poison\w*|hurt|harm\w*|worr\w*|concern\w*|risk\w*|safer|unsafe|outside|outdoors?|out of|yard|driveway|instead|rather|or|not|away|move|moving|vent(?:ed)?|direct-vent|installed|flue|chimney|water heater|furnace|boiler)\#(e)"#,
    )

    // Common misspellings (dev2): "generater in the garge", "propain".
    private static let quotes = JsRegex("[’‘]")
    private static let generatorTypo = JsRegex(#"(?<![\p{L}])gen[ae]?rat[eoa]?rs?(?![\p{L}])"#, flags: "giu")
    private static let garageTypo = JsRegex(#"(?<![\p{L}])gar(?:ge|adge|rage)(?![\p{L}])"#, flags: "giu")
    private static let propaneTypo = JsRegex(#"(?<![\p{L}])propain(?![\p{L}])"#, flags: "giu")
    private static let keroseneTypo = JsRegex(#"(?<![\p{L}])kerosine(?![\p{L}])"#, flags: "giu")
    private static let engineSpace = JsRegex(#"(?<![\p{L}\p{N}_])(?:garages?|carports?|shed|enclosed|basement|crawl ?space)(?![\p{L}\p{N}_])"#, flags: "iu")

    /// A fuel-burning device in an enclosed or attached space (or near its openings), symptoms aside.
    private static func hazardContext(_ query: String) -> Bool {
        var q = quotes.replace(in: query, with: "'")
        q = generatorTypo.replace(in: q, with: "generator")
        q = garageTypo.replace(in: q, with: "garage")
        q = propaneTypo.replace(in: q, with: "propane")
        q = keroseneTypo.replace(in: q, with: "kerosene")
        if ovenHeat.containsMatch(in: q) || heatSpace.containsMatch(in: q) { return true }
        if placement.containsMatch(in: q) {
            let ft = statedFeet(q)
            if !(!ft.isEmpty && ft.allSatisfy { $0 >= 19.5 }) { return true }
        }
        if !space.containsMatch(in: q) { return false }
        if (storage.containsMatch(in: q) && !running.containsMatch(in: q)) || fiction.containsMatch(in: q) { return false }
        let device = device.containsMatch(in: q)
            || (heater.containsMatch(in: appliance.replace(in: q, with: " ")) && !installed.containsMatch(in: q))
            || (propaneStove.containsMatch(in: q) && space.containsMatch(in: kitchen.replace(in: q, with: " ")))
        return device || (engine.containsMatch(in: q) && engineSpace.containsMatch(in: q))
    }

    /// Distances the message states, in feet. Every one at 20 ft (6 m) or more: the generator is already placed right.
    private static func statedFeet(_ q: String) -> [Double] {
        feet.findAll(in: q).map { m in metres.containsMatch(in: m.groupValue(2)) ? JsNumber.parse(m.groupValue(1)) * 3.28 : JsNumber.parse(m.groupValue(1)) }
    }

    /// English question about running a fuel-burning device in an enclosed or attached space (no symptoms, no alarm).
    public static func isCoHazardQuestion(_ query: String) -> Bool {
        !acute.containsMatch(in: quotes.replace(in: query, with: "'")) && hazardContext(query)
    }

    public static let coHazardEn =
        "Carbon monoxide (CO) from a generator, a charcoal or gas grill, a camping stove or lantern, or a fuel-burning heater that isn't professionally installed and vented to the outside is a poison you can't see or smell, and it can kill in minutes. "
            + "Never run them inside a home, garage, carport, basement, shed, tent or camper, even with the doors or windows open: that is not enough ventilation. "
            + "Run a generator outside only, at least 20 feet (6 metres) from any door, window or vent, with the exhaust pointing away from buildings. "
            + "Never leave a car or other engine running in a garage, even with the door open, and never heat a home with a gas oven or stove. "
            + "Have a battery-powered CO alarm, but an alarm does not make it safe to run these indoors. "
            + "If anyone gets a headache, dizziness, weakness, tiredness, nausea, vomiting, chest pain or confusion, or passes out, get everyone out into fresh air right away, call emergency services, and don't go back inside until you're told it's safe."

    public static let coHazardSourcesEn =
        "Sources: CDC, Power Outage and Carbon Monoxide guidance; US CPSC, Portable Generator Hazards and Generators and Engine-Driven Tools; NHS, Carbon monoxide poisoning."

    /// src/routing/context.ts emergencyLine(false): the last line when the question names no listed country.
    private static let emergencyLineEn = "In an emergency, call your local emergency number (911 in the US, 112 in Europe)."

    public static func coHazardAnswer(_ query: String) -> String {
        let q = quotes.replace(in: query, with: "'")
        let lead = askPermission.containsMatch(in: q) && !noLeadIf.containsMatch(in: q) && !statedFeet(q).contains { $0 >= 19.5 } ? "No. " : ""
        return "\(lead)\(coHazardEn)\n\n\(coHazardSourcesEn)\n\n\(EmergencyNumbers.emergencyNumbersLine(query, pt: false) ?? emergencyLineEn)"
    }

    // Portuguese and Spanish (Labs, Oct 18): "Posso usar aquecedor a gás dentro da barraca?" went to the model with no
    // warning. The same logic as the English patterns above, with each language's words. Not ported from the TypeScript.
    // Left out on purpose: a plain "fogão a gás" / "cocina de gas" (the kitchen stove), "aquecedor a óleo" / "radiador de
    // aceite" (electric), a wood stove, "deixar/dejar o carro na garagem" (parking), a bare "tienda" (a shop) and a stated
    // distance with no generator named.

    /// One language's patterns, in the roles the English ones play in hazardContext, isCoHazardQuestion and coHazardAnswer.
    private struct Words {
        let device: JsRegex, heater: JsRegex, appliance: JsRegex, installed: JsRegex, ovenHeat: JsRegex, heatSpace: JsRegex
        let engine: JsRegex, engineSpace: JsRegex, placement: JsRegex, feet: JsRegex, space: JsRegex, storage: JsRegex
        let fiction: JsRegex, running: JsRegex, acute: JsRegex, askPermission: JsRegex, noLeadIf: JsRegex

        func statedFeet(_ q: String) -> [Double] {
            feet.findAll(in: q).map { m in
                let n = JsNumber.parse(m.groupValue(1).replacingOccurrences(of: ",", with: "."))
                return m.groupValue(2).lowercased().hasPrefix("m") ? n * 3.28 : n
            }
        }

        func hazard(_ query: String) -> Bool {
            let q = CoHazard.quotes.replace(in: query, with: "'")
            if acute.containsMatch(in: q) { return false }
            if ovenHeat.containsMatch(in: q) || heatSpace.containsMatch(in: q) { return true }
            if placement.containsMatch(in: q) {
                let ft = statedFeet(q)
                if !(!ft.isEmpty && ft.allSatisfy { $0 >= 19.5 }) { return true }
            }
            if !space.containsMatch(in: q) { return false }
            if (storage.containsMatch(in: q) && !running.containsMatch(in: q)) || fiction.containsMatch(in: q) { return false }
            let device = device.containsMatch(in: q) || (heater.containsMatch(in: appliance.replace(in: q, with: " ")) && !installed.containsMatch(in: q))
            return device || (engine.containsMatch(in: q) && engineSpace.containsMatch(in: q))
        }

        func lead(_ query: String, _ no: String) -> String {
            let q = CoHazard.quotes.replace(in: query, with: "'")
            return askPermission.containsMatch(in: q) && !noLeadIf.containsMatch(in: q) && !statedFeet(q).contains { $0 >= 19.5 } ? no : ""
        }
    }

    private static let pt = Words(
        device: re(
            [
                #"\#(b)geradore?s?\#(e)(?! (?:de (?:senhas?|n[úu]meros?|nomes?|c[óo]digos?|qr|textos?|imagens?|ideias?|conte[úu]do|sinais?|fun[çc][õo]es|m[úu]sicas?|arte|memes?|relat[óo]rios?|hash|pdfs?|ru[íi]do|ondas?|vapor|pulsos?)|solar(?:es)?|a bateria|de bateria|com bateria|ia)\#(e))"#,
                #"\#(b)carv[ãa]o\#(e)(?! (?:ativado|vegetal ativado|de desenho|para desenho|em p[óo]))(?<!desenho a carv[ãa]o)(?<!l[áa]pis de carv[ãa]o)(?<!filtro de carv[ãa]o)(?<!m[áa]scara de carv[ãa]o)(?<!sabonete de carv[ãa]o)"#,
                #"\#(b)(?:churrasqueiras?|braseiros?|fogareiros?|hibachis?)\#(e)"#,
                #"\#(b)(?:fog[ãa]o|fog[õo]es) (?:de camping|de acampamento|port[áa]til a g[áa]s|a querosene|a [áa]lcool)\#(e)"#,
                #"\#(b)(?:lampi[ãa]o|lampi[õo]es|lanternas?) (?:a|de) (?:g[áa]s|querosene|parafina|butano|propano|camping)\#(e)"#,
                #"\#(b)(?:motor(?:es)?|motosserras?|cortador(?:es)? de grama|ro[çc]adeiras?|sopradores?|lavadoras? de alta press[ãa]o|ferramentas?) (?:a|de) (?:gasolina|diesel|combust[íi]vel)\#(e)"#,
                #"\#(b)(?:ma[çc]aricos?|bocas? de fog[ãa]o) (?:a|de) (?:g[áa]s|propano|butano)\#(e)"#,
            ].joined(separator: "|"),
        ),
        heater: re(
            #"\#(b)(?:aquecedor(?:es)?|estufas?)(?: [\p{L}-]+)? (?:a|de) (?:g[áa]s|querosene|parafina|propano|butano|diesel|combust[íi]vel|camping|p[áa]tio)\#(e)"# +
                #"|\#(b)(?:aquecedor(?:es)?) (?:externos?|de exterior|catal[íi]ticos?)\#(e)"#,
        ),
        appliance: reAll(#"\#(b)(?:aquecedor(?:es)? (?:de [áa]gua|de passagem|central)|caldeiras?|boilers?|fornalhas?)\#(e)"#),
        installed: re(#"\#(b)(?:instalad\p{L}*|com (?:chamin[ée]|duto|exaust[ãa]o|sa[íi]da para fora)|exaust[ãa]o for[çc]ada)\#(e)"#),
        ovenHeat: re(
            #"\#(b)(?:forno|fog[ãa]o)(?: a g[áa]s)?\#(e).{0,40}\#(b)(?:para|pra) (?:aquecer|esquentar)\#(e)"# +
                #"|\#(b)(?:aquecer|aquecendo|esquentar|esquentando|aquecid\p{L}*)\#(e).{0,50}\#(b)(?:forno|fog[ãa]o)(?: a g[áa]s)?\#(e) (?:ligado|aceso|aberto|com a porta)"# +
                #"|\#(b)(?:forno|fog[ãa]o)\#(e) (?:ligado|aceso) com a porta (?:aberta|abaixada)"#,
        ),
        heatSpace: re(
            #"\#(b)(?:aquecer|esquentar)\#(e) (?:a |o |minha |meu |nossa |nosso )?(?:[\p{L}-]+ )?(?:barraca|quarto|sala|casa|apartamento|trailer|motorhome|cabana|chal[ée]|garagem|por[ãa]o|abrigo)\#(e).{0,40}\#(b)(?:fogareiros?|fornos?|fog[ãa]o|fog[õo]es|churrasqueiras?|aquecedor(?:es)?|lampi[ãa]o|lampi[õo]es|braseiros?|queimadores?)\#(e)"#,
        ),
        engine: re(
            #"\#(b)(?:carros?|caminhonetes?|caminh[ãa]o|ve[íi]culos?|motor(?:es)?|motos?|motocicletas?|cortador(?:es)? de grama|ro[çc]adeiras?|motosserras?|quadriciclos?|vans?|suvs?)\#(e).{0,40}\#(b)(?:ligad[oa]s?|funcionando|rodando|em ponto morto|em marcha lenta|esquentando|aquecendo|ligar|ligando)\#(e)"# +
                #"|\#(b)(?:ligar|ligando|esquentar|aquecer|dar partida)\#(e).{0,25}\#(b)(?:carros?|caminhonetes?|ve[íi]culos?|motor(?:es)?|motos?|motocicletas?|cortador(?:es)? de grama|suvs?)\#(e)"#,
        ),
        engineSpace: re(#"\#(b)(?:garage(?:m|ns)|abrigos?|por[ãa]o|dep[óo]sito|galp[ãa]o|fechad[oa]s?)\#(e)"#),
        placement: re(
            #"\#(b)geradore?s?\#(e).{0,80}\#(b)(?:a que dist[âa]ncia|qual dist[âa]ncia|dist[âa]ncia|longe o suficiente|suficiente|m[íi]nim[oa]|perto|ok|seguro|\d+(?:[.,]\d+)? ?(?:m|metros?|p[ée]s))\#(e).{0,60}\#(b)(?:janelas?|portas?|respiros?|entradas? de ar|ventila[çc][õo]es|ventila[çc][ãa]o)\#(e)"# +
                #"|\#(b)(?:a que dist[âa]ncia|qual dist[âa]ncia|dist[âa]ncia m[íi]nima|\d+(?:[.,]\d+)? ?(?:m|metros?|p[ée]s))\#(e).{0,60}\#(b)(?:janelas?|portas?|respiros?)\#(e).{0,60}\#(b)geradore?s?\#(e)"# +
                #"|\#(b)geradore?s?\#(e).{0,80}\#(b)(?:bem ao lado|ao lado|perto|pertinho|junto|embaixo|debaixo|encostado)\#(e) (?:d[aeo]s? |à |ao )?(?:minha |meu |nossa |nosso )?(?:[\p{L}-]+ ){0,2}(?:janelas?|portas?|respiros?)\#(e)"#,
        ),
        feet: JsRegex(#"(\d+(?:[.,]\d+)?) ?(m|metros?|p[ée]s|ft)(?![\p{L}])"#, flags: "giu"),
        space: re(
            [
                #"\#(b)(?:dentro|em|no|na|nos|nas|num|numa|para dentro)(?: d[aeo]s?| de)? (?:minha |meu |nossa |nosso |sua |seu |uma |um )?(?:[\p{L}-]+ ){0,2}(?:casa|quartos?|salas?|apartamentos?|cabanas?|chal[ée]s?|barracas?|trailers?|motorhomes?|garage(?:m|ns)|por[ãa]o|por[õo]es|dep[óo]sitos?|galp[ãa]o|ed[íi]culas?|vans?|kombis?|barcos?|cabines?|banheiros?|cozinhas?|celeiros?|est[áa]bulos?|oficinas?|abrigos?|quitinetes?|kitnets?|carros?|caminhonetes?|ve[íi]culos?)\#(e)"#,
                #"\#(b)garage(?:m|ns)\#(e)(?! (?:sale|band))"#,
                #"\#(b)(?:barracas?|trailers?|motorhomes?|por[ãa]o|por[õo]es|galp[ãa]o)\#(e)(?! de praia)"#,
                #"\#(b)(?:varanda|[áa]rea|lugar|local|ambiente|espa[çc]o|c[ôo]modo|quarto|sala|garagem) (?:fechad[oa]|coberto e fechado|sem ventila[çc][ãa]o)\#(e)"#,
                #"\#(b)(?:dentro|aqui dentro|l[áa] dentro|em ambiente fechado|em lugar fechado)\#(e)"#,
                #"\#(b)(?:enquanto (?:a gente|n[óo]s|eu|voc[êe]|eles|as crian[çc]as|todos?) dorm\p{L}*|durante a noite|a noite toda|de madrugada)\#(e)"#,
            ].joined(separator: "|"),
        ),
        storage: re(#"\#(b)(?:guardar|guardando|guardad[oa]|armazen\p{L}*|estocar|esvaziar|drenar|para o inverno|fora de temporada)\#(e)"#),
        fiction: re(#"\#(b)(?:romance|meu personagem|roteiro|conto|fic[çc][ãa]o|historicamente|hist[óo]ric[oa])\#(e)"#),
        running: re(#"\#(b)(?:usar|usando|ligar|ligando|ligad[oa]|acender|acendendo|aces[oa]|funcionar|funcionando|rodar|rodando|operar|dar partida|cozinhar)\#(e)"#),
        acute: re(
            #"\#(b)(?:dor(?:es)? de cabe[çc]a|cabe[çc]a (?:d[óo]i|doendo|latejando|explodindo)|tontu\p{L}*|tont[oa]s?|zonz[oa]s?|enjo\p{L}*|n[áa]usea\p{L}*|vomit\p{L}*|v[ôo]mito\p{L}*|desmai\p{L}*|inconscient\p{L}*|confus\p{L}*|sonol[êe]n\p{L}*|dor no peito|falta de ar|sem ar|n[ãa]o (?:consigo|consegue) respirar|n[ãa]o (?:acorda|consegue acordar)|dif[íi]cil de acordar|fala enrolada|passando mal|(?:me )?sentindo (?:mal|estranh\p{L}*|frac[oa]))\#(e)"# +
                #"|\#(b)(?:alarmes?|detector(?:es)?|sensor(?:es)?)\#(e).{0,60}\#(b)(?:tocando|tocou|disparou|disparando|apitando|apitou|bipando|soando|est[áa] ligado|mostra|marca|indica)\#(e)|\#(b)\d+ ?ppm\#(e)"#,
        ),
        askPermission: re(
            #"(?:^|[.?!]\s+)(?:eu |n[óo]s |a gente )?(?:posso|podemos|pode|d[áa] para|d[áa] pra|devo|devemos)(?: ainda| s[óo]| tranquilamente)? (?:usar|ligar|deixar|colocar|botar|p[ôo]r|levar|trazer|acender|cozinhar|aquecer|esquentar|rodar|operar|manter|montar)\#(e)"# +
                #"|\#(b)(?:[ée]|seria) (?:seguro|ok|tranquilo)\#(e)|\#(b)tudo bem\#(e)|\#(b)tem problema\#(e)"#,
        ),
        noLeadIf: re(
            #"\#(b)(?:perigos\p{L}*|perigo|faz mal|morr\p{L}*|morte|mata|matar|envenen\p{L}*|intoxic\p{L}*|risco\p{L}*|arriscad\p{L}*|mais seguro|preocup\p{L}*|fora|ao ar livre|quintal|em vez|ao inv[ée]s|ou|n[ãa]o|longe|tirar|mover|ventilad\p{L}*|exaust\p{L}*|chamin[ée]|instalad\p{L}*|aquecedor de [áa]gua|caldeira)\#(e)"#,
        ),
    )

    private static let es = Words(
        device: re(
            [
                #"\#(b)generador(?:es)?\#(e)(?! (?:de (?:contrase[ñn]as?|n[úu]meros?|nombres?|c[óo]digos?|qr|textos?|im[áa]genes?|ideas?|contenido|se[ñn]ales?|funciones|m[úu]sica|arte|memes?|informes?|hash|pdfs?|ruido|ondas?|vapor|pulsos?)|solar(?:es)?|a bater[íi]a|de bater[íi]a|con bater[íi]a|ia)\#(e))"#,
                #"\#(b)carb[óo]n\#(e)(?! (?:activado|vegetal activado|de dibujo|para dibujo|en polvo|mineral activado|monoxide|dioxide|fiber|fibre|footprint|copy))(?<!dibujo al carb[óo]n)(?<!l[áa]piz de carb[óo]n)(?<!filtro de carb[óo]n)(?<!mascarilla de carb[óo]n)(?<!jab[óo]n de carb[óo]n)(?<!monóxido de carb[óo]n)"#,
                #"\#(b)(?:barbacoas?|braseros?|hornillos?|infiernillos?|hibachis?)\#(e)"#,
                #"\#(b)(?:parrillas?|asadores?) (?:de|a) (?:carb[óo]n|gas|le[ñn]a|propano|butano)\#(e)"#,
                #"\#(b)(?:estufas?|cocinas?) (?:de camping|de campamento|port[áa]til(?:es)? de gas)\#(e)"#,
                #"\#(b)(?:farol(?:es)?|faroles?|l[áa]mparas?|linternas?) (?:de|a) (?:gas|queroseno|keroseno|parafina|butano|propano|camping)\#(e)"#,
                #"\#(b)(?:motor(?:es)?|motosierras?|cortac[ée]sped(?:es)?|podadoras?|sopladores?|hidrolavadoras?|herramientas?) (?:de|a) (?:gasolina|di[ée]sel|combustible)\#(e)"#,
                #"\#(b)(?:sopletes?|quemadores?) (?:de|a) (?:gas|propano|butano)\#(e)"#,
            ].joined(separator: "|"),
        ),
        heater: re(
            #"\#(b)(?:calentador(?:es)?|estufas?|calefactor(?:es)?)(?: [\p{L}-]+)? (?:de|a) (?:gas|queroseno|keroseno|parafina|propano|butano|di[ée]sel|combustible|camping|exterior|terraza)\#(e)"# +
                #"|\#(b)(?:calentador(?:es)?|estufas?) (?:catal[íi]tic[oa]s?|de exterior)\#(e)"#,
        ),
        appliance: reAll(#"\#(b)(?:calentador(?:es)? de agua|termos?|calderas?|calefacci[óo]n central|boilers?)\#(e)"#),
        installed: re(#"\#(b)(?:instalad\p{L}*|con (?:chimenea|ducto|conducto|salida al exterior|tiro)|tiro forzado|ventilad\p{L}* al exterior)\#(e)"#),
        ovenHeat: re(
            #"\#(b)(?:horno|estufa|cocina)(?: de gas)?\#(e).{0,40}\#(b)para (?:calentar|templar)\#(e)"# +
                #"|\#(b)(?:calentar|calentando|calentad\p{L}*)\#(e).{0,50}\#(b)(?:horno|estufa|cocina)(?: de gas)?\#(e) (?:encendid[oa]|prendid[oa]|abiert[oa]|con la puerta)"# +
                #"|\#(b)(?:horno|estufa)\#(e) (?:encendid[oa]|prendid[oa]) con la puerta (?:abierta|baja)"#,
        ),
        heatSpace: re(
            #"\#(b)calentar\#(e) (?:la |el |mi |nuestra |nuestro )?(?:[\p{L}-]+ )?(?:tienda|carpa|habitaci[óo]n|cuarto|sala|casa|apartamento|piso|caravana|autocaravana|caba[ñn]a|garaje|s[óo]tano|refugio)\#(e).{0,40}\#(b)(?:hornillos?|hornos?|estufas?|parrillas?|barbacoas?|calentador(?:es)?|faroles?|braseros?|quemadores?)\#(e)"#,
        ),
        engine: re(
            #"\#(b)(?:coches?|carros?|autos?|camionetas?|cami[óo]n|veh[íi]culos?|motor(?:es)?|motos?|motocicletas?|cortac[ée]sped(?:es)?|podadoras?|motosierras?|cuatrimotos?|furgonetas?|suvs?)\#(e).{0,40}\#(b)(?:encendid[oa]s?|prendid[oa]s?|funcionando|en marcha|al ralent[íi]|calentando|encender|arrancar)\#(e)"# +
                #"|\#(b)(?:encender|prender|calentar|arrancar)\#(e).{0,25}\#(b)(?:coches?|carros?|autos?|camionetas?|veh[íi]culos?|motor(?:es)?|motos?|motocicletas?|cortac[ée]sped(?:es)?|suvs?)\#(e)"#,
        ),
        engineSpace: re(#"\#(b)(?:garajes?|cocheras?|s[óo]tanos?|cobertizos?|cerrad[oa]s?)\#(e)"#),
        placement: re(
            #"\#(b)generador(?:es)?\#(e).{0,80}\#(b)(?:a qu[ée] distancia|qu[ée] distancia|distancia|suficientemente lejos|suficiente|m[íi]nim[oa]|cerca|bien|seguro|\d+(?:[.,]\d+)? ?(?:m|metros?|pies))\#(e).{0,60}\#(b)(?:ventanas?|puertas?|rejillas?|ventilaciones?|tomas? de aire)\#(e)"# +
                #"|\#(b)(?:a qu[ée] distancia|qu[ée] distancia|distancia m[íi]nima|\d+(?:[.,]\d+)? ?(?:m|metros?|pies))\#(e).{0,60}\#(b)(?:ventanas?|puertas?|rejillas?)\#(e).{0,60}\#(b)generador(?:es)?\#(e)"# +
                #"|\#(b)generador(?:es)?\#(e).{0,80}\#(b)(?:justo al lado|al lado|junto|cerca|pegado|debajo|bajo)\#(e) (?:de |a )?(?:la |el |mi |nuestra |nuestro |una |un )?(?:[\p{L}-]+ ){0,2}(?:ventanas?|puertas?|rejillas?)\#(e)"#,
        ),
        feet: JsRegex(#"(\d+(?:[.,]\d+)?) ?(m|metros?|pies|ft)(?![\p{L}])"#, flags: "giu"),
        space: re(
            [
                #"\#(b)(?:dentro|adentro|en|al)(?: de| del)? (?:la |el |los |las |mi |mis |nuestra |nuestro |una |un |tu |su )?(?:[\p{L}-]+ ){0,2}(?:casa|habitaci[óo]n|habitaciones|cuartos?|dormitorios?|sal[óo]n|salas?|apartamentos?|pisos?|caba[ñn]as?|carpas?|caravanas?|autocaravanas?|garajes?|cocheras?|s[óo]tanos?|cobertizos?|trasteros?|furgonetas?|camionetas?|barcos?|ba[ñn]os?|cocinas?|talleres?|graneros?|establos?|refugios?|coches?|carros?|autos?|veh[íi]culos?)\#(e)"#,
                #"\#(b)(?:garajes?|cocheras?|s[óo]tanos?|cobertizos?|carpas?|caravanas?|autocaravanas?|tienda de campa[ñn]a)\#(e)(?! (?:de playa))"#,
                #"\#(b)(?:porche|terraza|espacio|lugar|habitaci[óo]n|cuarto|[áa]rea|garaje) (?:cerrad[oa]|sin ventilaci[óo]n)\#(e)"#,
                #"\#(b)(?:dentro|adentro|aqu[íi] dentro|ah[íi] dentro|bajo techo|en interiores|en un interior)\#(e)"#,
                #"\#(b)(?:mientras (?:dormimos|duermo|duermen|duermes|los ni[ñn]os duermen|todos duermen)|durante la noche|toda la noche|de madrugada)\#(e)"#,
            ].joined(separator: "|"),
        ),
        storage: re(#"\#(b)(?:guardar|guardando|guardad[oa]|almacen\p{L}*|vaciar|drenar|para el invierno|fuera de temporada)\#(e)"#),
        fiction: re(#"\#(b)(?:novela|mi personaje|gui[óo]n|cuento|ficci[óo]n|hist[óo]ricamente|hist[óo]ric[oa])\#(e)"#),
        running: re(#"\#(b)(?:usar|usando|encender|encendiendo|encendid[oa]|prender|prendid[oa]|funcionar|funcionando|arrancar|operar|cocinar)\#(e)"#),
        acute: re(
            #"\#(b)(?:dolor(?:es)? de cabeza|(?:me )?duele la cabeza|mare\p{L}*|n[áa]usea\p{L}*|v[óo]mit\p{L}*|vomit\p{L}*|desmay\p{L}*|inconsciente\p{L}*|confundid\p{L}*|confusi[óo]n|somnolen\p{L}*|dolor (?:en el|de) pecho|falta de aire|no (?:puedo|puede) respirar|no (?:despierta|puede despertar)|dif[íi]cil de despertar|(?:me )?siento (?:mal|rar[oa]|d[ée]bil))\#(e)"# +
                #"|\#(b)(?:alarmas?|detector(?:es)?|sensor(?:es)?)\#(e).{0,60}\#(b)(?:sonando|son[óo]|suena|pitando|pita|se activ[óo]|se dispar[óo]|marca|muestra|indica|est[áa] encendid[oa])\#(e)|\#(b)\d+ ?ppm\#(e)"#,
        ),
        askPermission: re(
            #"(?:^|[.?!¿]\s*)(?:yo |nosotros )?(?:puedo|podemos|se puede|debo|debemos)(?: todav[íi]a| solo| s[óo]lo)? (?:usar|encender|prender|dejar|poner|meter|llevar|traer|cocinar|calentar|operar|mantener|montar|tener)\#(e)"# +
                #"|\#(b)(?:es|ser[íi]a) (?:seguro|aceptable)\#(e)|\#(b)(?:est[áa] bien|hay problema)\#(e)"#,
        ),
        noLeadIf: re(
            #"\#(b)(?:peligros\p{L}*|peligro|hace da[ñn]o|morir|muere|muerte|mata|matar|envenen\p{L}*|intoxic\p{L}*|riesgo\p{L}*|arriesgad\p{L}*|m[áa]s seguro|preocup\p{L}*|fuera|afuera|al aire libre|patio|jard[íi]n|en vez|en lugar|o|no|lejos|sacar|mover|ventilad\p{L}*|chimenea|instalad\p{L}*|calentador de agua|caldera)\#(e)"#,
        ),
    )

    // DRAFT translation of the reviewed EN text (Oct 18): needs r4to's review before it leaves Labs.
    public static let coHazardPt =
        "O monóxido de carbono (CO) de um gerador, de uma churrasqueira a carvão ou a gás, de um fogareiro ou lampião de camping, ou de um aquecedor a combustível que não foi instalado por um profissional com saída para o lado de fora é um veneno que não se vê nem tem cheiro, e pode matar em minutos. "
            + "Nunca use esses aparelhos dentro de casa, garagem, abrigo de carro, porão, depósito, barraca ou trailer, nem com as portas ou janelas abertas: isso não é ventilação suficiente. "
            + "Use o gerador só do lado de fora, a pelo menos 6 metros (20 pés) de qualquer porta, janela ou respiro, com o escapamento virado para longe das construções. "
            + "Nunca deixe um carro ou outro motor ligado na garagem, nem com o portão aberto, e nunca aqueça a casa com o forno ou o fogão a gás. "
            + "Tenha um alarme de CO a pilha, mas um alarme não torna seguro usar esses aparelhos em lugar fechado. "
            + "Se alguém tiver dor de cabeça, tontura, fraqueza, cansaço, náusea, vômito, dor no peito ou confusão, ou desmaiar, leve todos para o ar livre imediatamente, ligue para o serviço de emergência e não volte para dentro até que digam que é seguro."

    public static let coHazardSourcesPt =
        "Fontes (em inglês): CDC, Power Outage and Carbon Monoxide guidance; US CPSC, Portable Generator Hazards and Generators and Engine-Driven Tools; NHS, Carbon monoxide poisoning."

    /// src/routing/context.ts emergencyLine(true).
    private static let emergencyLinePt = "Em uma emergência, ligue para o serviço de emergência local (192 SAMU, 193 Bombeiros no Brasil, 112 na Europa, 911 nos EUA)."

    // DRAFT translation of the reviewed EN text (Oct 18): needs r4to's review before it leaves Labs.
    public static let coHazardEs =
        "El monóxido de carbono (CO) de un generador, una parrilla de carbón o de gas, una estufa o un farol de camping, o un calentador de combustible que no haya instalado un profesional con salida al exterior es un veneno que no se puede ver ni oler, y puede matar en minutos. "
            + "Nunca los uses dentro de una casa, garaje, cochera, sótano, cobertizo, tienda de campaña o caravana, ni siquiera con las puertas o ventanas abiertas: eso no es ventilación suficiente. "
            + "Usa un generador solo al aire libre, a por lo menos 6 metros (20 pies) de cualquier puerta, ventana o rejilla de ventilación, con el escape apuntando lejos de los edificios. "
            + "Nunca dejes un coche u otro motor encendido en un garaje, ni siquiera con la puerta abierta, y nunca calientes una casa con un horno o una estufa de gas. "
            + "Ten una alarma de CO a pilas, pero una alarma no hace que sea seguro usar estos aparatos en interiores. "
            + "Si alguien tiene dolor de cabeza, mareo, debilidad, cansancio, náuseas, vómitos, dolor en el pecho o confusión, o se desmaya, saca a todos al aire libre de inmediato, llama a los servicios de emergencia y no vuelvas a entrar hasta que te digan que es seguro."

    public static let coHazardSourcesEs =
        "Fuentes (en inglés): CDC, Power Outage and Carbon Monoxide guidance; US CPSC, Portable Generator Hazards and Generators and Engine-Driven Tools; NHS, Carbon monoxide poisoning."

    // The country table has no Spanish lines, so a Spanish answer always ends with this one.
    private static let emergencyLineEs = "En una emergencia, llama al número de emergencias local (911 en EE. UU., 112 en Europa)."

    /// The language of a Portuguese or Spanish CO planning question ("pt" or "es"), or nil. Both match (shared words like
    /// "dentro" with each one's device): the Spanish detector decides.
    public static func coHazardLanguage(_ query: String) -> String? {
        let p = pt.hazard(query)
        let s = es.hazard(query)
        if p && s { return QueryContext.isSpanishQuestion(query) ? "es" : "pt" }
        if p { return "pt" }
        if s { return "es" }
        return nil
    }

    /// The CO answer in the question's language: Portuguese or Spanish, from coHazardLanguage.
    public static func coHazardAnswer(_ query: String, language: String) -> String {
        switch language {
        case "pt": "\(pt.lead(query, "Não. "))\(coHazardPt)\n\n\(coHazardSourcesPt)\n\n\(EmergencyNumbers.emergencyNumbersLine(query, pt: true) ?? emergencyLinePt)"
        case "es": "\(es.lead(query, "No. "))\(coHazardEs)\n\n\(coHazardSourcesEs)\n\n\(emergencyLineEs)"
        default: coHazardAnswer(query)
        }
    }
}
