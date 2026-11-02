import SwiftUI
import AppKit
import Observation
import Darwin

@MainActor @Observable
final class CleanupModel {
    var category: CleanupCategory?
    var items: [CleanupItem] = []
    var issues: [ScanIssue] = []
    var selected: Set<String> = []
    var exclusions: Set<String>
    var history: [CleanupRecord]
    var roots: [CleanupCategory: URL] = [:]
    var search = ""
    var busy = false
    private(set) var grantingAccess = false
    private(set) var accessProgress: String?
    var status = String(localized: "Ready to scan")
    var lastScan: Date?
    var message: String?
    var showConfirmation = false
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var accessPanel: NSOpenPanel?
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        exclusions = Set(defaults.stringArray(forKey: "excludedPaths") ?? [])
        history = defaults.data(forKey: "cleanupHistory").flatMap { try? JSONDecoder().decode([CleanupRecord].self, from: $0) } ?? []
        for category in CleanupCategory.allCases {
            guard let data = defaults.data(forKey: "folder.\(category.rawValue)") else { continue }
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
                guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                defer { url.stopAccessingSecurityScopedResource() }
                try validateFolder(url, for: category)
                if stale {
                    let renewed = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    defaults.set(renewed, forKey: "folder.\(category.rawValue)")
                }
                roots[category] = url
            } catch { status = String(localized: "Folder access must be granted again") }
        }
    }

    var scopedItems: [CleanupItem] {
        items.filter {
            (category == nil || $0.category == category || (category == .browsers && $0.category == .caches && $0.browserName != nil))
                && !exclusions.contains($0.id)
        }
    }
    var visibleItems: [CleanupItem] {
        scopedItems.filter { search.isEmpty || $0.url.path.localizedStandardContains(search) }
    }
    var selectedItems: [CleanupItem] {
        items.filter { selected.contains($0.id) && $0.canClean && !exclusions.contains($0.id) }
    }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var totalBytes: Int64 { scopedItems.reduce(0) { $0 + $1.bytes } }

    var scopedIssues: [ScanIssue] {
        guard let category else { return issues }
        guard let root = roots[category] else { return [] }
        return issues.filter { $0.isWithin(root) }
    }

    var accessIssueCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { category in
            guard let root = roots[category] else { return false }
            return scopedIssues.contains { $0.requiresAccess && $0.isWithin(root) }
        }
    }

    func openSystemSettings() {
        if let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"),
           NSWorkspace.shared.open(privacy) { return }
        if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            message = String(localized: "Open System Settings from the Apple menu, then choose Privacy & Security → Full Disk Access.")
        }
    }

    subscript(isSelected id: String) -> Bool {
        get { selected.contains(id) }
        set { if newValue { selected.insert(id) } else { selected.remove(id) } }
    }

    private static func pathsOverlap(_ a: String, _ b: String) -> Bool {
        a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    func expectedRoot(for category: CleanupCategory) -> URL {
        if category.relativePath.hasPrefix("/") {
            return URL(fileURLWithPath: category.relativePath, isDirectory: true)
        }
        // FileManager's home is the container home in a sandboxed process.
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent(category.relativePath)
    }

    func grant(_ category: CleanupCategory) {
        beginAccess(to: [category])
    }

    /// Each folder still requires explicit approval in macOS's folder picker.
    func grantAll() {
        beginAccess(to: CleanupCategory.allCases.filter { roots[$0] == nil })
    }

    private func beginAccess(to categories: [CleanupCategory]) {
        guard !busy, !grantingAccess else { return }
        guard !categories.isEmpty else {
            status = String(localized: "All cleanup folders are connected")
            return
        }
        grantingAccess = true
        requestAccess(to: categories, index: 0)
    }

    private func finishAccess(status: String) {
        accessPanel = nil
        accessProgress = nil
        grantingAccess = false
        self.status = status
    }

    private func requestAccess(to categories: [CleanupCategory], index: Int) {
        guard index < categories.count else {
            finishAccess(status: String(localized: "Folder access granted. Scan to see its contents."))
            return
        }
        let category = categories[index]
        let expected = expectedRoot(for: category)
        let panel = NSOpenPanel()
        accessPanel = panel
        accessProgress = String(localized: "Folder \(index + 1) of \(categories.count) · \(String(localized: category.title))")
        status = String(localized: "Connecting \(String(localized: category.title))…")
        panel.title = String(localized: "Connect \(String(localized: category.title))")
        panel.message = expected.path
        panel.prompt = String(localized: "Allow Access")
        panel.directoryURL = expected
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else {
                self.finishAccess(status: String(localized: "Folder connection cancelled. Previously connected folders are still available."))
                return
            }
            do {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try self.validateFolder(url, for: category)
                let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                self.defaults.set(data, forKey: "folder.\(category.rawValue)")
                if let previous = self.roots[category] {
                    self.issues.removeAll { $0.isWithin(previous) }
                }
                self.roots[category] = url
                self.items.removeAll { $0.category == category }
                self.issues.removeAll { $0.isWithin(url) }
                self.selected.removeAll()
            } catch {
                self.message = error.localizedDescription
                self.finishAccess(status: String(localized: "Folder access could not be connected. Previously connected folders are still available."))
                return
            }
            // Present the next panel after AppKit finishes dismissing this one.
            self.accessPanel = nil
            Task { @MainActor [weak self] in self?.requestAccess(to: categories, index: index + 1) }
        }
    }

    private func validateFolder(_ url: URL, for category: CleanupCategory) throws {
        let expected = expectedRoot(for: category)
        // Keep scope bounded to the planned folders. Custom DerivedData locations are supported.
        let valid = url.standardizedFileURL.path == expected.standardizedFileURL.path
            || (category == .developer && url.lastPathComponent == "DerivedData")
        guard valid, url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw FolderAccessError.unexpectedFolder
        }
        let canonical = try CleanupScanner.canonicalURL(url).path
        for (otherCategory, other) in roots where otherCategory != category {
            let scoped = other.startAccessingSecurityScopedResource()
            defer { if scoped { other.stopAccessingSecurityScopedResource() } }
            let otherPath = try CleanupScanner.canonicalURL(other).path
            guard !Self.pathsOverlap(canonical, otherPath) else { throw FolderAccessError.overlap }
        }
    }

    private enum FolderAccessError: LocalizedError {
        case unexpectedFolder, overlap
        var errorDescription: String? {
            switch self {
            case .unexpectedFolder:
                String(localized: "Choose the displayed folder. Custom Xcode folders must be named DerivedData.")
            case .overlap:
                String(localized: "This folder overlaps another scan category. Choose a separate DerivedData folder to avoid counting or cleaning items twice.")
            }
        }
    }

    func revoke(_ category: CleanupCategory) {
        guard !busy, !grantingAccess else { return }
        if let root = roots[category] { issues.removeAll { $0.isWithin(root) } }
        roots.removeValue(forKey: category)
        defaults.removeObject(forKey: "folder.\(category.rawValue)")
        items.removeAll { $0.category == category }
        selected.removeAll()
        status = String(localized: "Folder access removed")
    }

    func scan() {
        guard !busy, !grantingAccess else { return }
        guard !roots.isEmpty else {
            message = String(localized: "Allow access to a scan folder first.")
            return
        }
        busy = true
        selected.removeAll()
        items.removeAll()
        issues.removeAll()
        let roots = roots
        let excluded = exclusions
        operation = Task {
            defer { busy = false; operation = nil }
            for category in CleanupCategory.allCases {
                guard !Task.isCancelled else { status = String(localized: "Scan cancelled — results are incomplete"); return }
                guard let root = roots[category] else { continue }
                status = String(localized: "Scanning \(root.lastPathComponent)…")
                guard root.startAccessingSecurityScopedResource() else {
                    issues.append(ScanIssue(path: root.path, message: String(localized: "Access unavailable. Allow access again."), requiresAccess: true))
                    continue
                }
                let worker = Task.detached(priority: .userInitiated) {
                    try CleanupScanner().scan(root: root, category: category, excluded: excluded)
                }
                do {
                    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    items.append(contentsOf: result.items)
                    issues.append(contentsOf: result.issues)
                } catch is CancellationError {
                    root.stopAccessingSecurityScopedResource()
                    status = String(localized: "Scan cancelled — results are incomplete")
                    return
                } catch { issues.append(ScanIssue(path: root.path, error: error)) }
                root.stopAccessingSecurityScopedResource()
            }
            items.sort { $0.bytes > $1.bytes }
            lastScan = .now
            status = issues.isEmpty ? String(localized: "Scan complete") : String(localized: "Scan complete with skipped locations")
        }
    }

    func cancel() { operation?.cancel() }
    func selectEligible() { selected.formUnion(visibleItems.filter(\.canClean).map(\.id)) }
    func exclude(_ item: CleanupItem) {
        exclusions.insert(item.id)
        selected.remove(item.id)
        defaults.set(Array(exclusions), forKey: "excludedPaths")
    }
    func resetExclusions() {
        exclusions.removeAll()
        defaults.removeObject(forKey: "excludedPaths")
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func clean() {
        guard !busy, !grantingAccess else { return }
        let plan = selectedItems
        guard !plan.isEmpty else { return }
        busy = true
        operation = Task {
            defer { busy = false; operation = nil; selected.removeAll() }
            for item in plan {
                if Task.isCancelled { status = String(localized: "Cleanup cancelled. Completed moves remain in Trash."); return }
                status = String(localized: "Checking \(item.url.lastPathComponent)…")
                var destination: URL?
                var outcome: String
                let scoped = item.root.startAccessingSecurityScopedResource()
                do {
                    guard scoped else { throw CocoaError(.fileReadNoPermission) }
                    if item.category == .developer {
                        let active = NSWorkspace.shared.runningApplications.contains {
                            ["com.apple.dt.Xcode", "com.apple.iphonesimulator"].contains($0.bundleIdentifier ?? "")
                        }
                        guard !active else { throw ScanError.busy }
                    }
                    let worker = Task.detached(priority: .userInitiated) { try TrashService().move(item) }
                    destination = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    outcome = String(localized: "Moved to Trash")
                    items.removeAll { $0.id == item.id }
                } catch { outcome = error.localizedDescription }
                if scoped { item.root.stopAccessingSecurityScopedResource() }
                history.insert(CleanupRecord(id: UUID(), date: .now, path: item.id, bytes: destination == nil ? 0 : item.bytes,
                                             outcome: outcome, trashPath: destination?.path), at: 0)
                history = Array(history.prefix(100))
                if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "cleanupHistory") }
            }
            status = String(localized: "Cleanup finished. Review the activity report.")
        }
    }
}
