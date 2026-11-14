import Testing
@testable import BoarModels

/// SetupGuideTest.kt, case for case.
struct SetupGuideTests {
    typealias Page = SetupGuide.Page

    @Test func everyPageInALabsBuildWithoutAPinEndingOnReady() {
        #expect(SetupGuide.pages(experimental: true, pinSetBefore: false, notifications: true)
            == [.look, .files, .answers, .ask, .first, .pin, .notify, .privacy, .labs, .ready])
    }

    @Test func noNotificationsPageWhereThePlatformDoesNotAsk() {
        #expect(!SetupGuide.pages(experimental: true, pinSetBefore: false, notifications: false).contains(.notify))
    }

    @Test func noLabsPageInANormalBuild() {
        #expect(!SetupGuide.pages(experimental: false, pinSetBefore: false, notifications: true).contains(.labs))
    }

    @Test func noPinPageWhenAPinWasSetBeforeSetupStarted() {
        let pages = SetupGuide.pages(experimental: false, pinSetBefore: true, notifications: true)
        #expect(!pages.contains(.pin))
        #expect(pages.last == .ready)
    }

    @Test func aPinSetOnItsPageKeepsThePagesWhenSetupResumesInANewProcess() {
        // Saved on Privacy, with the PIN page in the list; the PIN is set now. Same pages, same page.
        let (pages, i) = SetupGuide.resume(experimental: true, pinPage: true, pinSetNow: true, notifications: true, page: "PRIVACY")
        #expect(pages.contains(.pin))
        #expect(pages[i] == .privacy)
    }

    @Test func resumingWithoutASavedPageStartsOnTheFirstOne() {
        let (pages, i) = SetupGuide.resume(experimental: false, pinPage: nil, pinSetNow: true, notifications: true, page: nil)
        #expect(!pages.contains(.pin))
        #expect(i == 0)
    }

    @Test func filesWaitForTheSearchModel() {
        #expect(!SetupGuide.canImport(searchModelPresent: false, indexBuilding: false, importing: false))
    }

    @Test func filesWaitWhileTheIndexBuilds() {
        #expect(!SetupGuide.canImport(searchModelPresent: true, indexBuilding: true, importing: false))
    }

    @Test func oneImportAtATime() {
        #expect(!SetupGuide.canImport(searchModelPresent: true, indexBuilding: false, importing: true))
    }

    @Test func filesGoInOnceTheSearchModelIsThereAndTheIndexIsNotBuilding() {
        #expect(SetupGuide.canImport(searchModelPresent: true, indexBuilding: false, importing: false))
    }

    @Test func pendingIsWhatTheLastFinishedImportDidNotInclude() {
        #expect(SetupGuide.pending(onDisk: ["a.txt", "b.pdf"], imported: ["a.txt"]) == ["b.pdf"])
        #expect(SetupGuide.pending(onDisk: ["a.txt"], imported: ["a.txt"]).isEmpty)
        // An import cut short (process killed) recorded nothing: everything is pending again.
        #expect(SetupGuide.pending(onDisk: ["a.txt", "b.pdf"], imported: []) == ["a.txt", "b.pdf"])
    }

    @Test func aSecondFileWithTheSameNameGetsANumber() {
        #expect(SetupGuide.freeName("notes.txt", taken: ["a.md"]) == "notes.txt")
        #expect(SetupGuide.freeName("notes.txt", taken: ["notes.txt"]) == "notes (2).txt")
        #expect(SetupGuide.freeName("notes.txt", taken: ["notes.txt", "notes (2).txt"]) == "notes (3).txt")
        #expect(SetupGuide.freeName("README", taken: ["README"]) == "README (2)")
    }
}
