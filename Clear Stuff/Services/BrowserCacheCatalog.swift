import Foundation

/// Only these cache directories are candidates inside Application Support.
/// Profile roots, website storage, cookies, credentials, and extensions are never candidates.
nonisolated enum BrowserCacheCatalog {
    static let browsers: [(path: String, name: String)] = [
        ("Google/Chrome", "Chrome"), ("Google/Chrome Beta", "Chrome Beta"),
        ("Google/Chrome Canary", "Chrome Canary"), ("Chromium", "Chromium"),
        ("Microsoft Edge", "Edge"), ("Microsoft Edge Beta", "Edge Beta"),
        ("BraveSoftware/Brave-Browser", "Brave"), ("Vivaldi", "Vivaldi"),
        ("Opera Software/Opera Stable", "Opera"), ("Firefox", "Firefox")
    ]
    static let chromiumCaches = ["Cache", "Code Cache", "GPUCache", "DawnCache", "GrShaderCache", "ShaderCache"]

    static func browserName(relativePath: String) -> String? {
        if relativePath == "com.apple.Safari" || relativePath.hasPrefix("com.apple.Safari/") { return "Safari" }
        return browsers.first { relativePath == $0.path || relativePath.hasPrefix($0.path + "/") }?.name
    }

    static func isProfileCache(relativePath: String) -> Bool {
        for browser in browsers {
            guard relativePath.hasPrefix(browser.path + "/") else { continue }
            let parts = relativePath.dropFirst(browser.path.count + 1).split(separator: "/").map(String.init)
            if browser.name == "Firefox" {
                return parts.count == 3 && parts[0] == "Profiles" && parts[2] == "cache2"
            }
            if browser.name == "Opera" {
                return parts.count == 1 && chromiumCaches.contains(parts[0])
            }
            return parts.count == 2 && isChromiumProfile(parts[0]) && chromiumCaches.contains(parts[1])
        }
        return false
    }

    private static func isChromiumProfile(_ name: String) -> Bool {
        name == "Default" || name == "Guest Profile" || name.hasPrefix("Profile ")
    }

    static func candidates(root: URL, excluded: Set<String>, issues: inout [ScanIssue]) throws -> [URL] {
        var candidates: [URL] = []
        let fm = FileManager.default
        for browser in browsers {
            try Task.checkCancellation()
            let base = root.appendingPathComponent(browser.path, isDirectory: true)
            guard fm.fileExists(atPath: base.path), !isExcluded(base, excluded: excluded) else { continue }
            do {
                guard base.standardizedFileURL == base.resolvingSymlinksInPath().standardizedFileURL else { throw ScanError.unsafePath }
                if browser.name == "Opera" {
                    candidates += chromiumCaches.map { base.appendingPathComponent($0, isDirectory: true) }
                } else {
                    let profilesRoot = browser.name == "Firefox" ? base.appendingPathComponent("Profiles", isDirectory: true) : base
                    guard fm.fileExists(atPath: profilesRoot.path), !isExcluded(profilesRoot, excluded: excluded) else { continue }
                    guard profilesRoot.standardizedFileURL == profilesRoot.resolvingSymlinksInPath().standardizedFileURL else { throw ScanError.unsafePath }
                    let profiles = try fm.contentsOfDirectory(at: profilesRoot, includingPropertiesForKeys: [.isDirectoryKey])
                    guard profiles.count <= 512 else { throw ScanError.limit }
                    for profile in profiles where browser.name == "Firefox" || isChromiumProfile(profile.lastPathComponent) {
                        guard !isExcluded(profile, excluded: excluded) else { continue }
                        guard profile.standardizedFileURL == profile.resolvingSymlinksInPath().standardizedFileURL else { throw ScanError.unsafePath }
                        guard try profile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { continue }
                        let names = browser.name == "Firefox" ? ["cache2"] : chromiumCaches
                        candidates += names.map { profile.appendingPathComponent($0, isDirectory: true) }
                    }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { issues.append(ScanIssue(path: base.path, error: error)) }
        }
        return candidates.filter { fm.fileExists(atPath: $0.path) && !isExcluded($0, excluded: excluded) }
    }

    private static func isExcluded(_ url: URL, excluded: Set<String>) -> Bool {
        excluded.contains { url.path == $0 || url.path.hasPrefix($0 + "/") }
    }
}
