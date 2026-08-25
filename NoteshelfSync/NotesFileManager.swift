import Foundation

struct NotesFileManager {
    
    static func fileURL(for notebook: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent("\(notebook).txt")
    }
    
    static func saveNote(for notebook: String, content: String) {
        let url = fileURL(for: notebook)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    static func loadNote(for notebook: String) -> String {
        let url = fileURL(for: notebook)
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        return ""
    }
    
    static func listNotebooks() -> [String] {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: documentsURL.path) else {
            return []
        }
        return files
            .filter { $0.hasSuffix(".txt") }
            .map { $0.replacingOccurrences(of: ".txt", with: "") }
    }
    
    static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    static func notebookURL(userId: String, notebook: String) -> URL {
        documentsURL()
            .appendingPathComponent(userId)
            .appendingPathComponent(notebook)
    }
    
    static func pageURL(userId: String, notebook: String, page: String) -> URL {
        notebookURL(userId: userId, notebook: notebook)
            .appendingPathComponent("\(page).rtf")
    }
    
    static func ensureNotebookFolder(userId: String, notebook: String) {
        let url = notebookURL(userId: userId, notebook: notebook)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
