import Foundation

nonisolated struct TrashService: Sendable {
    /// Coordinate with cooperating writers, then re-scan. Users must stop uncoordinated builds.
    func move(_ item: CleanupItem) throws -> URL {
        try Task.checkCancellation()
        guard item.canClean else { throw ScanError.unsafePath }
        guard item.root.standardizedFileURL == item.root.resolvingSymlinksInPath().standardizedFileURL else {
            throw ScanError.unsafePath
        }
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Result<URL, Error>?
        coordinator.coordinate(writingItemAt: item.url, options: .forMoving, error: &coordinationError) { coordinatedURL in
            outcome = Result {
                try Task.checkCancellation()
                let fresh = try CleanupScanner().inspect(coordinatedURL, root: item.root, category: item.category)
                guard fresh.stamp == item.stamp, fresh.signature == item.signature, fresh.canClean else {
                    throw ScanError.changed
                }
                // A final check narrows the window after the recursive inspection.
                guard try CleanupScanner.stamp(coordinatedURL) == item.stamp else { throw ScanError.changed }
                var destination: NSURL?
                try FileManager.default.trashItem(at: coordinatedURL, resultingItemURL: &destination)
                guard let destination = destination as URL?,
                      !FileManager.default.fileExists(atPath: coordinatedURL.path),
                      try CleanupScanner.stamp(destination).inode == item.stamp.inode else {
                    throw CocoaError(.fileWriteUnknown)
                }
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }
}
