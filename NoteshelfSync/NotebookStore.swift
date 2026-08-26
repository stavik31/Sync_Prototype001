import Foundation

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
    
    static func notebookJSONURL(_ name: String) -> URL {
        notebookURL(name).appendingPathComponent("notebook.json")
    }
    
    static func saveInfo(_ info: NotebookInfo, for name: String) {
        guard let data = try? JSONEncoder().encode(info) else { return }
        try? data.write(to: notebookJSONURL(name), options: .atomic)
    }
    
    static func loadInfo(for name: String) -> NotebookInfo? {
        guard let data = try? Data(contentsOf: notebookJSONURL(name)) else { return nil}
        return try? JSONDecoder().decode(NotebookInfo.self, from: data)
    }
    
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
    
    static func createNotebook(named name: String) {
        try? FileManager.default.createDirectory(at: pagesURL(name), withIntermediateDirectories: true)
        
        let pageId = UUID().uuidString
        let firstPage = pagesURL(name).appendingPathComponent("\(pageId).rtf")
        try? "".write(to: firstPage, atomically: true, encoding: .utf8)
        
        let info = NotebookInfo(id: UUID().uuidString, order: [pageId])
        saveInfo(info, for: name)
    }
    
    static func listNotebooks() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: rootURL().path) else {
            return []
        }
        return names.filter {FileManager.default.fileExists(atPath: notebookJSONURL($0).path)}
    }
}
