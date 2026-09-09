import Foundation

// Shared mutable state for one uploadNotebook call: the lock's current etag
// (updated every heartbeat) and whether it's known to be lost. An actor
// because both the main upload flow and the background heartbeat Task read
// and write this concurrently.
fileprivate actor LockState {
    private(set) var etag: String
    private(set) var lost = false
    
    init(etag: String) {
        self.etag = etag
    }
    
    func update(_ newEtag: String) {
        etag = newEtag
    }
    
    func markLost() {
        lost = true
    }
}

struct AWSSyncRemoteStore: SyncRemoteStore {
    let authToken: String

    // Only checks that a token string was provided — it does NOT verify the
    // token is still valid with Cognito/the server. A garbage or expired
    // non-empty string still passes this check.
    func isAvailable() async -> Bool {
        !authToken.isEmpty
    }

    // Only accountId gets filled in (decoded locally from the JWT, no network
    // call). name/usedBytes/totalBytes are always nil — nothing in this
    // backend exposes them.
    func accountDetails() async -> AccountDetails? {
        guard let id = AuthManager.userId(from: authToken) else {return nil }
        return AccountDetails(accountId: id, name: nil, usedBytes: nil, totalBytes: nil)
    }

    // Maps the server's package list straight onto RemoteNode. Most fields
    // stay nil — this backend doesn't track device ids, versions, or folder
    // structure, so there's nothing to put in them.
    func listNotebooks() async -> [RemoteNode] {
        let packages = await SyncAPI.listPackages(authToken: authToken) ?? []
        return packages.map {
            RemoteNode(remoteId: $0.id, name: nil, documentId: $0.id, driveId: nil, version: nil, documentVersion: nil, syncVersion: nil, relativePath: $0.path, createdDevice: nil, lastUpdDevice: nil, createdAt: nil, modifiedAt: $0.last_mod, revisionToken: nil, isFolder: false)
        }
    }

    // One notebook's current server-side state. Note getManifest returns nil
    // both when the notebook genuinely doesn't exist AND when something else
    // went wrong (see SyncAPI.getManifest's comment) — this can't tell those
    // two cases apart either.
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

    // The whole upload, end to end. stagedFolder holds only the files that
    // actually need uploading — UploadEngine already decided that; this
    // function doesn't re-diff anything itself, except to work out each
    // staged file's id for prepare/commit. Every exit path (success or
    // failure) goes through releaseAndStop() so the lock is never left held.
    func uploadNotebook(entity: NotebookSyncInfo, stagedFolder: URL) async -> PublishOutcome {
        // 1. Take the lock. Nothing below assumes it might not be held.
        guard let lock = await SyncAPI.acquireLock(packageId: entity.documentId, authToken: authToken),
              lock.acquired, let initialEtag = lock.etag else {
            return PublishOutcome(status: .notStarted, syncInfo: entity)
        }

        // 2. Keep the lock alive in the background for however long the
        // upload takes — see startHeartbeat below.
        let lockState = LockState(etag: initialEtag)
        let heartbeat = startHeartbeat(packageId: entity.documentId, lockState: lockState)

        func releaseAndStop() async {
            heartbeat.cancel()
            let finalEtag = await lockState.etag
            _ = await SyncAPI.releaseLock(packageId: entity.documentId, etag: finalEtag, authToken: authToken)
        }

        // 3. Work out each staged file's server-side id via stagedFileId
        // (below), and compare against what the server already has, so only
        // genuinely-changed files get sent to prepare.
        let stagedFiles = (try? FileManager.default.contentsOfDirectory(at: stagedFolder, includingPropertiesForKeys: nil)) ?? []
        let existing = await SyncAPI.getManifest(packageId: entity.documentId, authToken: authToken)?.files ?? []

        var changed: [PrepareFile] = []
        for file in stagedFiles {
            let pageId = stagedFileId(file, notebookId: entity.documentId)
            changed.append(PrepareFile(id: pageId, last_mod: fileLastMod(file)))
        }

        // 4. prepare + upload — skipped entirely if nothing changed.
        if !changed.isEmpty {
            guard let prep = await SyncAPI.prepare(packageId: entity.documentId, files: changed, authToken: authToken) else {
                await releaseAndStop()
                return PublishOutcome(status: .notStarted, syncInfo: entity)
            }
            // Every changed file uploads in parallel. Large files (over
            // chunkSize) go through the multipart path; everything else is
            // one plain PUT.
            let allUploaded = await withTaskGroup(of: Bool.self) { group in
                for target in prep.uploads {
                    group.addTask {
                        guard let fileURL = stagedFiles.first(where: {
                            stagedFileId($0, notebookId: entity.documentId) == target.id}),
                              let content = try? Data(contentsOf: fileURL) else {
                            return false
                        }

                        if content.count > Self.chunkSize {
                            return await uploadLargeFile(content: content, packageId: entity.documentId, fileId: target.id, lastMod: entity.modified)
                        }

                        return await SyncAPI.put(content: content, to: target.url)
                    }
                }

                var success = true
                for await ok in group {
                    if !ok { success = false }
                }
                return success
            }

            guard allUploaded else {
                await releaseAndStop()
                return PublishOutcome(status: .notStarted, syncInfo: entity)
            }
        }

        // 5. Build the final manifest: start from what the server already had,
        // then overwrite/add an entry for every staged file. commit() below
        // treats this as the complete truth for the notebook — anything not
        // in here gets deleted server-side, which is why this starts from
        // `existing` rather than just the staged files.
        var manifestById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for file in stagedFiles {
            let pageId = stagedFileId(file, notebookId: entity.documentId)
            let path = pageId == entity.documentId ? "notebook.json" : "Pages/\(pageId).rtf"
            manifestById[pageId] = FileEntry(id: pageId, path: path, last_mod: fileLastMod(file))
        }

        // 6. If the heartbeat ever lost the lock while we were uploading,
        // bail instead of committing — someone else may already be publishing.
        if await lockState.lost {
            await releaseAndStop()
            return PublishOutcome(status: .notStarted, syncInfo: entity)
        }

        // 7. Publish. This is the point of no return — see SyncAPI.commit's
        // own warning about the manifest being the complete truth.
        guard await SyncAPI.commit(packageId: entity.documentId, path: entity.relativePath,
                                   lastMod: entity.modified, manifest: Manifest(files: Array(manifestById.values)), authToken: authToken) != nil else {
            await releaseAndStop()
            return PublishOutcome(status: .notStarted, syncInfo: entity)
        }

        // 8. Always release, even on the success path.
        await releaseAndStop()

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

    // A staged file's own mtime, read straight off the filesystem — so
    // per-page diffing compares each page against its own timestamp, not the
    // whole notebook's.
    private func fileLastMod(_ url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attrs?[.modificationDate] as? Date else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    // A staged file's filename doubles as its server-side id — except the
    // notebook's own metadata file, which is always named "notebook.json" and
    // so carries no id of its own. That one case maps to the notebook's id
    // instead; every other file's id is just its name with ".rtf" stripped.
    private func stagedFileId(_ file: URL, notebookId: String) -> String {
        file.lastPathComponent == "notebook.json" ? notebookId : file.deletingPathExtension().lastPathComponent
    }

    // Files at or under this size go through a single PUT; anything bigger
    // uses the multipart path (uploadLargeFile) instead. 10MB, matching what
    // the backend's presigned-URL/multipart split is tuned for.
    private nonisolated static let chunkSize = 10 * 1024 * 1024

    // The multipart path for one file over chunkSize: split it into
    // chunkSize-sized pieces, upload each in parallel, then tell the server
    // to stitch them together. Only returns true if every single piece and
    // the final stitch-together both succeeded.
    private func uploadLargeFile(content: Data, packageId: String, fileId: String, lastMod: Int64) async -> Bool {
        guard let start = await SyncAPI.startMultipart(packageId: packageId, fileId: fileId, lastMod: lastMod, size: content.count, authToken: authToken) else { return false }
        
        let results = await withTaskGroup(of: CompletedPart?.self) { group in
            for target in start.parts {
                group.addTask {
                    let startOffset = (target.partNumber - 1) * Self.chunkSize
                    let endOffset = min(startOffset + Self.chunkSize, content.count)
                    let chunk = content.subdata(in: startOffset..<endOffset)
                    
                    guard let eTag = await SyncAPI.putPart(content: chunk, to: target.url) else { return nil }
                    return CompletedPart(partNumber: target.partNumber, eTag: eTag)
                }
            }
            
            var collected: [CompletedPart] = []
            for await result in group {
                if let result {
                    collected.append(result)
                }
            }
            return collected
        }
        guard results.count == start.parts.count else { return false }
        
        guard await SyncAPI.completeMultipart(packageId: packageId, fileId: fileId, uploadId: start.uploadId, parts: results, authToken: authToken) != nil else { return false }

        return true
    }
    
    // Runs for as long as the returned Task isn't cancelled, renewing the lock
    // every 5 minutes so a slow upload doesn't lose it to expiry. If a
    // heartbeat is ever rejected, marks the lock lost rather than retrying —
    // uploadNotebook checks lockState.lost before committing and bails if so.
    // Cancelled by releaseAndStop() once the upload is done.
    private func startHeartbeat(packageId: String, lockState: LockState) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if Task.isCancelled { break }
                
                let currentEtag = await lockState.etag
                guard let response = await SyncAPI.heartbeatLock(packageId: packageId, etag: currentEtag, authToken: authToken),
                      response.renewed, let newEtag = response.etag else {
                    await lockState.markLost()
                    break
                }
                await lockState.update(newEtag)
            }
        }
    }
}
