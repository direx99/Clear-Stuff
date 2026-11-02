import Foundation

nonisolated enum CleanupCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case caches, browsers, developer, logs, systemCaches, downloads, installers
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .caches: "App Caches"
        case .browsers: "Browser Caches"
        case .developer: "Developer Data"
        case .logs: "Logs & Reports"
        case .systemCaches: "System Caches"
        case .downloads: "Download Cleanup"
        case .installers: "macOS Installers"
        }
    }
    var icon: String {
        switch self {
        case .caches: "externaldrive"
        case .browsers: "globe"
        case .developer: "hammer"
        case .logs: "doc.text"
        case .systemCaches: "gearshape.2"
        case .downloads: "arrow.down.circle"
        case .installers: "desktopcomputer.and.arrow.down"
        }
    }
    var relativePath: String {
        switch self {
        case .caches: "Library/Caches"
        case .browsers: "Library/Application Support"
        case .developer: "Library/Developer/Xcode/DerivedData"
        case .logs: "Library/Logs"
        case .systemCaches: "/Library/Caches"
        case .downloads: "Downloads"
        case .installers: "/Applications"
        }
    }
    var consequence: LocalizedStringResource {
        switch self {
        case .caches: "Select only caches you recognize. Close the affected apps first. Cached or offline data may be lost and downloads may restart."
        case .browsers: "Close browsers first. Only cache folders are listed; passwords, bookmarks, history, cookies, and extensions are preserved. Also connect App Caches for Safari and Firefox caches."
        case .developer: "All DerivedData items can be moved to Trash. Close Xcode, Simulator, and all builds first. The next build will rebuild and reindex."
        case .logs: "All logs and reports can be selected. Removing them loses historical troubleshooting evidence."
        case .systemCaches: "Shared caches in /Library/Caches. Only items owned by your account can be cleaned. System-owned and inaccessible items are reported as skipped."
        case .downloads: "Partial downloads, possibly truncated ZIPs, and installer packages are listed for review. Stop downloads and installers first. Removing partial files prevents resuming them."
        case .installers: "Saved Install macOS apps in Applications. Remove only installers you no longer need. Quit installers and finish updates first; active macOS update staging is excluded."
        }
    }
}

nonisolated struct FileStamp: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

nonisolated struct CleanupItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let root: URL
    let category: CleanupCategory
    let bytes: Int64
    let modified: Date
    let stamp: FileStamp
    let signature: String
    let canClean: Bool
    let reason: String
    let fileCount: Int

    let relativePath: String

    var browserName: String? {
        BrowserCacheCatalog.browserName(relativePath: relativePath)
    }

    var displayName: String {
        guard let browserName else { return url.lastPathComponent }
        if category == .caches { return "\(browserName) cache" }
        return "\(browserName) · \(url.deletingLastPathComponent().lastPathComponent) · \(url.lastPathComponent)"
    }
}

nonisolated struct ScanIssue: Identifiable, Sendable {
    enum Kind: Sendable {
        case access, ownership, limit, other
    }

    var id: String { path + message }
    let path: String
    let message: String
    let kind: Kind
    var requiresAccess: Bool { kind == .access }

    init(path: String, message: String, requiresAccess: Bool = false) {
        self.path = path
        self.message = message
        self.kind = requiresAccess ? .access : .other
    }

    init(path: String, error: Error) {
        self.path = path
        self.message = error.localizedDescription
        if case ScanError.otherOwner = error {
            kind = .ownership
        } else if case ScanError.limit = error {
            kind = .limit
        } else {
            kind = Self.isPermissionError(error) ? .access : .other
        }
    }

    func isWithin(_ root: URL) -> Bool {
        // Bookmarks can retain /var aliases while enumeration returns /private/var.
        let canonical = (try? CleanupScanner.canonicalURL(root))?.path ?? root.path
        return path == root.path || path.hasPrefix(root.path + "/")
            || path == canonical || path.hasPrefix(canonical + "/")
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        var current = error as NSError
        // Foundation may wrap a POSIX failure. Bound traversal of underlying errors.
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain &&
                [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(current.code) {
                return true
            }
            if current.domain == NSPOSIXErrorDomain &&
                [POSIXErrorCode.EACCES.rawValue, POSIXErrorCode.EPERM.rawValue].contains(Int32(current.code)) {
                return true
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            current = underlying
        }
        return false
    }
}

nonisolated struct ScanResult: Sendable {
    var items: [CleanupItem] = []
    var issues: [ScanIssue] = []
}

nonisolated struct CleanupRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let date: Date
    let path: String
    let bytes: Int64
    let outcome: String
    let trashPath: String?
}
