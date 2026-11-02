import Foundation
import Testing
@testable import CleanupCore

@Test func permissionIssuesRecognizeFoundationPOSIXAndWrappedErrors() {
    let errors: [Error] = [CocoaError(.fileReadNoPermission), CocoaError(.fileWriteNoPermission),
                           POSIXError(.EACCES), POSIXError(.EPERM),
                           NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue,
                                   userInfo: [NSUnderlyingErrorKey: POSIXError(.EACCES)])]
    for error in errors {
        let issue = ScanIssue(path: "/fixture/cache", error: error)
        #expect(issue.requiresAccess)
        #expect(issue.message == error.localizedDescription)
    }
    for error: Error in [ScanError.unsafePath, ScanError.limit, ScanError.otherOwner,
                         CocoaError(.fileNoSuchFile), POSIXError(.ENOENT)] {
        #expect(!ScanIssue(path: "/fixture/cache", error: error).requiresAccess)
    }
}

@Test func ownershipAndScanLimitsDoNotSuggestReconnecting() {
    let ownership = ScanIssue(path: "/Library/Caches/example", error: ScanError.otherOwner)
    #expect(ownership.kind == .ownership)
    #expect(!ownership.requiresAccess)
    let limit = ScanIssue(path: "/fixture/DerivedData", error: ScanError.limit)
    #expect(limit.kind == .limit)
    #expect(!limit.requiresAccess)
    #expect(ScanIssue(path: "/fixture", error: POSIXError(.EPERM)).kind == .access)
}

@Test func issuesStayWithinTheirCategoryIncludingCanonicalAliases() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let cache = try fixture.file("Cache/data").deletingLastPathComponent()
    let issue = ScanIssue(path: cache.appendingPathComponent("data").path, error: ScanError.otherOwner)
    #expect(issue.isWithin(cache))
    #expect(ScanIssue(path: cache.path, error: ScanError.limit).isWithin(cache))
    #expect(!issue.isWithin(fixture.root.appendingPathComponent("Other")))
    #expect(!ScanIssue(path: cache.path + "-other/data", error: ScanError.limit).isWithin(cache))
    let alias = URL(fileURLWithPath: cache.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
    #expect(issue.isWithin(alias))
}

@Test func unreadableCacheIsReportedWhileAccessibleCacheRemainsSelectable() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Accessible/data")
    _ = try fixture.file("Blocked/data")
    let blocked = fixture.root.appendingPathComponent("Blocked")
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blocked.path) }
    let result = try CleanupScanner().scan(root: fixture.root, category: .caches)
    #expect(result.items.map { $0.url.lastPathComponent } == ["Accessible"])
    #expect(result.items.allSatisfy { $0.canClean })
    try #require(result.issues.count == 1)
    #expect(result.issues[0].path == blocked.path)
    #expect(result.issues[0].requiresAccess)
}

private struct Fixture {
    let root: URL
    let now = Date()
    init() throws {
        root = try CleanupScanner.canonicalURL(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func file(_ path: String, age: TimeInterval = 40 * 86_400, text: String = "fixture") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }
    func derivedData() throws -> URL {
        let project = root.appendingPathComponent("Project-123")
        _ = try file("Project-123/Build/output", text: "build result")
        let info = try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": "/tmp/Example.xcworkspace"], format: .xml, options: 0)
        try info.write(to: project.appendingPathComponent("info.plist"))
        let enumerator = FileManager.default.enumerator(at: project, includingPropertiesForKeys: nil)!
        for case let url as URL in enumerator {
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: url.path)
        }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-40 * 86_400)], ofItemAtPath: project.path)
        return project
    }
}

@Test func allLogsAndReportsAreSelectableRegardlessOfAgeOrName() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("DiagnosticReports/Old.ips")
    _ = try fixture.file("app/output.log.1")
    _ = try fixture.file("app/active.log")
    _ = try fixture.file("DiagnosticReports/New.crash", age: 100)
    _ = try fixture.file("app/credentials.json")
    let result = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .logs)
    #expect(result.items.count == 5)
    #expect(Set(result.items.filter(\.canClean).map { $0.url.lastPathComponent }) == ["Old.ips", "output.log.1", "active.log", "New.crash", "credentials.json"])
    #expect(result.issues.isEmpty)
}

@Test func cachesCanBeSelectedAndScanDoesNotChangeFiles() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("UnknownApp/cache", text: "preserve me")
    let before = try CleanupScanner.stamp(file)
    let result = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .caches)
    try #require(result.items.count == 1)
    #expect(result.items[0].bytes == 11)
    #expect(result.items[0].canClean)
    #expect(try CleanupScanner.stamp(file) == before)
    #expect(try String(contentsOf: file, encoding: .utf8) == "preserve me")
}

@Test func excludesWholeLogSubtrees() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Keep/log.log.1")
    _ = try fixture.file("Other/log.log.1")
    let result = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .logs,
                                                        excluded: [fixture.root.appendingPathComponent("Keep").path])
    try #require(result.items.count == 1)
    #expect(result.items[0].url.path.contains("Other"))
}

@Test func neverFollowsLinks() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let target = try fixture.file("real/secret", text: "private data")
    let link = fixture.root.appendingPathComponent("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.deletingLastPathComponent())
    let result = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .caches)
    #expect(result.items.count == 1)
    try #require(result.issues.count == 1)
    #expect(result.issues[0].path == link.path)
    #expect(throws: ScanError.self) { try CleanupScanner().scan(root: link, category: .caches) }
}

@Test func allDerivedDataIncludingRecentAndSharedCachesCanBeSelected() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let project = try fixture.derivedData()
    _ = try fixture.file("CompilationCache.noindex/data")
    _ = try fixture.file("ModuleCache.noindex/data")
    let first = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .developer)
    #expect(first.items.first(where: { $0.url.path == project.path })?.canClean == true)
    #expect(first.items.allSatisfy { $0.canClean })
    #expect(first.items.count == 3)
    _ = try fixture.file("Project-123/Build/new", age: 0)
    let second = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .developer)
    #expect(second.items.first(where: { $0.url.path == project.path })?.canClean == true)
}

@Test func changedTreeHasDifferentSignature() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let project = try fixture.derivedData()
    let scanner = CleanupScanner(now: fixture.now)
    let before = try scanner.inspect(project, root: fixture.root, category: .developer)
    _ = try fixture.file("Project-123/Build/output", text: "different output")
    let after = try scanner.inspect(project, root: fixture.root, category: .developer)
    #expect(before.signature != after.signature)
}

@Test func hardLinksAreNotCountedTwiceWithinCandidate() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("Cache/a", text: "12345")
    try FileManager.default.linkItem(at: file, to: fixture.root.appendingPathComponent("Cache/b"))
    let result = try CleanupScanner(now: fixture.now).scan(root: fixture.root, category: .caches)
    try #require(result.items.count == 1)
    #expect(result.items[0].bytes == 5)
    #expect(result.items[0].fileCount == 2)
}

@Test func scanLimitIsReportedInsteadOfClaimingCompleteSize() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Cache/a")
    _ = try fixture.file("Cache/b")
    let result = try CleanupScanner(now: fixture.now, maximumEntries: 1).scan(root: fixture.root, category: .caches)
    #expect(result.items.isEmpty)
    #expect(!result.issues.isEmpty)
}

@Test func cancelledScanThrows() async throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Cache/a")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try CleanupScanner().scan(root: fixture.root, category: .caches)
    }
    do {
        _ = try await task.value
        Issue.record("Expected cancelled scan")
    } catch { #expect(error is CancellationError) }
}

@Test func rejectsChangedCleanupCandidateWithoutMutation() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("report.log.1")
    let item = try CleanupScanner(now: fixture.now).inspect(file, root: fixture.root, category: .logs)
    #expect(item.canClean)
    _ = try fixture.file("report.log.1", age: 0, text: "new active output")
    #expect(throws: ScanError.self) { try TrashService().move(item) }
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func movesOnlyDisposableFixtureToTrashAndVerifiesDestination() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    // Only data generated by this test is moved. Never scans the user's logs or caches.
    let file = try fixture.file("ClearStuffTest-\(UUID().uuidString).log.1", text: "disposable test fixture")
    let item = try CleanupScanner(now: fixture.now).inspect(file, root: fixture.root, category: .logs)
    try #require(item.canClean)
    let destination = try TrashService().move(item)
    defer { try? FileManager.default.removeItem(at: destination) }
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try String(contentsOf: destination, encoding: .utf8) == "disposable test fixture")
}

@Test func macOSSystemPathAliasesProduceValidContainedItems() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Cache/a")
    let aliased = URL(fileURLWithPath: fixture.root.path.replacingOccurrences(of: "/private/var/", with: "/var/"))
    let result = try CleanupScanner().scan(root: aliased, category: .caches)
    #expect(result.items.count == 1)
    #expect(result.issues.isEmpty)
}

@Test func movesCacheContainingLinkWithoutTouchingTarget() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let target = try fixture.file("Outside/keep", text: "preserve target")
    let cache = fixture.root.appendingPathComponent("Cache")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("link"), withDestinationURL: target)
    let item = try CleanupScanner(now: fixture.now).inspect(cache, root: fixture.root, category: .caches)
    #expect(item.canClean)
    #expect(item.bytes == 0)
    let destination = try TrashService().move(item)
    defer { try? FileManager.default.removeItem(at: destination) }
    #expect(try String(contentsOf: target, encoding: .utf8) == "preserve target")
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.appendingPathComponent("link").path) == target.path)
}

@Test func movesManuallySelectedCacheFixtureToTrash() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("ClearStuffCacheTest-\(UUID().uuidString)/data", age: 0, text: "disposable cache")
    let folder = file.deletingLastPathComponent()
    let item = try CleanupScanner(now: fixture.now).inspect(folder, root: fixture.root, category: .caches)
    try #require(item.canClean)
    let destination = try TrashService().move(item)
    defer { try? FileManager.default.removeItem(at: destination) }
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(try String(contentsOf: destination.appendingPathComponent("data"), encoding: .utf8) == "disposable cache")
}

@Test func browserDiscoveryIncludesOnlyCacheFoldersAcrossProfiles() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let paths = ["Google/Chrome/Default/Cache/data", "Google/Chrome/Profile 2/Code Cache/js",
                 "Microsoft Edge/Default/GPUCache/data", "BraveSoftware/Brave-Browser/Default/Cache/data",
                 "Firefox/Profiles/example.default/cache2/entries/data", "Opera Software/Opera Stable/Cache/data"]
    for path in paths { _ = try fixture.file(path, age: 0) }
    let preserved = ["Google/Chrome/Default/Login Data", "Google/Chrome/Default/History",
                     "Google/Chrome/Default/Bookmarks", "Google/Chrome/Default/Network/Cookies",
                     "Google/Chrome/Default/Local Storage/data", "Google/Chrome/Default/Extensions/data",
                     "Firefox/Profiles/example.default/logins.json", "Unrelated/Cache/data"]
    for path in preserved { _ = try fixture.file(path, text: "keep") }
    let result = try CleanupScanner().scan(root: fixture.root, category: .browsers)
    #expect(result.items.count == paths.count)
    #expect(result.items.allSatisfy { $0.canClean })
    #expect(result.issues.isEmpty)
    #expect(Set(result.items.compactMap(\.browserName)) == ["Chrome", "Edge", "Brave", "Firefox", "Opera"])
    let chromeCache = try #require(result.items.first { $0.url.path.hasSuffix("Default/Cache") && $0.browserName == "Chrome" })
    let destination = try TrashService().move(chromeCache)
    defer { try? FileManager.default.removeItem(at: destination) }
    for path in preserved { #expect(try String(contentsOf: fixture.root.appendingPathComponent(path), encoding: .utf8) == "keep") }
    let profile = fixture.root.appendingPathComponent("Google/Chrome/Default")
    #expect(throws: ScanError.self) { try CleanupScanner().inspect(profile, root: fixture.root, category: .browsers) }
}

@Test func browserDiscoveryRespectsExclusionsAndSkipsLinkedProfiles() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Google/Chrome/Default/Cache/data")
    _ = try fixture.file("Microsoft Edge/Default/Cache/data")
    _ = try fixture.file("Outside/Cache/keep")
    try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("Chromium"), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: fixture.root.appendingPathComponent("Chromium/Default"), withDestinationURL: fixture.root.appendingPathComponent("Outside"))
    let result = try CleanupScanner().scan(root: fixture.root, category: .browsers,
                                         excluded: [fixture.root.appendingPathComponent("Google/Chrome").path])
    #expect(result.items.count == 1)
    #expect(result.items.first?.browserName == "Edge")
    #expect(result.issues.count == 1)
}

@Test func vendorCachesAreSplitWithoutDoubleCounting() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Google/Chrome/Default/Cache/data", text: "12345")
    _ = try fixture.file("Google/Other/cache", text: "123")
    let result = try CleanupScanner().scan(root: fixture.root, category: .caches)
    #expect(result.items.count == 2)
    #expect(result.items.reduce(0) { $0 + $1.bytes } == 8)
    #expect(result.items.filter { $0.browserName != nil }.count == 1)
}

@Test func downloadsListPartialInstallersAndTruncatedZIPsButPreservePersonalFiles() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let candidates = ["unfinished.crdownload", "unfinished.part", "Safari.download/data",
                      "InstallAssistant.pkg", "installer.dmg", "truncated.zip"]
    for path in candidates { _ = try fixture.file(path, age: 0) }
    let preserved = ["photo.jpg", "document.pdf", "empty.txt", "Personal/unfinished.part", "backup.iso"]
    for path in preserved { _ = try fixture.file(path, text: "preserve") }
    let validZIP = try fixture.file("empty-valid.zip")
    try (Data([0x50, 0x4b, 0x05, 0x06]) + Data(repeating: 0, count: 18)).write(to: validZIP)
    let result = try CleanupScanner().scan(root: fixture.root, category: .downloads)
    #expect(Set(result.items.map { $0.url.lastPathComponent }) == ["unfinished.crdownload", "unfinished.part", "Safari.download", "InstallAssistant.pkg", "installer.dmg", "truncated.zip"])
    #expect(result.items.allSatisfy { $0.canClean })
    #expect(result.issues.isEmpty)
    #expect(throws: ScanError.self) { try CleanupScanner().inspect(fixture.root.appendingPathComponent("document.pdf"), root: fixture.root, category: .downloads) }
    #expect(throws: ScanError.self) { try CleanupScanner().inspect(fixture.root.appendingPathComponent("Personal/unfinished.part"), root: fixture.root, category: .downloads) }
    for path in preserved { #expect(try String(contentsOf: fixture.root.appendingPathComponent(path), encoding: .utf8) == "preserve") }
}

@Test func partialDownloadIsRecheckedBeforeTrashAndCompletedDownloadIsPreserved() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("truncated.zip", text: "incomplete")
    let item = try CleanupScanner().inspect(file, root: fixture.root, category: .downloads)
    try #require(item.canClean)
    try (Data([0x50, 0x4b, 0x05, 0x06]) + Data(repeating: 0, count: 18)).write(to: file)
    #expect(throws: ScanError.self) { try TrashService().move(item) }
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@Test func savedMacOSInstallersDoNotIncludeInstalledAppsOrUpdateStaging() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    _ = try fixture.file("Install macOS Example.app/Contents/SharedSupport/image.dmg")
    _ = try fixture.file("Keep.app/Contents/data")
    _ = try fixture.file("macOS Install Data/payload")
    let result = try CleanupScanner().scan(root: fixture.root, category: .installers)
    #expect(result.items.count == 1)
    #expect(result.items.first?.url.lastPathComponent == "Install macOS Example.app")
    #expect(throws: ScanError.self) { try CleanupScanner().inspect(fixture.root.appendingPathComponent("Keep.app"), root: fixture.root, category: .installers) }
}

@Test func movesOnlySelectedDownloadFixtureToTrash() throws {
    let fixture = try Fixture(); defer { fixture.remove() }
    let file = try fixture.file("ClearStuffDownloadTest-\(UUID().uuidString).crdownload")
    let preserved = try fixture.file("keep.pdf", text: "personal download")
    let item = try CleanupScanner().inspect(file, root: fixture.root, category: .downloads)
    let destination = try TrashService().move(item)
    defer { try? FileManager.default.removeItem(at: destination) }
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(try String(contentsOf: preserved, encoding: .utf8) == "personal download")
}
