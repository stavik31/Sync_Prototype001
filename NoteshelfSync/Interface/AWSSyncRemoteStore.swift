import Foundation

struct AWSSyncRemoteStore: SyncRemoteStore {
    let authToken: String

    func isAvailable() async -> Bool {
//        KeychainManager.load(key: "authToken") != nil
        !authToken.isEmpty
    }

    func accountDetails() async -> AccountDetails? {
        guard let id = AuthManager.userId(from: authToken) else {return nil }
        return AccountDetails(accountId: id, name: nil, usedBytes: nil, totalBytes: nil)
    }

    func listNotebooks() async -> [RemoteNode] {
        let packages = await SyncAPI.listPackages(authToken: authToken) ?? []
        return packages.map {
            RemoteNode(remoteId: $0.id, name: nil, documentId: $0.id, driveId: nil, version: nil, documentVersion: nil, syncVersion: nil, relativePath: $0.path, createdDevice: nil, lastUpdDevice: nil, createdAt: nil, modifiedAt: $0.last_mod, revisionToken: nil, isFolder: false)
        }
    }

    func maxVersionNotebook(documentId: String) async -> RemoteNode? {
        guard let manifest = await SyncAPI.getManifest(packageId: documentId, authToken: authToken) else { return nil }
        let pkg = manifest.package
        return RemoteNode(remoteId: pkg.id, name: nil, documentId: pkg.id, driveId: nil, version: nil, documentVersion: nil, syncVersion: nil, relativePath: pkg.path, createdDevice: nil, lastUpdDevice: nil, createdAt: nil, modifiedAt: pkg.last_mod, revisionToken: nil, isFolder: false)
    }

    func downloadNotebook(node: RemoteNode, destination: URL, conflictFlow: Bool) async -> DownloadOutcome {
        // TODO — second intern. Nothing to migrate: no download function exists
        // in SyncAPI yet. Needs a new AWS Lambda + a new SyncAPI.download(...)
        // function (mirroring SyncAPI.prepare's shape) before this can be real.
        // See the plan page's Phase 3 section for the exact steps.
        DownloadOutcome(status: .failed, message: "not implemented")
    }

    func readTombstones() async -> [Tombstone] {
        // TODO — second intern. Nothing to migrate: no deletion-tracking table
        // exists yet. Needs a new Lambda + a new SyncAPI.listTombstones(...)
        // function first.
        []
    }

    func uploadNotebook(entity: NotebookSyncInfo, stagedFolder: URL) async -> PublishOutcome {
        let stagedFiles = (try? FileManager.default.contentsOfDirectory(at: stagedFolder, includingPropertiesForKeys: nil)) ?? []
        let existing = await SyncAPI.getManifest(packageId: entity.documentId, authToken: authToken)?.files ?? []

        var changed: [PrepareFile] = []
        for file in stagedFiles {
            let pageId = file.deletingPathExtension().lastPathComponent
            changed.append(PrepareFile(id: pageId, last_mod: entity.modified))
        }

        if !changed.isEmpty {
            guard let prep = await SyncAPI.prepare(packageId: entity.documentId, files: changed, authToken: authToken) else {
                return PublishOutcome(status: .notStarted, syncInfo: entity)
            }
            for target in prep.uploads {
                guard let fileURL = stagedFiles.first(where: { $0.deletingPathExtension().lastPathComponent == target.id }),
                      let content = try? Data(contentsOf: fileURL),
                      await SyncAPI.put(content: content, to: target.url) else {
                    return PublishOutcome(status: .notStarted, syncInfo: entity)
                }
            }
        }

        var manifestById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for file in stagedFiles {
            let pageId = file.deletingPathExtension().lastPathComponent
            manifestById[pageId] = FileEntry(id: pageId, path: file.lastPathComponent, last_mod: entity.modified)
        }

        guard await SyncAPI.commit(packageId: entity.documentId, path: entity.relativePath,
                                    lastMod: entity.modified, manifest: Manifest(files: Array(manifestById.values)),
                                    authToken: authToken) != nil else {
            return PublishOutcome(status: .notStarted, syncInfo: entity)
        }

        var updated = entity
        updated.lstSyncDate = Int64(Date().timeIntervalSince1970 * 1000)
        return PublishOutcome(status: .uploaded, syncInfo: updated)
    }

    func deleteNotebookRemote(entity: NotebookSyncInfo) async -> PublishOutcome {
        // TODO — second intern. Nothing to migrate: today, deleting a notebook
        // only removes it from the local array, AWS never finds out. Needs a
        // new delete Lambda + a new SyncAPI.delete(...) function first.
        PublishOutcome(status: .notStarted, syncInfo: entity)
    }

    func readFolderPlist(kind: FolderKind) async -> FolderPlistDownload? {
        // Deferred — the app has no folder/category concept at all. Leave as
        // a stub unless folder sync gets confirmed as in scope.
        nil
    }

    func writeFolderPlist(kind: FolderKind, file: URL, revisionToken: String?, modifiedAt: Int64) async -> Bool {
        // Deferred — see readFolderPlist above.
        false
    }

    func mapThrowable(_ error: Error) -> DriveSyncException {
        // Placeholder only. SyncAPI currently swallows every failure (prints
        // and returns nil) instead of throwing anything real, so there's
        // nothing meaningful to map yet. Real version needs SyncAPI reworked
        // to throw typed errors first — separate, lower-priority task.
        DriveSyncException(message: error.localizedDescription)
    }

    func downloadDeletionListFile() async -> URL? {
        // TODO — second intern. Depends on readTombstones() above being real
        // first — this just writes that same data out to a local file.
        nil
    }
}
