import Foundation

struct UploadEngine {

    // Uploads every notebook that has changed since its last successful upload.
    // Called by the Upload button.
    static func uploadAll(userId: String, authToken: String) async {
        
        let serverPackages = await SyncAPI.listPackages(authToken: authToken) ?? []
        
        for notebook in NotebookStore.listNotebooks() {
            guard let info = NotebookStore.loadInfo(for: notebook) else { continue }
            
            let localMod = notebookLastMod(notebook)
            let record = SyncTable.record(for: notebook)
            
            guard let record else {
                _ = await upload(notebook: notebook, packageId: info.id, authToken: authToken)
                continue
            }
            
            if localMod == record.lastMod {
                continue
            }
            
            let serverMod = serverPackages.first(where: { $0.id == record.packageId})?.last_mod
            
            if let serverMod, serverMod != record.lastMod {
                print("conflict: \(notebook), skipped")
                continue
            }
            
            _ = await upload(notebook: notebook, packageId: record.packageId, authToken: authToken)
        }
    }

    // A notebook has no timestamp of its own — it's the newest of its pages' file dates.
    // Returns 0 if the notebook has no pages.
    static func notebookLastMod(_ notebook: String) -> Int64 {

        guard let info = NotebookStore.loadInfo(for: notebook) else { return 0 }
        
        var newest: Int64 = 0
        
        for pageId in info.order {
            let mod = NotebookStore.lastMod(notebook, page: "\(pageId).rtf")
            if mod > newest {
                newest = mod
            }
        }
        return newest
    }

    // Uploads one notebook end to end. Returns true only if commit succeeded.
    static func upload(notebook: String, packageId: String, authToken: String) async -> Bool {

        guard let info = NotebookStore.loadInfo(for: notebook) else { return false }
        
        let serverManifest = await SyncAPI.getManifest(packageId: packageId, authToken: authToken)
        let serverPages = serverManifest?.files ?? []
        
        let stagingFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingFolder) }
        
        for pageId in info.order {
            let localMod = NotebookStore.lastMod(notebook, page: "\(pageId).rtf")
            let serverMod = serverPages.first(where: { $0.id == pageId})?.last_mod
            if serverMod != localMod {
                let content = NotebookStore.loadPage(notebook, page: "\(pageId).rtf")
                try? content.write(to: stagingFolder.appendingPathComponent(pageId), atomically: true, encoding: .utf8)
            }
        }
        
        let notebookMod = notebookLastMod(notebook)
        
        let entity = NotebookSyncInfo(
            documentId: packageId, driveId: nil, modified: notebookMod, deleted: false,
            version: nil, crtDevice: nil, lstUpdDevice: nil, relativePath: "MyNotes/\(notebook)",
            lstSyncDate: nil, errorCode: nil, errorDescription: nil, conflicted: false,
            forceFetchOrPublish: false, accountId: nil, deletionTimestamp: nil,
            documentVersion: nil, crtDt: nil
        )
        
        let remoteStore = AWSSyncRemoteStore(authToken: authToken)
        let outcome = await remoteStore.uploadNotebook(entity: entity, stagedFolder: stagingFolder)
        guard outcome.status == .uploaded else { return false }
        
        SyncTable.save(notebook: notebook, packageId: packageId, lastMod: notebookMod)
        return true
    }
}
