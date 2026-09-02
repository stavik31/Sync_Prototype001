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
        
        var changed: [PrepareFile] = []
        for pageId in info.order {
            let localMod = NotebookStore.lastMod(notebook, page: "\(pageId).rtf")
            let serverMod = serverPages.first(where: { $0.id == pageId})?.last_mod
            if serverMod != localMod {
                changed.append(PrepareFile(id: pageId, last_mod: localMod))
            }
        }
        
        if !changed.isEmpty {
            guard let prep = await SyncAPI.prepare(packageId: packageId, files: changed, authToken: authToken) else {
                return false
            }
            
            for target in prep.uploads {
                let content = NotebookStore.loadPage(notebook, page: "\(target.id).rtf")
                if await put(content: content, to: target.url) == false {
                    return false
                }
            }
        }
        
        var files: [FileEntry] = []
        for pageId in info.order {
            files.append(FileEntry(id: pageId, path: "/Pages/\(pageId).rtf", last_mod: NotebookStore.lastMod(notebook, page: "\(pageId).rtf")))
        }
        
        let notebookMod = notebookLastMod(notebook)
        
        guard await SyncAPI.commit(
            packageId: packageId,
            path: "MyNotes/\(notebook)",
            lastMod: notebookMod,
            manifest: Manifest(files: files),
            authToken: authToken
        ) != nil else { return false }
        
        SyncTable.save(notebook: notebook, packageId: packageId, lastMod: notebookMod)
        return true
    }

    // Sends one page's content to a presigned url.
    // No Authorization header — permission is already inside the url.
    static func put(content: String, to urlString: String) async -> Bool {

        guard let url = URL(string: urlString) else { return false }

                var request = URLRequest(url: url)
                request.httpMethod = "PUT"
                request.httpBody = content.data(using: .utf8)

                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse else { return false }

                    if http.statusCode != 200 {
                        print("put failed: \(http.statusCode)")
                        return false
                    }

                    return true

                } catch {
                    print("put error: \(error)")
                    return false
                }
    }
}
