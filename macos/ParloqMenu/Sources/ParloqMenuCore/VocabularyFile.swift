import Foundation

public enum VocabularyFileError: LocalizedError {
    case invalidPath

    public var errorDescription: String? {
        switch self {
        case .invalidPath:
            return "Vocabulary path must be absolute"
        }
    }
}

public enum VocabularyFile {
    public static let starter = """
        # One whole-word correction per line:
        # what the recognizer heard = what you want

        """

    public static func prepare(
        atPath path: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard path.hasPrefix("/") else {
            throw VocabularyFileError.invalidPath
        }
        let fileURL = URL(fileURLWithPath: path)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: path) {
            try starter.write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
        }
        return fileURL
    }
}
