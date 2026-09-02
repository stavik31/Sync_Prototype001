import Foundation

protocol SyncRemoteStore {
    func isAvailable() async -> Bool
    func accountDetails() async -> AccountDetails?
    func listNotebooks() async -> [RemoteNode]
    func maxVersionNotebook(documentId: String) async -> RemoteNode?
    func downloadNotebook(node: RemoteNode, destination: URL, conflictFlow: Bool) async -> DownloadOutcome
    func readTombstones() async -> [Tombstone]
    func uploadNotebook(entity: NotebookSyncInfo, stagedFolder: URL) async -> PublishOutcome
    func deleteNotebookRemote(entity: NotebookSyncInfo) async -> PublishOutcome
    func readFolderPlist(kind: FolderKind) async -> FolderPlistDownload?
    func writeFolderPlist(kind: FolderKind, file: URL, revisionToken: String?, modifiedAt: Int64)  async -> Bool
    func mapThrowable(_ error: Error) -> DriveSyncException
    func downloadDeletionListFile() async -> URL?
}
