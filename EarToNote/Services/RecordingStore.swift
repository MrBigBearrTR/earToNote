import Foundation

/// Location of the audio files. Recordings live in Application Support so they stay on the device
/// (and in the user's device backup) but are not visible in the Files app.
enum RecordingStore {
    static var directory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileName(for meetingID: UUID) -> String {
        "\(meetingID.uuidString).m4a"
    }

    static func url(forFileName name: String) -> URL {
        directory.appending(path: name, directoryHint: .notDirectory)
    }

    static func fileExists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forFileName: name).path)
    }

    static func deleteFile(named name: String) {
        try? FileManager.default.removeItem(at: url(forFileName: name))
    }

    static func totalSize() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return files.reduce(into: Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: Set(keys)).fileSize) ?? 0
            total += Int64(size)
        }
    }
}
