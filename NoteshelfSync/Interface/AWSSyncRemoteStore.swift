import Foundation

struct AWSSyncRemoteStore: SyncRemoteStore {
    let authToken: String

    func isAvailable() async -> Bool {
        // Check whether a login token is saved right now — read
        // KeychainManager.load(key: "authToken") in Storage/KeychainManager.swift.
        // New one-liner, nothing to migrate.
        false
    }

    func accountDetails() async -> AccountDetails? {
        // Pull the account id out of `authToken` using AuthManager.userId(from:)
        // in AWS/AuthManager.swift — already exists, no network call needed.
        // Build an AccountDetails with that id; leave usedBytes/totalBytes nil,
        // no quota tracking exists yet.
        nil
    }

    func listNotebooks() async -> [RemoteNode] {
        // Migrate from: SyncAPI.listPackages(authToken:) in AWS/SyncAPI.swift.
        // Call it, default to [] on nil, then map each PackageMetadata into a
        // RemoteNode (id -> remoteId/documentId, path -> relativePath,
        // last_mod -> modifiedAt).
        []
    }

    func maxVersionNotebook(documentId: String) async -> RemoteNode? {
        // Migrate from: SyncAPI.getManifest(packageId:authToken:) in AWS/SyncAPI.swift,
        // passing documentId as packageId. Take just the `.package` field and map
        // it to a RemoteNode the same way as listNotebooks above.
        nil
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
        // Migrate from: UploadEngine.upload(notebook:packageId:authToken:) in
        // Logic/UploadEngine.swift — but restructured, not copy-pasted. That
        // function reads pages straight out of NotebookStore; this one only
        // ever sees a plain stagedFolder. Still need SyncAPI.getManifest first
        // to merge with the notebook's unchanged pages before calling
        // SyncAPI.commit, or commit will delete anything not in stagedFolder.
        // OPEN QUESTION: confirm whether stagedFolder holds only changed pages
        // (this assumption) or the whole notebook, before finishing this.
        PublishOutcome(status: .notStarted, syncInfo: entity)
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
