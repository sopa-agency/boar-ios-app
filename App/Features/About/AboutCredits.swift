import BoarModels
import SwiftUI

/// The open work BOAR is built on, for About's credits (android AboutCredits.kt and LabHooks' extra list): the
/// libraries in the app, what BOAR reads and where its models come from, the Boar Labs data and code, then every
/// model and pack in the catalog with its own license.
enum AboutCredits {
    struct Credit: Hashable {
        let name: String
        let license: String
    }

    /// The libraries in the app (Android's list without PdfBox: iOS reads PDFs with Apple's PDFKit).
    static let libraries = [
        Credit(name: "llama.cpp / ggml", license: "MIT"),
        Credit(name: "SQLite", license: "public domain"),
        Credit(name: "Zstandard", license: "BSD"),
        Credit(name: "AndroidLM (knowledge-pack search design)", license: "Apache-2.0"),
        Credit(name: "Baloo 2 and Lexend fonts", license: "SIL OFL 1.1"),
    ]

    /// What BOAR reads and where its models come from; Hugging Face hosts, it isn't a license.
    static var sources: [Credit] {
        [
            Credit(name: String(localized: "Wikipedia (the built-in library and the Vital Articles pack)"), license: "CC BY-SA 4.0"),
            Credit(name: String(localized: "Hugging Face (where BOAR's models download from)"), license: "—"),
        ]
    }

    /// The Boar Labs code and data this build ships (Android's list, without the engines and models iOS doesn't
    /// have: stable-diffusion.cpp, Big Boar, Boar Wisp).
    static let labs = [
        Credit(name: "r4to's calculator, BOAR R&D (Boar Calculator)", license: "MIT"),
        Credit(name: "r4to's travel distance, BOAR R&D (Boar Distance)", license: "MIT"),
        Credit(name: "GeoNames cities15000 (Boar Distance)", license: "CC BY 4.0"),
        Credit(name: "r4to's offline facts, BOAR R&D (Boar Facts)", license: "MIT"),
        Credit(name: "Wikidata facts table (Boar Facts)", license: "CC0"),
        Credit(name: "r4to's verdict guard, BOAR R&D (Boar Guard)", license: "MIT"),
        Credit(name: "r4to's CO hazard check, BOAR R&D (Boar Cohazard)", license: "MIT"),
    ]

    /// The catalog's models and packs, each with its license; hidden ones (no longer offered) aren't credited.
    static let models: [Credit] = {
        guard let catalog = try? Catalog.bundled() else { return [] }
        var seen = Set<Credit>()
        return catalog.models
            .filter { !$0.hidden && !$0.license.isEmpty && !$0.license.hasPrefix("Unknown") }
            .map { Credit(name: $0.label, license: $0.license) }
            .filter { seen.insert($0).inserted }
    }()

    static var all: [Credit] {
        libraries + sources + (LabsBuild.experimental ? labs : []) + models
    }
}
