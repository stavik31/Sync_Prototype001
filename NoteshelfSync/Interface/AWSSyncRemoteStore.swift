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

    // Ported from Madhav's AppSync repo (Download.swift: downloadFiles/
    // downloadFileToStaging/promoteCompletePackageToMainStorage), adapted here.
    // Two deliberate differences from his version, so they don't look like
    // mistakes if he reads this later:
    //
    // 1. No `packagesDirectory`/`packagePath`-building. His code builds the
    //    local package path itself from a raw path string (and has to guard
    //    against double-nesting "MyNotes/X" inside it). Doesn't apply here:
    //    `destination` is already the final resolved folder, handed in by
    //    the caller — there's nothing to build.
    //
    // 2. No general SyncTable update/verify calls. His `downloadFiles`
    //    updates and verifies SyncTable itself. Here, that's left for
    //    DownloadEngine.syncNotebook (the decision-logic layer that calls
    //    this method) — same split as UploadEngine deciding what to upload
    //    vs. this uploadNotebook just doing it. The one SyncTable touch his
    //    version has inside the final version check (marking a conflict) is
    //    handled here by returning DownloadOutcome(status: .remoteChanged,
    //    ...) instead — that status exists on this protocol specifically for
    //    "the server moved since we started, re-check before overwriting."
    //
    // Everything else — the copy-existing-package-into-staging step, the
    // final server version re-check before promoting, the staging
    // mechanics, the backup/restore promotion, the modification-date step,
    // the print statements — matches his structure closely, including the
    // copy-existing step's known limitation: it never removes a page that
    // was deleted server-side, since a deleted page just isn't in the new
    // manifest to overwrite it. Kept as-is per instruction, to fix later.
    //
    // The token (self.authToken here vs. his AuthManager.shared) and the
    // network calls (SyncAPI.getManifest/download, which go through this
    // app's 401-refresh handling, vs. his raw URLSession calls) are the two
    // changes that are non-negotiable regardless of the above.
    func downloadNotebook(node: RemoteNode, destination: URL, conflictFlow: Bool) async -> DownloadOutcome {
            guard let documentId = node.documentId else {
                return DownloadOutcome(status: .failed, message: "node has no documentId")
            }

            guard let manifest = await SyncAPI.getManifest(packageId: documentId, authToken: authToken) else {
                return DownloadOutcome(status: .failed, message: "could not get manifest")
            }

            let operationStagingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let packageStagingDirectory = operationStagingDirectory.appendingPathComponent(destination.lastPathComponent, isDirectory: true)
            let packageExists = FileManager.default.fileExists(atPath: destination.path)

            do {
                try FileManager.default.createDirectory(at: operationStagingDirectory, withIntermediateDirectories: true)

                if packageExists {
                    print("")
                    print("📋 EXISTING PACKAGE")
                    print("Copying ONLY package into staging")
                    print("")
                    print("FROM:")
                    print(destination.path)
                    print("")
                    print("TO:")
                    print(packageStagingDirectory.path)
                    print("")

                    try FileManager.default.copyItem(at: destination, to: packageStagingDirectory)

                    print("✅ Existing package copied to staging")

                } else {
                    print("")
                    print("🆕 NEW PACKAGE")
                    print("Creating package in staging")
                    print("")

                    try FileManager.default.createDirectory(at: packageStagingDirectory, withIntermediateDirectories: true)

                    print("✅ Empty package created in staging")
                }

                for file in manifest.files {
                    print("")
                    print("⬇️ Downloading file:", file.id)
                    print("Path:", file.path)

                    guard let downloadedFile = await SyncAPI.download(packageId: documentId, fileId: file.id, authToken: authToken) else {
                        print("❌ Could not get download information")
                        print("File:", file.id)
                        removeStagingDirectory(operationStagingDirectory)
                        return DownloadOutcome(status: .failed, message: "missing download URL for \(file.id)")
                    }

                    guard await downloadFileToStaging(downloadedFile: downloadedFile, expectedPath: file.path, packageStagingDirectory: packageStagingDirectory) else {
                        print("❌ File failed to download")
                        print("File:", file.id)
                        removeStagingDirectory(operationStagingDirectory)
                        return DownloadOutcome(status: .failed, message: "download failed for \(file.id)")
                    }

                    print("✅ File successfully updated in staging:", file.id)
                }

                print("")
                print("=====================================")
                print("🔍 FINAL SERVER VERSION CHECK")
                print("Package:", documentId)
                print("Original server lastMod:", manifest.package.last_mod)
                print("=====================================")
                print("")

                guard let latestPackages = await SyncAPI.listPackages(authToken: authToken) else {
                    print("❌ Could not get latest server metadata")
                    print("🛑 Package promotion cancelled")
                    print("🛑 Main package was NOT changed")
                    removeStagingDirectory(operationStagingDirectory)
                    return DownloadOutcome(status: .failed, message: "could not verify latest server metadata")
                }

                guard let latestServerPackage = latestPackages.first(where: { $0.id == documentId }) else {
                    print("❌ Package no longer exists on server")
                    print("🛑 Package promotion cancelled")
                    print("🛑 Main package was NOT changed")
                    removeStagingDirectory(operationStagingDirectory)
                    return DownloadOutcome(status: .failed, message: "package no longer exists on server")
                }

                print("Latest server lastMod:", latestServerPackage.last_mod)

                if latestServerPackage.last_mod != manifest.package.last_mod {
                    print("")
                    print("🚨🚨🚨 SERVER VERSION CHANGED 🚨🚨🚨")
                    print("")
                    print("Someone modified/uploaded this package while it was downloading.")
                    print("")
                    print("🛑 DOWNLOAD CANCELLED")
                    print("🛑 MAIN PACKAGE WAS NOT TOUCHED")
                    print("🧹 STAGING PACKAGE WILL BE DELETED")
                    print("")

                    removeStagingDirectory(operationStagingDirectory)
                    return DownloadOutcome(status: .remoteChanged, message: "server changed during download")
                }

                print("")
                print("✅ FINAL SERVER VERSION CHECK PASSED")
                print("🚚 Safe to promote package")
                print("")

                guard promoteCompletePackageToMainStorage(destination: destination, packageStagingDirectory: packageStagingDirectory, operationStagingDirectory: operationStagingDirectory) else {
                    print("❌ Failed to promote complete package")
                    removeStagingDirectory(operationStagingDirectory)
                    return DownloadOutcome(status: .failed, message: "could not promote package")
                }

                for file in manifest.files {
                    let localFileURL = destination.appendingPathComponent(file.path)
                    guard FileManager.default.fileExists(atPath: localFileURL.path) else { continue }
                    setModificationDate(at: localFileURL, unixTimestampMilliseconds: manifest.package.last_mod)
                }

                removeStagingDirectory(operationStagingDirectory)

                return DownloadOutcome(status: .downloaded, message: nil)

            } catch {
                print("❌ Package download error:")
                print(error.localizedDescription)
                removeStagingDirectory(operationStagingDirectory)
                return DownloadOutcome(status: .failed, message: error.localizedDescription)
            }
        }

        private func downloadFileToStaging(downloadedFile: DownloadedFile, expectedPath: String, packageStagingDirectory: URL) async -> Bool {
            guard let url = URL(string: downloadedFile.downloadUrl) else {
                print("❌ Invalid presigned URL")
                return false
            }

            guard let scheme = url.scheme, scheme == "https" || scheme == "http" else {
                print("❌ Download URL is not HTTP/HTTPS")
                return false
            }

            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid S3 response")
                    return false
                }

                guard httpResponse.statusCode == 200 else {
                    print("❌ S3 download failed:", httpResponse.statusCode)
                    return false
                }

                let stagedFileURL = packageStagingDirectory.appendingPathComponent(expectedPath)
                let parentDirectory = stagedFileURL.deletingLastPathComponent()

                try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

                if FileManager.default.fileExists(atPath: stagedFileURL.path) {
                    print("♻️ Replacing file INSIDE staging")
                    print(stagedFileURL.path)
                    try FileManager.default.removeItem(at: stagedFileURL)
                }

                try FileManager.default.moveItem(at: temporaryURL, to: stagedFileURL)

                print("📦 File placed in staging:")
                print(stagedFileURL.path)

                return true

            } catch {
                print("❌ S3 download/staging error:")
                print(error.localizedDescription)
                return false
            }
        }

        private func promoteCompletePackageToMainStorage(destination: URL, packageStagingDirectory: URL, operationStagingDirectory: URL) -> Bool {
            let backupDirectory = operationStagingDirectory.appendingPathComponent("OldPackageBackup", isDirectory: true)

            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

                guard FileManager.default.fileExists(atPath: packageStagingDirectory.path) else {
                    print("❌ Staging package does not exist")
                    print(packageStagingDirectory.path)
                    return false
                }

                if FileManager.default.fileExists(atPath: destination.path) {
                    print("")
                    print("📦 Moving old Main package to backup")
                    print("FROM:", destination.path)
                    print("TO:", backupDirectory.path)

                    try FileManager.default.moveItem(at: destination, to: backupDirectory)

                    print("✅ Old Main package backed up")
                }

                print("")
                print("🚚 Moving COMPLETE package to Main")
                print("FROM:", packageStagingDirectory.path)
                print("TO:", destination.path)

                do {
                    try FileManager.default.moveItem(at: packageStagingDirectory, to: destination)
                    print("")
                    print("✅ COMPLETE PACKAGE promoted to Main")

                } catch {
                    print("")
                    print("❌ Could not move staging package to Main")
                    print(error.localizedDescription)

                    if FileManager.default.fileExists(atPath: backupDirectory.path) {
                        print("♻️ Restoring old Main package")
                        try? FileManager.default.moveItem(at: backupDirectory, to: destination)
                        print("✅ Old Main package restored")
                    }

                    return false
                }

                if FileManager.default.fileExists(atPath: backupDirectory.path) {
                    try? FileManager.default.removeItem(at: backupDirectory)
                    print("🧹 Old package backup removed")
                }

                return true

            } catch {
                print("")
                print("❌ Complete package promotion error:")
                print(error.localizedDescription)

                if !FileManager.default.fileExists(atPath: destination.path),
                   FileManager.default.fileExists(atPath: backupDirectory.path) {
                    print("♻️ Attempting to restore old Main package")
                    try? FileManager.default.moveItem(at: backupDirectory, to: destination)
                }

                return false
            }
        }

        private func removeStagingDirectory(_ operationStagingDirectory: URL) {
            do {
                if FileManager.default.fileExists(atPath: operationStagingDirectory.path) {
                    try FileManager.default.removeItem(at: operationStagingDirectory)
                    print("🧹 Staging area removed")
                }
            } catch {
                print("⚠️ Could not completely remove staging")
                print(error.localizedDescription)
            }
        }

        private func setModificationDate(at url: URL, unixTimestampMilliseconds: Int64) {
            let seconds = TimeInterval(unixTimestampMilliseconds) / 1000
            let date = Date(timeIntervalSince1970: seconds)

            do {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
                print("🕒 Local modification date updated")
                print("File:", url.path)
            } catch {
                print("⚠️ Could not set modification date")
                print(error.localizedDescription)
            }
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
            let currentEtag = await lockState.etag
            guard let prep = await SyncAPI.prepare(packageId: entity.documentId, files: changed, authToken: authToken, lockEtag: currentEtag) else {
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
        let commitEtag = await lockState.etag
        guard await SyncAPI.commit(packageId: entity.documentId, path: entity.relativePath,
                                   lastMod: entity.modified, manifest: Manifest(files: Array(manifestById.values)), authToken: authToken, lockEtag: commitEtag) != nil else {
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
