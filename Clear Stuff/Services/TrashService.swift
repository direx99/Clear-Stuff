import Foundation
import Darwin

nonisolated enum TrashMoveResult: Sendable {
    case verified(URL)
    case movedButUnverified(URL?)

    var destination: URL? {
        switch self {
        case .verified(let url): url
        case .movedButUnverified(let url): url
        }
    }
}

nonisolated struct TrashService: Sendable {
    /// Coordinate with cooperating writers, then re-scan and isolate the candidate before trashing it.
    func move(_ item: CleanupItem, afterStaging: (URL) throws -> Void = { _ in }) throws -> TrashMoveResult {
        try Task.checkCancellation()
        guard item.canClean else { throw ScanError.unsafePath }
        guard item.root.standardizedFileURL == item.root.resolvingSymlinksInPath().standardizedFileURL else {
            throw ScanError.unsafePath
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<TrashMoveResult, Error>?
        coordinator.coordinate(writingItemAt: item.url, options: .forMoving, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                try Task.checkCancellation()
                let scanner = CleanupScanner()
                let fresh = try scanner.inspect(coordinatedURL, root: item.root, category: item.category)
                guard fresh.stamp == item.stamp, fresh.signature == item.signature, fresh.canClean else {
                    throw ScanError.changed
                }
                guard try CleanupScanner.stamp(coordinatedURL) == item.stamp else { throw ScanError.changed }

                // An atomic same-directory rename isolates the exact directory entry we will trash.
                // If another process wins the race, validate the renamed object before trashing it.
                let stagedURL = coordinatedURL.deletingLastPathComponent()
                    .appendingPathComponent(".ClearStuff-\(UUID().uuidString)-\(coordinatedURL.lastPathComponent)")
                try Self.renameExclusively(coordinatedURL, to: stagedURL)
                do {
                    try afterStaging(stagedURL)
                    let staged = try scanner.fingerprint(stagedURL)
                    guard Self.sameObject(staged.stamp, item.stamp), staged.signature == item.signature else {
                        throw ScanError.changed
                    }
                } catch {
                    do { try Self.renameExclusively(stagedURL, to: coordinatedURL) }
                    catch { throw TrashStagingError.restoreFailed(stagedURL) }
                    throw error
                }

                var destination: NSURL?
                // Once this call returns, a verification failure must not be reported as a failed move.
                do { try FileManager.default.trashItem(at: stagedURL, resultingItemURL: &destination) }
                catch {
                    if !FileManager.default.fileExists(atPath: stagedURL.path) {
                        return .movedButUnverified(destination as URL?)
                    }
                    do { try Self.renameExclusively(stagedURL, to: coordinatedURL) }
                    catch { throw TrashStagingError.restoreFailed(stagedURL) }
                    throw error
                }
                let trashURL = destination as URL?
                guard let trashURL,
                      !FileManager.default.fileExists(atPath: stagedURL.path),
                      (try? CleanupScanner.stamp(trashURL).inode) == item.stamp.inode else {
                    return .movedButUnverified(trashURL)
                }
                return .verified(trashURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }

    private static func sameObject(_ current: FileStamp, _ original: FileStamp) -> Bool {
        current.device == original.device && current.inode == original.inode &&
        current.size == original.size && current.modifiedSeconds == original.modifiedSeconds &&
        current.modifiedNanoseconds == original.modifiedNanoseconds
    }

    private static func renameExclusively(_ source: URL, to destination: URL) throws {
        let status = source.path.withCString { from in
            destination.path.withCString { to in
                renameatx_np(AT_FDCWD, from, AT_FDCWD, to, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}

nonisolated enum TrashStagingError: LocalizedError {
    case restoreFailed(URL)

    var errorDescription: String? {
        switch self {
        case .restoreFailed(let url):
            String(localized: "The item changed during cleanup and could not be restored to its original path. Review \(url.path) in Finder.")
        }
    }
}
