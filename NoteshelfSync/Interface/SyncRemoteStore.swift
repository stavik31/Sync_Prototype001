import Foundation

// The contract every backend implementation has to satisfy — deliberately
// shaped to mirror the Android side's Kotlin sync interface, method for
// method, so a signature change here is a cross-team contract change even
// though AWSSyncRemoteStore is the only implementation that exists today.
//
// Nothing here requires every method to be functionally complete — a given
// implementation can stub out methods it hasn't built yet (AWSSyncRemoteStore
// currently implements 5 of these 12 for real; see its own file for which).
protocol SyncRemoteStore {
    // Cheap, local check that this store has enough to attempt a call — not
    // a guarantee the backend will actually accept it.
    func isAvailable() async -> Bool

    // Whatever account info the backend can provide about the current user.
    func accountDetails() async -> AccountDetails?

    // Every notebook the backend currently holds for this user.
    func listNotebooks() async -> [RemoteNode]

    // One notebook's current state on the backend, by id.
    func maxVersionNotebook(documentId: String) async -> RemoteNode?

    // Fetches one notebook's contents down to `destination`. conflictFlow
    // signals this is happening as part of resolving a conflict, not a
    // routine sync, in case an implementation needs to behave differently.
    func downloadNotebook(node: RemoteNode, destination: URL, conflictFlow: Bool) async -> DownloadOutcome

    // Every deletion the backend knows about, so a device that missed one can
    // catch up without a full re-scan.
    func readTombstones() async -> [Tombstone]

    // Publishes everything staged in `stagedFolder` as the new state of
    // `entity`. Implementations are expected to make this atomic from the
    // caller's point of view — either the whole notebook updates, or nothing does.
    func uploadNotebook(entity: NotebookSyncInfo, stagedFolder: URL) async -> PublishOutcome

    // Tells the backend this notebook is gone, so other devices learn about
    // the deletion instead of just seeing it vanish from one device's list.
    func deleteNotebookRemote(entity: NotebookSyncInfo) async -> PublishOutcome

    // Folder/category structure — see FolderKind's comment in SyncModels.swift.
    func readFolderPlist(kind: FolderKind) async -> FolderPlistDownload?
    func writeFolderPlist(kind: FolderKind, file: URL, revisionToken: String?, modifiedAt: Int64)  async -> Bool

    // Turns whatever error shape a backend produces into the one typed error
    // the rest of the app knows how to handle.
    func mapThrowable(_ error: Error) -> DriveSyncException

    // Writes readTombstones()'s data out to a local file, for callers that
    // want it as a file rather than an in-memory array.
    func downloadDeletionListFile() async -> URL?
}
