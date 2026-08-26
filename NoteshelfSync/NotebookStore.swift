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
