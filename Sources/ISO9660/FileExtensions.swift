import Foundation

extension URL {
    /// Returns the path of the file if the URL is a file URL, or `nil` if not.
    var filePath: String? {
        guard isFileURL else { return nil }

        if #available(macOS 13.0, *) {
            return self.path(percentEncoded: false)
        } else {
            return self.path
        }
    }

    /// Returns `true` if the URL points to an existing file
    var fileExists: Bool {
        guard let path = filePath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
