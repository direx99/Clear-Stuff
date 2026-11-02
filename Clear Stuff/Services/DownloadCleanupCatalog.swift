import Foundation

nonisolated enum DownloadCleanupCatalog {
    /// Inspect only direct Downloads children; personal folders are never traversed.
    static func reason(for url: URL) throws -> String? {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true else { throw ScanError.unsafePath }
        let ext = url.pathExtension.lowercased()
        if ["crdownload", "part", "download"].contains(ext) {
            return String(localized: "Possibly interrupted download — stop downloads first; removing it prevents resuming")
        }
        if values.isRegularFile == true && ["dmg", "pkg", "mpkg"].contains(ext) {
            return String(localized: "Downloaded installer — review whether it is still needed; this is not a corruption finding")
        }
        if values.isDirectory == true && ["pkg", "mpkg"].contains(ext) {
            return String(localized: "Downloaded installer package — quit installers first; remove only if no longer needed")
        }
        if ext == "zip", values.isRegularFile == true,
           try lacksZIPDirectoryFooter(url, size: values.fileSize ?? 0) {
            return String(localized: "Possibly truncated ZIP — standard archive directory footer is missing or incomplete; review before removing")
        }
        return nil
    }

    static func isMacOSInstaller(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return url.pathExtension.lowercased() == "app"
            && (name.hasPrefix("Install macOS ") || name.hasPrefix("Install OS X "))
    }

    /// A bounded structural check, not a full archive CRC or general corruption test.
    private static func lacksZIPDirectoryFooter(_ url: URL, size: Int) throws -> Bool {
        guard size >= 22 else { return true }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let start = max(0, size - 65_557)
        try handle.seek(toOffset: UInt64(start))
        let data = try handle.read(upToCount: 65_557) ?? Data()
        guard data.count >= 22 else { return true }
        for index in stride(from: data.count - 22, through: 0, by: -1) {
            guard data[index] == 0x50, data[index + 1] == 0x4b,
                  data[index + 2] == 0x05, data[index + 3] == 0x06 else { continue }
            let commentLength = Int(data[index + 20]) | (Int(data[index + 21]) << 8)
            if index + 22 + commentLength <= data.count { return false }
        }
        return true
    }
}
