import Foundation

struct UploadEngine {

    // Uploads every notebook that has changed since its last successful upload.
    // Called by the Upload button.
    //
    // Note: userId isn't actually referenced anywhere in this function's body
    // right now — every lookup here goes by notebook name/packageId instead.
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
                SyncTable.markConflict(notebook: notebook, conflict: true)
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

    // Uploads one notebook end to end: diffs every page (and the notebook's
    // own metadata) against what the server already has, stages only what
    // changed into a temp folder, then hands that folder to
    // AWSSyncRemoteStore.uploadNotebook to actually publish it. Returns true
    // only if that publish (commit) succeeded.
    static func upload(notebook: String, packageId: String, authToken: String) async -> Bool {

        guard let info = NotebookStore.loadInfo(for: notebook) else { return false }

        let serverManifest = await SyncAPI.getManifest(packageId: packageId, authToken: authToken)
        let serverPages = serverManifest?.files ?? []

        // Everything staged here is temporary — cleaned up via defer whether
        // the upload below succeeds or fails.
        let stagingFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: stagingFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingFolder) }

        // Stage each page whose mod time doesn't match what the server has —
        // unchanged pages are left out entirely, so AWSSyncRemoteStore only
        // ever sees files that actually need uploading.
        for pageId in info.order {
            let localMod = NotebookStore.lastMod(notebook, page: "\(pageId).rtf")
            let serverMod = serverPages.first(where: { $0.id == pageId})?.last_mod
            if serverMod != localMod {
                let content = NotebookStore.loadPage(notebook, page: "\(pageId).rtf")
                let stagedURL = stagingFolder.appendingPathComponent(pageId)
                try? content.write(to: stagedURL, atomically: true, encoding: .utf8)
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: Double(localMod) / 1000)],
                    ofItemAtPath: stagedURL.path
                )
            }
        }
        
        // Same idea, but for the notebook's own metadata file (order + id) —
        // staged separately since it isn't one of info.order's pages.
        let infoLocalMod = NotebookStore.notebookInfoLastMod(notebook)
        let infoServerMod = serverPages.first(where: { $0.id == info.id })?.last_mod
        if infoServerMod != infoLocalMod, let infoData = try? JSONEncoder().encode(info) {
            let stagedInfoURL = stagingFolder.appendingPathComponent("notebook.json")
            try? infoData.write(to: stagedInfoURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(infoLocalMod) / 1000 )],
                ofItemAtPath: stagedInfoURL.path
            )
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

        // Only recorded here, after commit has actually succeeded — matches
        // SyncTable's own rule (see its header) that writing early would make
        // the next upload silently believe it already sent something it didn't.
        SyncTable.save(notebook: notebook, packageId: packageId, lastMod: notebookMod)
        return true
    }
}
