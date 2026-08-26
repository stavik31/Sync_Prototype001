import Foundation

struct LocalManifest: Codable {
    var id: String
    var files: [FileEntry]
}

struct NotebookStore {
    
    static func rootURL() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("MyNotes")
    }
    
    static func notebookURL(_ name: String) -> URL {
        rootURL().appendingPathComponent(name)
    }
    
    static func pagesURL(_ name: String) -> URL {
        notebookURL(name).appendingPathComponent("Pages")
    }
    
    static func pageURL(_ notebook: String, page: String) -> URL {
        pagesURL(notebook).appendingPathComponent(page)
    }
    
    static func firstPageName(in notebook: String) -> String {
        guard let manifest = loadManifest(for: notebook),
                let first = manifest.files.first else { return "Page1.rtf" }
        return (first.path as NSString).lastPathComponent
    }
    
    static func loadPage(_ notebook: String, page: String) -> String {
        (try? String(contentsOf: pageURL(notebook, page: page), encoding: .utf8)) ?? ""
    }
    
    static func savePage(_ notebook: String, page: String, content: String) {
        try? content.write(to: pageURL(notebook, page: page), atomically: true, encoding: .utf8)
        touch(notebook: notebook, page: page)
    }
    
    static func touch(notebook: String, page: String) {
        guard var manifest = loadManifest(for: notebook) else {return}
        guard let i = manifest.files.firstIndex(where: {
            ($0.path as NSString).lastPathComponent == page
        }) else {return}
        manifest.files[i].last_mod = now()
        saveManifest(manifest, for: notebook)
    }
    
    static func manifestURL(_ name: String) -> URL {
        notebookURL(name).appendingPathComponent("Manifest.json")
    }
    
    static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    static func createNotebook(named name: String) {
        try? FileManager.default.createDirectory(at: pagesURL(name), withIntermediateDirectories: true)
        
        let firstPage = pagesURL(name).appendingPathComponent("Page1.rtf")
        try? "".write(to: firstPage, atomically: true, encoding: .utf8)
        
        let manifest = LocalManifest(
            id: UUID().uuidString,
            files: [
                FileEntry(id: UUID().uuidString, path: "/Pages/Page1.rtf", last_mod: now())
            ]
        )
        saveManifest(manifest, for: name)
    }
    
    static func saveManifest(_ manifest: LocalManifest, for name: String) {
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        try? data.write(to: manifestURL(name), options: .atomic)
    }
    
    static func loadManifest(for name: String) -> LocalManifest? {
        guard let data = try? Data(contentsOf:manifestURL(name)) else { return nil }
        return try? JSONDecoder().decode(LocalManifest.self, from: data)
    }
    
    static func listNotebooks() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rootURL().path) else {
            return []
        }
        return names.filter {FileManager.default.fileExists(atPath: manifestURL($0).path)}
    }
}
