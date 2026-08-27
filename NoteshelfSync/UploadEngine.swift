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

        // read the page order         -> NotebookStore.loadInfo(for:)
        // for each page uuid, get its file date  -> NotebookStore.lastMod(_:page:)
        // return the largest

        return 0
    }

    // Uploads one notebook end to end. Returns true only if commit succeeded.
    static func upload(notebook: String, packageId: String, authToken: String) async -> Bool {

        // 1. build [PrepareFile] — one per page, id + last_mod

        // 2. SyncAPI.prepare(...)  -> gives back an upload url per page

        // 3. for each returned UploadTarget:
        //      read that page's content  -> NotebookStore.loadPage(_:page:)
        //      send it                   -> put(content:to:)
        //      stop if any PUT fails

        // 4. build Manifest — one FileEntry per page, with id + path + last_mod
        //    (path is the notebook-relative one, e.g. "/Pages/Page1.rtf")

        // 5. SyncAPI.commit(...)  — path is the notebook's display path

        // 6. only if commit succeeded, SyncTable.save(...)

        return false
    }

    // Sends one page's content to a presigned url.
    // No Authorization header — permission is already inside the url.
    static func put(content: String, to urlString: String) async -> Bool {

        return false
    }
}
