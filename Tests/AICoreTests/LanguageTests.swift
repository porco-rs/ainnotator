import AICore
import Testing

@Test func germanIsChosenOnlyWhenTheFirstPreferenceIsGerman() {
    #expect(Language.choose(from: ["de"]) == .de)
    #expect(Language.choose(from: ["de-DE", "en"]) == .de)
    #expect(Language.choose(from: ["de_AT"]) == .de)
    #expect(Language.choose(from: ["en", "de"]) == .en)
}

@Test func everythingElseIsEnglish() {
    #expect(Language.choose(from: ["en"]) == .en)
    #expect(Language.choose(from: ["fr"]) == .en)
    #expect(Language.choose(from: ["fr", "de"]) == .en)
    #expect(Language.choose(from: []) == .en)
}
