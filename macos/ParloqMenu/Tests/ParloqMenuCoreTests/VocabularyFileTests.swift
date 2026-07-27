import Foundation
import ParloqMenuCore
import Testing

@Test func vocabularyPreparationCreatesAStarterWithoutReplacingEdits() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("vocab.txt").path

    let fileURL = try VocabularyFile.prepare(atPath: path)
    #expect(fileURL.path == path)
    #expect(
        try String(contentsOf: fileURL, encoding: .utf8)
            == VocabularyFile.starter
    )

    try "parlo = Parloq\n".write(
        to: fileURL,
        atomically: true,
        encoding: .utf8
    )
    _ = try VocabularyFile.prepare(atPath: path)
    #expect(
        try String(contentsOf: fileURL, encoding: .utf8)
            == "parlo = Parloq\n"
    )
}

@Test func vocabularyPreparationRejectsRelativePaths() {
    #expect(throws: VocabularyFileError.self) {
        try VocabularyFile.prepare(atPath: "relative/vocab.txt")
    }
}
