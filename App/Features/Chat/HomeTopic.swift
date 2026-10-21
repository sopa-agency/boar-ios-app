import SwiftUI

/// A topic row on the home screen: an outline symbol, a short name, and the questions it offers.
///
/// Every question is answered by an article in the built-in library (App/Resources/Data/corpus.json, on every iPhone;
/// the Ethereum, smart contract, proof of stake, Bitcoin, DeFi and Vitalik Buterin intros were added for these):
/// checked 2026-10-17 that the article ranks first for the question in a BM25 search over that library and that its
/// intro holds the facts the answer needs. The models' answers to them are not yet checked.
struct HomeTopic: Identifiable {
    let name: LocalizedStringKey
    let symbol: String
    let color: Color
    let questions: [String]
    let id: String

    static var all: [HomeTopic] { [
        HomeTopic(name: "Ethereum and tech", symbol: "cpu", color: .blue, questions: [
            "What is Ethereum, and who started it?",
            "What changed when Ethereum moved to proof of stake?",
            "What can a smart contract do?",
            "Why can't anyone quietly change a blockchain?",
            "Why does Bitcoin mining use so much electricity?",
            "What is DeFi, and what are its risks?",
        ], id: "tech"),
        HomeTopic(name: "Space and physics", symbol: "sparkles", color: .indigo, questions: [
            "Could anything escape from a black hole?",
            "What are Lagrange points, and why do telescopes park there?",
            "How does fusion power the stars?",
            "What is quantum entanglement, in plain words?",
        ], id: "space"),
        HomeTopic(name: "Life and health", symbol: "heart", color: .red, questions: [
            "How do the bacteria in your gut affect your health?",
            "How do bacteria use CRISPR to fight viruses?",
            "How do neurons send signals?",
            "What are superbugs, and why do they appear?",
        ], id: "life"),
        HomeTopic(name: "Earth and nature", symbol: "leaf", color: .green, questions: [
            "Can you really see the Great Barrier Reef from space?",
            "How big is the Amazon rainforest, and who shares it?",
            "How long have Earth's tectonic plates been moving?",
            "What is driving today's climate change?",
        ], id: "earth"),
        HomeTopic(name: "History", symbol: "building.columns", color: .brown, questions: [
            "What travelled along the Silk Road?",
            "How far did the Mongol Empire stretch?",
            "Why did Rome lose control of its western provinces?",
            "What sparked the Renaissance?",
            "Why was the Cold War called cold?",
        ], id: "history"),
        HomeTopic(name: "Ideas and money", symbol: "lightbulb", color: .orange, questions: [
            "What is game theory used for?",
            "What causes inflation?",
            "Has any country tried universal basic income?",
            "How does public-key cryptography keep a message secret?",
        ], id: "ideas"),
    ] }
}
