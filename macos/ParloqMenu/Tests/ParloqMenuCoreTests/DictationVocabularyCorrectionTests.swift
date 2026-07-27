import Foundation
import ParloqMenuCore
import Testing

@Test func vocabularyCorrectionNormalizesAndEncodes() throws {
    let correction = try #require(DictationVocabularyCorrection(
        heard: "  par   lock ",
        replacement: " Parloq "
    ))
    #expect(correction.heard == "par lock")
    #expect(correction.replacement == "Parloq")

    let request = DictateRequest(vocabularyCorrection: correction)
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(request)
        ) as? [String: Any]
    )
    #expect(object["command"] as? String == "configure")
    let settings = try #require(object["settings"] as? [String: Any])
    let encoded = try #require(
        settings["vocabulary_correction"] as? [String: String]
    )
    #expect(encoded == [
        "heard": "par lock",
        "replacement": "Parloq",
    ])
    #expect(settings["device"] == nil)
    #expect(settings["save_recordings"] == nil)
}

@Test func vocabularyCorrectionRejectsUnsafeRules() {
    #expect(DictationVocabularyCorrection(
        heard: "",
        replacement: "Parloq"
    ) == nil)
    #expect(DictationVocabularyCorrection(
        heard: "same",
        replacement: "same"
    ) == nil)
    #expect(DictationVocabularyCorrection(
        heard: "two\nlines",
        replacement: "one line"
    ) == nil)
    #expect(DictationVocabularyCorrection(
        heard: "left=right",
        replacement: "value"
    ) == nil)
    #expect(DictationVocabularyCorrection(
        heard: String(repeating: "a", count: 201),
        replacement: "short"
    ) == nil)
}
