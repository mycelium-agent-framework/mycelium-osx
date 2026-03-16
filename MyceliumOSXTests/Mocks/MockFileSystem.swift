import Foundation
@testable import MyceliumOSX

/// In-memory file system for testing.
final class MockFileSystem: FileSystemAccessing {
    var files: [String: Data] = [:]
    var directories: Set<String> = []

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let prefix = url.path + "/"
        var results: Set<String> = []
        for key in files.keys {
            if key.hasPrefix(prefix) {
                let remainder = String(key.dropFirst(prefix.count))
                if let firstSlash = remainder.firstIndex(of: "/") {
                    results.insert(String(remainder[..<firstSlash]))
                } else {
                    results.insert(remainder)
                }
            }
        }
        for dir in directories {
            if dir.hasPrefix(prefix) {
                let remainder = String(dir.dropFirst(prefix.count))
                if !remainder.contains("/") && !remainder.isEmpty {
                    results.insert(remainder)
                }
            }
        }
        return results.map { url.appendingPathComponent($0) }
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func read(at url: URL) -> Data? {
        files[url.path]
    }

    func write(data: Data, to url: URL) throws {
        files[url.path] = data
    }

    func readString(at url: URL) -> String? {
        guard let data = files[url.path] else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helpers

    func addFile(_ path: String, content: String) {
        files[path] = Data(content.utf8)
    }

    func addDirectory(_ path: String) {
        directories.insert(path)
    }
}
