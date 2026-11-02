import Foundation
import CryptoKit
import Darwin

/// File-system work runs outside the main actor. Tree sizing reads metadata; download checks read only a bounded ZIP footer.
nonisolated struct CleanupScanner: Sendable {
    let now: Date
    let maximumEntries: Int
    init(now: Date = .now, maximumEntries: Int = 200_000) {
        self.now = now
        self.maximumEntries = maximumEntries
    }

    func scan(root: URL, category: CleanupCategory, excluded: Set<String> = []) throws -> ScanResult {
        try Task.checkCancellation()
        guard root.standardizedFileURL == root.resolvingSymlinksInPath().standardizedFileURL else {
            throw ScanError.unsafePath
        }
        let fm = FileManager.default
        var result = ScanResult()
        let entries: [URL]
        if category == .browsers {
            entries = try BrowserCacheCatalog.candidates(root: root, excluded: excluded, issues: &result.issues)
        } else {
            entries = try fm.contentsOfDirectory(at: Self.canonicalURL(root), includingPropertiesForKeys: nil)
        }
        var visited = 0
        for entry in entries.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            if excluded.contains(entry.path) { continue }
            do {
                if category == .downloads {
                    guard try DownloadCleanupCatalog.reason(for: entry) != nil else { continue }
                    result.items.append(try inspect(entry, root: root, category: category, visited: &visited))
                } else if category == .installers {
                    guard DownloadCleanupCatalog.isMacOSInstaller(entry) else { continue }
                    result.items.append(try inspect(entry, root: root, category: category, visited: &visited))
                } else if category == .logs {
                    try collectLogs(entry, root: root, excluded: excluded, result: &result, visited: &visited, depth: 0)
                } else if category == .caches && ["Google", "BraveSoftware", "Opera Software"].contains(entry.lastPathComponent) {
                    // Separate browser cache folders from other apps sharing the vendor directory.
                    guard entry.standardizedFileURL == entry.resolvingSymlinksInPath().standardizedFileURL else { throw ScanError.unsafePath }
                    for child in try fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil) {
                        if excluded.contains(child.path) { continue }
                        do { result.items.append(try inspect(child, root: root, category: category, visited: &visited)) }
                        catch is CancellationError { throw CancellationError() }
                        catch { result.issues.append(ScanIssue(path: child.path, error: error)) }
                    }
                } else {
                    let item = try inspect(entry, root: root, category: category, visited: &visited)
                    result.items.append(item)
                }
            } catch is CancellationError { throw CancellationError() }
            catch {
                result.issues.append(ScanIssue(path: entry.path, error: error))
                if visited > maximumEntries { break }
            }
        }
        result.items.sort { $0.bytes > $1.bytes }
        return result
    }

    func inspect(_ url: URL, root: URL, category: CleanupCategory) throws -> CleanupItem {
        var visited = 0
        return try inspect(url, root: root, category: category, visited: &visited)
    }

    private func inspect(_ url: URL, root: URL, category: CleanupCategory, visited: inout Int) throws -> CleanupItem {
        guard url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw ScanError.unsafePath
        }
        let url = try Self.canonicalURL(url)
        let canonicalRoot = try Self.canonicalURL(root)
        guard url.path.hasPrefix(canonicalRoot.path + "/"), url != canonicalRoot else {
            throw ScanError.unsafePath
        }
        var downloadReason: String?
        if category == .downloads || category == .installers {
            guard url.deletingLastPathComponent() == canonicalRoot else { throw ScanError.unsafePath }
            if category == .downloads {
                downloadReason = try DownloadCleanupCatalog.reason(for: url)
                guard downloadReason != nil else { throw ScanError.unsafePath }
            } else {
                guard DownloadCleanupCatalog.isMacOSInstaller(url),
                      try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw ScanError.unsafePath }
            }
        }
        var summary = TreeSummary()
        try measure(url, summary: &summary, visited: &visited, depth: 0)
        let stamp = try Self.stamp(url)
        let modified = summary.newest
        if category == .browsers {
            let relative = String(url.path.dropFirst(canonicalRoot.path.count + 1))
            guard BrowserCacheCatalog.isProfileCache(relativePath: relative) else { throw ScanError.unsafePath }
        }
        let reason: String
        switch category {
        case .caches: reason = String(localized: "App cache — close the app first; cached data may need to download again")
        case .browsers: reason = String(localized: "Browser cache — close the browser first; websites will reload cached files")
        case .developer: reason = String(localized: "Xcode generated data — close Xcode and stop builds; data will rebuild")
        case .logs: reason = String(localized: "Log or report — troubleshooting history will be removed")
        case .systemCaches: reason = String(localized: "Shared cache owned by your account — close affected apps first; data may need to rebuild")
        case .downloads:
            guard let downloadReason else { throw ScanError.unsafePath }
            reason = downloadReason
        case .installers: reason = String(localized: "Saved macOS installer — quit installers and finish updates first; remove only if no longer needed")
        }
        return CleanupItem(url: url, root: root, category: category, bytes: summary.bytes,
                           modified: modified, stamp: stamp, signature: summary.digest,
                           canClean: true, reason: reason, fileCount: summary.count,
                           relativePath: String(url.path.dropFirst(canonicalRoot.path.count + 1)))
    }

    private func collectLogs(_ url: URL, root: URL, excluded: Set<String>, result: inout ScanResult,
                             visited: inout Int, depth: Int) throws {
        try Task.checkCancellation()
        guard !excluded.contains(url.path) else { return }
        guard depth < 64 else { throw ScanError.limit }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else { throw ScanError.unsafePath }
        if values.isDirectory == true {
            visited += 1
            guard visited <= maximumEntries else { throw ScanError.limit }
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) {
                do {
                    try collectLogs(child, root: root, excluded: excluded, result: &result, visited: &visited, depth: depth + 1)
                } catch is CancellationError { throw CancellationError() }
                catch {
                    result.issues.append(ScanIssue(path: child.path, error: error))
                    if visited > maximumEntries { throw ScanError.limit }
                }
            }
        } else {
            result.items.append(try inspect(url, root: root, category: .logs, visited: &visited))
        }
    }

    private func measure(_ url: URL, summary: inout TreeSummary, visited: inout Int, depth: Int) throws {
        try Task.checkCancellation()
        visited += 1
        guard visited <= maximumEntries, depth < 64 else { throw ScanError.limit }
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .volumeIdentifierKey])
        let stamp = try Self.stamp(url)
        summary.hash.update(data: Data("\(url.path):\(stamp)".utf8))
        summary.newest = max(summary.newest, Date(timeIntervalSince1970: Double(stamp.modifiedSeconds)))
        if values.isSymbolicLink == true {
            return
        }
        if values.isDirectory == true {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            for child in children.sorted(by: { $0.path < $1.path }) {
                let childStamp = try Self.stamp(child)
                guard childStamp.device == stamp.device else { throw ScanError.unsafePath }
                try measure(child, summary: &summary, visited: &visited, depth: depth + 1)
            }
        } else if values.isRegularFile == true {
            summary.count += 1
            // Hard links are counted once within this candidate. APFS clone sharing remains an estimate.
            if summary.inodes.insert("\(stamp.device):\(stamp.inode)").inserted {
                summary.bytes += max(0, stamp.size)
            }
        } else {
            throw ScanError.unsafePath
        }
    }

    /// Foundation preserves macOS /var aliases while enumeration returns /private/var.
    static func canonicalURL(_ url: URL) throws -> URL {
        guard let resolved = realpath(url.path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    static func stamp(_ url: URL) throws -> FileStamp {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard value.st_uid == getuid() else { throw ScanError.otherOwner }
        return FileStamp(device: value.st_dev, inode: value.st_ino, size: value.st_size,
                         modifiedSeconds: Int64(value.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec),
                         changedSeconds: Int64(value.st_ctimespec.tv_sec), changedNanoseconds: Int64(value.st_ctimespec.tv_nsec))
    }

    private struct TreeSummary {
        var bytes: Int64 = 0
        var count = 0
        var newest = Date.distantPast
        var inodes: Set<String> = []
        var hash = SHA256()
        var digest: String { hash.finalize().map { String(format: "%02x", $0) }.joined() }
    }
}

nonisolated enum ScanError: LocalizedError {
    case unsafePath, limit, changed, busy, otherOwner
    var errorDescription: String? {
        switch self {
        case .unsafePath: String(localized: "Skipped a link, special file, unsupported item, or location outside the scan folder.")
        case .otherOwner: String(localized: "Owned by another account or macOS. Administrator-managed cleanup is required; this app does not modify system-owned files.")
        case .limit: String(localized: "Scan limit reached. Results are incomplete; scan a smaller folder.")
        case .changed: String(localized: "Item changed after scanning. Scan again before cleaning.")
        case .busy: String(localized: "Close Xcode, Simulator, and developer build processes before cleaning.")
        }
    }
}
