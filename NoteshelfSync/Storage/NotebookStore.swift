import Foundation

// Everything to do with notebooks on disk: creating them, reading and writing
// pages, adding and deleting pages.
//
// Layout, for a notebook the user named "Physics":
//
//   Documents/
//     MyNotes/
//       Physics/
//         notebook.json          <- the notebook's uuid + its page order
//         Pages/
//           <page-uuid>.rtf      <- one file per page
//
// Two things worth knowing:
//
// 1. Page files are named by their uuid, not "Page1.rtf". The uuid IS the
//    identity — nothing else stores it. Page ORDER comes from notebook.json,
//    not from filenames, so inserting a page in the middle never renames files.
//
// 2. There's no last_mod stored anywhere. The filesystem already tracks when
//    each file was modified; lastMod(_:page:) reads that and converts it to the
//    unix-milliseconds format the server expects.
//
// The local layout deliberately differs from the server's, which is flat and
// uuid-keyed: {userId}/{notebook-uuid}/{page-uuid}.rtf

// What notebook.json holds.
//   id    - this notebook's uuid, used as its identity on the server
//   order - page uuids, in display order. This is the only place page order lives.
struct NotebookInfo: Codable {
    var id: String
    var order: [String]
}

struct NotebookStore {
    
    static func rootURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("MyNotes")
    }
    
    static func notebookURL(_ name: String) -> URL {
        rootURL().appendingPathComponent(name)
    }
    
    // The metadata file's path is fixed and deterministic — always
    // "<notebook folder>/notebook.json" — so finding it never requires
    // scanning the folder's contents.
    static func notebookJSONURL(_ name: String) -> URL {
        notebookURL(name).appendingPathComponent("notebook.json")
    }

    static func saveInfo(_ info: NotebookInfo, for name: String) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: notebookJSONURL(name), options: .atomic)
    }

    static func loadInfo(for name: String) -> NotebookInfo? {
        guard let data = try? Data(contentsOf: notebookJSONURL(name)) else { return nil }
        return try? JSONDecoder().decode(NotebookInfo.self, from: data)
    }
    
    // When this page was last written, as unix milliseconds.
    // Read from the filesystem rather than stored — the OS maintains it for free.
    // Returns 0 if the file doesn't exist.
    static func lastMod(_ notebook: String, page: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: pageURL(notebook, page: page).path)
        guard let date = attrs?[.modificationDate] as? Date else { return 0}
        return Int64(date.timeIntervalSince1970 * 1000)
    }
    
    static func pagesURL(_ name: String) -> URL {
        notebookURL(name).appendingPathComponent("Pages")
    }
    
    static func pageURL(_ notebook: String, page: String) -> URL {
        pagesURL(notebook).appendingPathComponent(page)
    }
    
    static func loadPage(_ notebook: String, page: String) -> String {
        (try? String(contentsOf: pageURL(notebook, page: page), encoding: .utf8)) ?? ""
    }
    
    static func savePage(_ notebook: String, page: String, content: String) {
        try? content.write(to: pageURL(notebook, page: page), atomically: true, encoding: .utf8)
    }
    
    // Creates a page and inserts it directly after the given position.
    // Returns the new page's index so the editor can jump straight to it.
    // Only notebook.json's order array changes — no files are renamed.
    static func addPage(to notebook: String, after index: Int) -> Int {
        guard var info = loadInfo(for: notebook) else { return index }
        
        let pageId = UUID().uuidString
        let newPage = pagesURL(notebook).appendingPathComponent("\(pageId).rtf")
        try? "".write(to: newPage, atomically: true, encoding: .utf8)
        
        let newIndex = min(index + 1, info.order.count)
        info.order.insert(pageId, at: newIndex)
        saveInfo(info, for: notebook)
        
        return newIndex
    }
    
    // Deletes a page — both the file and its entry in notebook.json.
    // Returns the index the editor should show next.
    // If it was the last remaining page, a fresh blank one is created so a
    // notebook is never empty.
    static func deletePage(from notebook: String, at index: Int) -> Int {
        guard var info = loadInfo(for: notebook) else { return 0}
        guard index >= 0 && index < info.order.count else { return index }
        
        let pageId = info.order[index]
        try? FileManager.default.removeItem(at: pageURL(notebook, page: "\(pageId).rtf"))
        info.order.remove(at: index)
        
        if info.order.isEmpty {
            let newId = UUID().uuidString
            let newPage = pagesURL(notebook).appendingPathComponent("\(newId).rtf")
            try? "".write(to: newPage, atomically: true, encoding: .utf8)
            info.order = [newId]
            saveInfo(info, for: notebook)
            return 0
        }
        
        saveInfo(info, for: notebook)
        return min(index, info.order.count - 1)
    }
    
    // Creates the folder structure, one blank first page, and notebook.json
    // with a fresh id. No validation on `name` — an empty or duplicate name
    // is accepted as-is (see CreateNotebookPopup's comment).
    static func createNotebook(named name: String) {
        try? FileManager.default.createDirectory(at: pagesURL(name), withIntermediateDirectories: true)

        let pageId = UUID().uuidString
        let firstPage = pagesURL(name).appendingPathComponent("\(pageId).rtf")
        try? "".write(to: firstPage, atomically: true, encoding: .utf8)

        let info = NotebookInfo(id: UUID().uuidString, order: [pageId])
        saveInfo(info, for: name)
    }

    // Removes the entire notebook folder (notebook.json, Pages/, everything)
    // from disk in one call — this is genuinely a full local delete, not just
    // an in-memory removal. It has no knowledge of the server, though: nothing
    // here tells AWS this notebook is gone (see
    // AWSSyncRemoteStore.deleteNotebookRemote, still a stub).
    static func deleteNotebook(named name: String) {
        try? FileManager.default.removeItem(at: notebookURL(name))
    }
    
    // Every notebook on disk, by name.
    // A folder counts as a notebook only if it contains a notebook.json —
    // that's what distinguishes one from any other folder that might be there.
    static func listNotebooks() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rootURL().path) else {
            return []
        }
        return names.filter { FileManager.default.fileExists(atPath: notebookJSONURL($0).path) }
    }

    // Same idea as lastMod, but for notebook.json itself rather than a page —
    // used to decide whether the notebook's metadata (its id/page order) needs
    // re-uploading, separately from any individual page.
    static func notebookInfoLastMod(_ name: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: notebookJSONURL(name).path)
        guard let date = attrs?[.modificationDate] as? Date else { return 0 }
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}
