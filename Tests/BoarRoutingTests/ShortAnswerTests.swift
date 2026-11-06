@testable import BoarRouting
import Testing

/// Health questions answer in Succinct even when Detailed is picked: which questions count (HealthQuestionTest.kt).
@Suite struct HealthQuestionTests {
    @Test func firstAidAndInjuriesAreHealth() {
        for q in [
            "When should a burn see a doctor?",
            "How do I treat a minor kitchen burn?",
            "My hiking partner is shivering, confused and slurring words",
            "I was stung by a box jellyfish while swimming. Should I rinse it?",
            "My child spilled boiling water on their arm. What do I do?",
            "Meu amigo está tremendo, confuso e com a fala enrolada",
            "Como estancar um sangramento no nariz?",
        ] { #expect(QueryContext.isHealthQuestion(q), "\(q)") }
    }

    @Test func researchQuestionsAreNot() {
        for q in [
            "What are the main sights to see in Lisbon?",
            "What is the difference between optimistic and zk-rollups?",
            "What is a seed phrase in a crypto wallet?",
            "Which countries are bigger than India by area?",
        ] { #expect(!QueryContext.isHealthQuestion(q), "\(q)") }
    }
}

/// Seed-phrase and wallet-backup questions answer in Succinct even when Detailed is picked (SeedPhraseQuestionTest.kt).
@Suite struct SeedPhraseQuestionTests {
    @Test func everyTriggerRoutes() {
        for q in [
            "What is a seed phrase in a crypto wallet?",
            "Where should I keep my seedphrase?",
            "How do I store a recovery phrase safely?",
            "Is a mnemonic phrase the same as a password?",
            "What happens if I lose the mnemonic for my wallet?",
            "Should I write down the 12 words of my wallet?",
            "Is it safe to photograph my 24-word bitcoin backup?",
            "Can someone steal my coins with my private key?",
            "What is the best way to do a wallet backup?",
            "How do I back up my wallet?",
            "How do I backup my hardware wallet?",
            "O que é uma frase semente?",
            "Onde guardo minha frase-semente?",
            "How do I store my seed-phrase?",
            "¿Dónde guardo mi frase semilla?",
            "¿Cómo hago una copia de seguridad de mi billetera?",
            "Perdí mi frase de recuperación",
            "¿Es seguro compartir la clave privada de mi billetera?",
            "Where do I keep my bitcoin private key?",
            "Onde guardar a frase de recuperação?",
            "Onde guardar a frase de recuperacao?",
            "Perdi as palavras de recuperação, e agora?",
            "Posso tirar foto das 12 palavras da minha carteira?",
            "As 24 palavras do bitcoin ficam no celular?",
            "O que é uma chave privada de bitcoin?",
            "Como fazer backup da carteira?",
        ] { #expect(QueryContext.isSeedPhraseQuestion(q), "\(q)") }
    }

    /// 12/24 words and "mnemonic" need a wallet or a coin nearby; an SSH or TLS private key is not a wallet's.
    @Test func walletsWithoutABackupOrSecretDoNot() {
        for q in [
            "How do I generate an SSH private key?",
            "Onde fica a chave privada do certificado TLS?",
            "What's a wallet?",
            "wallet for coins",
            "best leather wallet",
            "What is a hardware wallet?",
            "Write a poem in 12 words",
            "A mnemonic for the planets",
            "Resuma em 24 palavras",
            "Why do we have seasons?",
        ] { #expect(!QueryContext.isSeedPhraseQuestion(q), "\(q)") }
    }
}

/// ShortAnswerTest.kt.
@Suite struct ShortAnswerTests {
    @Test func healthAndSeedQuestionsUnderDetailedAnswerShort() {
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "How do I treat a minor kitchen burn?", previousQuestion: nil) == "health")
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "How should I store my seed phrase?", previousQuestion: nil) == "seed")
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "Why is Kyoto historically important?", previousQuestion: nil) == nil)
    }

    @Test func aFollowUpInAHealthOrSeedChatStaysShort() {
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "And for how long?", previousQuestion: "How do I treat a minor kitchen burn?") == "health")
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "What about a second copy?", previousQuestion: "How should I store my seed phrase?") == "seed")
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "And for how long?", previousQuestion: "Why is Kyoto historically important?") == nil)
    }

    @Test func aThankYouIsSmallTalkEvenAfterAHealthQuestion() {
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "thanks, that helps", previousQuestion: "How do I treat a minor kitchen burn?") == ShortAnswer.smallTalk)
        #expect(ShortAnswer.reason(chosenStyle: "detailed", question: "merci beaucoup", previousQuestion: nil) == ShortAnswer.smallTalk)
        #expect(ShortAnswer.isSmallTalk("thank you so much!"))
        #expect(!ShortAnswer.isSmallTalk("How do I say thank you in Thai?"))
    }

    @Test func otherStylesAreLeftAlone() {
        #expect(ShortAnswer.reason(chosenStyle: "succinct", question: "How do I treat a minor kitchen burn?", previousQuestion: nil) == nil)
        #expect(ShortAnswer.reason(chosenStyle: "personal", question: "And for how long?", previousQuestion: "How do I treat a minor kitchen burn?") == nil)
    }
}
