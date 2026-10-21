import BoarCore
import Foundation
import Testing
@testable import BoarModels

@Suite struct PinEncryptionTests {
    @Test func aWrongPINCantUnwrapTheDataKeyButTheRightOneCan() {
        let salt = PinKeys.newSalt()
        let dek = PinKeys.newDataKey()
        let wrapped = PinKeys.wrap(dek, kek: PinKeys.derive(pin: "4821", salt: salt, iterations: 1000))
        #expect(PinKeys.unwrap(wrapped, kek: PinKeys.derive(pin: "4821", salt: salt, iterations: 1000)) == dek)
        #expect(PinKeys.unwrap(wrapped, kek: PinKeys.derive(pin: "4822", salt: salt, iterations: 1000)) == nil)
    }

    @Test func pinRulesAndTheWaitAfterWrongTries() {
        #expect(PinKeys.valid("1234")); #expect(PinKeys.valid("12345678"))
        #expect(!PinKeys.valid("123")); #expect(!PinKeys.valid("12a4")); #expect(!PinKeys.valid("123456789"))
        #expect(!PinKeys.valid("١٢٣٤")) // non-ASCII digits are not PIN digits
        #expect(PinKeys.backoffSeconds(4) == 0); #expect(PinKeys.backoffSeconds(5) == 30); #expect(PinKeys.backoffSeconds(6) == 60)
        #expect(PinKeys.backoffSeconds(12) == 3600); #expect(PinKeys.backoffSeconds(40) == 3600)
    }

    @Test func sealedTextRoundTripsEachSealDiffersAndTheWrongKeyShowsTheLock() {
        let c = AesTextCipher(key: PinKeys.newDataKey())
        let a = c.seal("Hello, boar"), b = c.seal("Hello, boar")
        #expect(AesTextCipher.isSealed(a)); #expect(a != b)
        #expect(c.open(a) == "Hello, boar")
        #expect(c.open("plain from before") == "plain from before")
        #expect(AesTextCipher(key: PinKeys.newDataKey()).open(a) == AesTextCipher.locked)
        #expect(PlainCipher().open(a) == AesTextCipher.locked)
        #expect(c.open("enc1:!!!not base64") == AesTextCipher.locked)
        #expect(c.open(c.seal("")) == "")
        #expect(c.open(c.seal("héllo 🐗 \n multi")) == "héllo 🐗 \n multi")
    }

    /// The format is the Android one: "enc1:" + base64(nonce12 | ciphertext | tag16), PBKDF2 with 210_000 rounds by default.
    @Test func theSealedFormatMatchesTheAndroidLayout() throws {
        let c = AesTextCipher(key: Data(repeating: 7, count: 32))
        let sealed = c.seal("abc")
        #expect(sealed.hasPrefix("enc1:"))
        let raw = try #require(Data(base64Encoded: String(sealed.dropFirst(5))))
        #expect(raw.count == 12 + 3 + 16)
        #expect(PinKeys.iterations == AppSettings.defaultPinIterations)
        #expect(PinKeys.derive(pin: "1234", salt: Data(repeating: 1, count: 16), iterations: 2).count == 32)
    }

    /// RFC 7914 §11 style check of the KDF itself: PBKDF2-HMAC-SHA256("passwd", "salt", 1, 32) is a published vector.
    @Test func pbkdf2MatchesAKnownVector() {
        let key = PinKeys.derive(pin: "password", salt: Data("salt".utf8), iterations: 1)
        #expect(key.map { String(format: "%02x", $0) }.joined() == "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b")
    }

    @Test func deviceKeySealIsBoundToTheStoredKey() throws {
        let store = InMemorySecretStore()
        let seal = DeviceKeySeal(store: store, account: "test-alias")
        let dek = PinKeys.newDataKey()
        let sealed = try seal.seal(dek)
        #expect(try seal.open(sealed) == dek)
        #expect(try DeviceKeySeal(store: store, account: "test-alias").open(sealed) == dek)
        #expect(try DeviceKeySeal(store: InMemorySecretStore(), account: "test-alias").open(sealed) == nil)
        try seal.destroy()
        #expect(try store.load(account: "test-alias") == nil)
        #expect(try seal.open(sealed) == nil)
    }

    /// Whole PIN flow without a chat store: wrap twice (PIN, device), open, and check what reaches a SQLite column.
    /// (Kotlin's `ChatStore` lives in BoarAnswer; its on-disk guarantee is the same one tested here on a plain table.)
    @Test func withAPINNothingATextColumnHoldsIsInTheClear() throws {
        let db = try SqliteDatabase.inMemory()
        try db.exec("CREATE TABLE chat_messages (id TEXT PRIMARY KEY, text TEXT NOT NULL)")
        func put(_ id: String, _ text: String, _ cipher: TextCipher) throws {
            try db.execute("INSERT OR REPLACE INTO chat_messages (id, text) VALUES (?, ?)", args: [.text(id), .text(cipher.seal(text))])
        }
        func reseal(_ from: TextCipher, _ to: TextCipher) throws {
            let rows = try db.query("SELECT id, text FROM chat_messages") { ($0.string(0)!, $0.string(1)!) }
            try db.transaction { for (id, t) in rows { try db.execute("UPDATE chat_messages SET text = ? WHERE id = ?", args: [.text(to.seal(from.open(t))), .text(id)]) } }
        }
        func raw() throws -> [String] { try db.query("SELECT text FROM chat_messages ORDER BY id") { $0.string(0)! } }
        func clear(_ c: TextCipher) throws -> [String] { try raw().map(c.open) }

        let plain = PlainCipher()
        try put("a1", "Where can I buy a SIM card?", plain)
        try put("a2", "At the airport.", plain)
        // Turn the PIN on: the old rows are re-sealed in place, new ones are sealed on write.
        let pin = "4821"
        let salt = PinKeys.newSalt()
        let dek = PinKeys.newDataKey()
        let deviceSeal = DeviceKeySeal(store: InMemorySecretStore(), account: "t")
        let stored = try deviceSeal.seal(PinKeys.wrap(dek, kek: PinKeys.derive(pin: pin, salt: salt, iterations: 1000)))
        let aes = AesTextCipher(key: dek)
        try reseal(plain, aes)
        try put("a3", "And a taxi?", aes)
        #expect(try raw().allSatisfy { !$0.contains("SIM") && !$0.contains("airport") && !$0.contains("taxi") && AesTextCipher.isSealed($0) })
        #expect(try clear(aes) == ["Where can I buy a SIM card?", "At the airport.", "And a taxi?"])
        // Without the key (the app before the PIN is entered) the text stays locked.
        #expect(try clear(plain).allSatisfy { $0 == AesTextCipher.locked })
        // Entering the PIN later: device seal, then PIN seal, give the same data key back.
        let pinSealed = try deviceSeal.open(stored)
        #expect(pinSealed.flatMap { PinKeys.unwrap($0, kek: PinKeys.derive(pin: pin, salt: salt, iterations: 1000)) } == dek)
        #expect(pinSealed.flatMap { PinKeys.unwrap($0, kek: PinKeys.derive(pin: "0000", salt: salt, iterations: 1000)) } == nil)
        // Turn it off: back to plain.
        try reseal(aes, plain)
        #expect(try raw() == ["Where can I buy a SIM card?", "At the airport.", "And a taxi?"])
    }
}
