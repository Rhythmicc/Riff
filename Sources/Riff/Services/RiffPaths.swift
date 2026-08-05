import Foundation

enum RiffPaths {
    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Riff", isDirectory: true)
    }
}
