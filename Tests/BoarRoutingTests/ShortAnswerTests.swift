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

    /// The F3 checks: "My CO alarm keeps chirping every minute" ran a Detailed answer. Card or not, it is kept short.
    @Test func carbonMonoxideNamedIsAHealthQuestionKeptShortCardOrNot() {
        for q in ["My CO alarm keeps chirping every minute", "my CO detector says error", "Is 50 ppm of carbon monoxide dangerous?",
                  "O detector de monóxido mostra erro"] {
            #expect(ShortAnswer.reason(chosenStyle: "detailed", question: q, previousQuestion: nil) == "health", "\(q)")
        }
        #expect(!QueryContext.isHealthQuestion("CO2 levels in the office are high"))
        #expect(!QueryContext.isHealthQuestion("Who is the CO of the company?"))
    }

    /// "How much paracetamol (acetaminophen) can an adult take in a day?" had none of the health words.
    @Test func aMedicinesDoseIsAHealthQuestionKeptShort() {
        for q in ["How much paracetamol (acetaminophen) can an adult take in a day?", "ibuprofen dose for adults", "Is 1000 mg of Tylenol too much?",
                  "Quantos mg de dipirona posso tomar?", "Qual a dosagem máxima de paracetamol por dia?", "¿Cuánto ibuprofeno puedo tomar al día?",
                  "What is the maximum daily dose of aspirin?"] {
            #expect(QueryContext.isHealthQuestion(q), "\(q)")
            #expect(ShortAnswer.reason(chosenStyle: "detailed", question: q, previousQuestion: nil) == "health", "\(q)")
        }
        // A medicine named without a dose word, or a dose word without a medicine, is not this rule.
        for q in ["Who invented aspirin?", "How much does a car cost?", "What is the history of ibuprofen?"] {
            #expect(!QueryContext.isHealthQuestion(q), "\(q)")
        }
    }

    /// BenchModelsTest.kt over Android's health topic (topics/health.v1.json; the bench isn't on iOS, so its queries are
    /// here): every question but the CO one, which the acute card answers, is kept short.
    @Test func everyBenchHealthQuestionIsKeptShort() {
        for q in ["I just spilled boiling water on my hand. What should I do right now?",
                  "I got stung by a bee on my arm. How do I treat it, and when is it an emergency?",
                  "My 2-year-old has a fever of 39 °C. What should I do, and when should we see a doctor?",
                  "How much paracetamol (acetaminophen) can an adult take in a day?"] {
            #expect(ShortAnswer.reason(chosenStyle: "detailed", question: q, previousQuestion: nil) == "health", "\(q)")
        }
    }

    /// "hows health blood test? summarize" in Personal Files wasn't health. Personal Files is kept short for health too.
    @Test func labResultsAreHealthAndPersonalFilesKeepsThemShort() {
        for q in ["hows health blood test? summarize", "summarize my blood test", "resuma meu exame de sangue", "what does my LDL mean?", "meu colesterol está alto?"] {
            #expect(QueryContext.isHealthQuestion(q), "\(q)")
        }
        #expect(ShortAnswer.reason(chosenStyle: "personal", question: "summarize my blood test", previousQuestion: nil) == "health")
        #expect(ShortAnswer.reason(chosenStyle: "personal", question: "what did my landlord say?", previousQuestion: nil) == nil)
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
        // Golden change (Android aa9b0cc5): Personal Files is kept short for health too, with its own prompt; not for anything else.
        #expect(ShortAnswer.reason(chosenStyle: "personal", question: "And for how long?", previousQuestion: "How do I treat a minor kitchen burn?") == "health")
        #expect(ShortAnswer.reason(chosenStyle: "personal", question: "How should I store my seed phrase?", previousQuestion: nil) == nil)
    }
}
