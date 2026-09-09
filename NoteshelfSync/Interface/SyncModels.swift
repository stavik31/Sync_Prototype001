import Foundation

// The neutral vocabulary SyncRemoteStore's methods speak in — shapes any
// backend implementation (AWS today, potentially others later) has to
// produce and consume, independent of how that backend actually works.
//
// Most fields are optional. That's deliberate: not every backend will have
// something to put in every field (AWSSyncRemoteStore, for instance, leaves
// most of RemoteNode's device/version fields nil, since this backend doesn't
// track them), so the contract only guarantees the shape, not that every
// value is populated.

struct RemoteNode {
    let remoteId: String?
    let name: String?
    let documentId: String?
    let driveId: String?
    let version: Int64?
    let documentVersion: String?
    let syncVersion: Int64?
    let relativePath: String
    let createdDevice: String?
    let lastUpdDevice: String?
    let createdAt: Int64?
    let modifiedAt: Int64?
    let revisionToken: String?
    let isFolder: Bool
}

struct AccountDetails {
    let accountId: String?
    let name: String?
    let usedBytes: Int64?
    let totalBytes: Int64?
}

// remoteChanged means the download was skipped because the server's copy has
// moved since whatever version the caller thought it was fetching — not a
// failure, just "re-check before you overwrite something newer."
enum DownloadStatus { case downloaded, remoteChanged, failed }
struct DownloadOutcome { let status: DownloadStatus; let message: String?}

// notStarted covers every "didn't even try" case — lock not acquired,
// prepare failed, network error — not just "not yet begun".
enum PublishStatus { case notStarted, inProgress, uploaded, conflicted, deleted}
struct PublishOutcome { let status: PublishStatus; let syncInfo: NotebookSyncInfo }

// A record that a notebook was deleted, for backends that track deletions
// separately so other devices can learn about them without a full re-scan.
struct Tombstone { let documentId: String; let deletedAt: Int64 }

// Folder/category sync — this app has no folder concept at all right now, so
// nothing currently produces or consumes these; they're here for backends
// that do organize notebooks into folders.
enum FolderKind { case group, category }
struct FolderPlistDownload { let modifiedAt: Int64; let revisionToken: String?; let localFile: URL }

// One notebook's sync state as the rest of the app understands it — this is
// what SyncRemoteStore's upload/delete methods take and hand back, separate
// from RemoteNode (which describes what the *server* currently has).
struct NotebookSyncInfo {
    var documentId: String
    var driveId: String?
    var modified: Int64
    var deleted: Bool
    var version: Int64?
    var crtDevice: String?
    var lstUpdDevice: String?
    var relativePath: String
    var lstSyncDate: Int64?
    var errorCode: String?
    var errorDescription: String?
    var conflicted: Bool
    var forceFetchOrPublish: Bool
    var accountId: String?
    var deletionTimestamp: Int64?
    var documentVersion: String?
    var crtDt: Int64?
}

struct DriveSyncException: Error { let message: String }
