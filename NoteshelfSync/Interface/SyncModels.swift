import Foundation

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

enum DownloadStatus { case downloaded, remoteChanged, failed }
struct DownloadOutcome { let status: DownloadStatus; let message: String?}

enum PublishStatus { case notStarted, inProgress, uploaded, conflicted, deleted}
struct PublishOutcome { let status: PublishStatus; let syncInfo: NotebookSyncInfo }

struct Tombstone { let documentId: String; let deletedAt: Int64 }

enum FolderKind { case group, category }
struct FolderPlistDownload { let modifiedAt: Int64; let revisionToken: String?; let localFile: URL }

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
